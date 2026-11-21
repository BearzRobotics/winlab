//! Chimera Linux lab VMs (docs/decisions/0009-chimera-lab.md). Chimera ships live ISOs and rootfs tarballs but no
//! cloud image, so a lab VM is built by installing from the official live ISO, following the official procedure,
//! with no human at the keyboard:
//!
//!   1. QEMU boots the ISO's own kernel and initrd directly, with `console=ttyS0`, so the live system prints its
//!      boot and its login prompt on a serial port that WinLab reads over a local TCP socket.
//!   2. WinLab logs in (the live image's documented root login), mounts a small seed CD that WinLab built, and runs
//!      `install.sh` from it. The scripts in `chimera/` do the install and print progress lines starting "WL: ".
//!   3. On success the live system is powered off and the installed disk is booted.
//!
//! This file is pure: it builds the seed and implements the serial conversation as a state machine fed with bytes
//! (so it is unit-tested with a simulated transcript, no VM needed). Starting QEMU and the TCP socket is main.zig's job.
const std = @import("std");
const iso9660 = @import("iso9660.zig");

pub const install_script = @embedFile("chimera/install.sh");
pub const chroot_script = @embedFile("chimera/chroot.sh");

pub const seed_label = "WLSEED";

/// The live ISO's own kernel command line (from its boot/grub/grub.cfg) plus a serial console.
pub const live_cmdline = "boot=live live-media=CHIMERA_LIVE dinit_skip_volumes init=/usr/bin/init loglevel=4 console=ttyS0,115200";

/// The documented login of the live image (printed in its own banner). It exists only in the live session.
pub const live_user = "root";
pub const live_password = "chimera";

/// The ISO's kernel and initrd, as paths inside the ISO (extracted with the system's tar.exe).
pub const iso_kernel = "live/vmlinuz";
pub const iso_initrd = "live/initrd";

pub const Options = struct {
    /// Host name (letters, digits, hyphens; 1..63).
    hostname: []const u8,
    user: []const u8 = "labadmin",
    /// Console password; also stored (hashed in the guest) for root. SSH password logins stay off.
    password: []const u8,
    /// One OpenSSH public key line.
    ssh_public_key: []const u8,
};

pub const Error = error{ InvalidHostname, InvalidUser, InvalidPassword, InvalidKey, OutOfMemory } || std.Io.Writer.Error || iso9660.Error;

fn validName(s: []const u8, max: usize) bool {
    if (s.len == 0 or s.len > max) return false;
    for (s, 0..) |c, i| switch (c) {
        'a'...'z', '0'...'9' => {},
        '-', '_' => if (i == 0) return false,
        else => return false,
    };
    return true;
}

/// Values end up inside single quotes in a shell file, so a quote, a backslash or a control character is refused.
fn plainValue(s: []const u8) bool {
    for (s) |c| if (c < 0x20 or c == 0x7F or c == '\'' or c == '\\') return false;
    return true;
}

pub fn writeConf(o: Options, w: *std.Io.Writer) Error!void {
    if (!validName(o.hostname, 63)) return error.InvalidHostname;
    if (!validName(o.user, 32)) return error.InvalidUser;
    if (o.password.len < 8 or o.password.len > 100 or !plainValue(o.password)) return error.InvalidPassword;
    if (!std.mem.startsWith(u8, o.ssh_public_key, "ssh-") or o.ssh_public_key.len > 600 or !plainValue(o.ssh_public_key)) return error.InvalidKey;
    try w.print("HOST='{s}'\nLABUSER='{s}'\nPASS='{s}'\nPUBKEY='{s}'\n", .{ o.hostname, o.user, o.password, o.ssh_public_key });
}

/// The seed CD (volume label WLSEED): `install.sh`, `chroot.sh` and `wl.conf`. Caller frees.
pub fn buildSeed(gpa: std.mem.Allocator, o: Options) Error![]u8 {
    var conf: std.Io.Writer.Allocating = .init(gpa);
    defer conf.deinit();
    try writeConf(o, &conf.writer);
    return iso9660.build(gpa, seed_label, &.{
        .{ .name = "install.sh", .data = install_script },
        .{ .name = "chroot.sh", .data = chroot_script },
        .{ .name = "wl.conf", .data = conf.written() },
    });
}

// ---------------------------------------------------------------------------------------------
// The serial conversation
// ---------------------------------------------------------------------------------------------

pub const Step = enum {
    /// Waiting for "login:" on the serial console.
    wait_login,
    wait_password,
    /// Logged in; waiting for the shell prompt.
    wait_prompt,
    /// Probe sent; waiting for its output, which proves the shell is reading input.
    wait_ready,
    /// The install is running; progress lines are reported.
    running,
    finished_ok,
    finished_failed,
};

/// What runs in the live system once the shell is ready. `echo` of the command contains the text `WL-RC=$?`
/// verbatim, which never starts a line of output, so only the real result line is matched.
///
/// The install runs with stdin from /dev/null and its output through a pipe, never directly on the console TTY:
/// on a TTY, `apk del` asks "continue?" and draws a progress bar, and the install then waits for a keypress
/// forever (found the hard way: a hand-run background job had hidden it).
pub const run_command = "{ mkdir -p /seed && mount -t iso9660 -o ro /dev/sr1 /seed && sh /seed/install.sh /seed; echo \"WL-RC=$?\"; } </dev/null 2>&1 | cat\n";
/// The probe's own text contains `''` so the echoed command does not equal its output.
const probe_command = "echo WL-REA''DY\n";

const max_line = 4096;
const max_log = 256 * 1024;

pub const Driver = struct {
    gpa: std.mem.Allocator,
    step: Step = .wait_login,
    line: std.ArrayList(u8) = .empty,
    /// Everything the install printed (capped), for the failure report.
    log: std.ArrayList(u8) = .empty,
    exit_code: ?u32 = null,
    saw_ok: bool = false,
    /// Set when the conversation failed in a way that has a clear reason.
    failure: []const u8 = "",
    esc: enum { none, saw_esc, in_csi } = .none,

    pub fn init(gpa: std.mem.Allocator) Driver {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Driver) void {
        self.line.deinit(self.gpa);
        self.log.deinit(self.gpa);
    }

    pub fn done(self: *const Driver) bool {
        return self.step == .finished_ok or self.step == .finished_failed;
    }

    /// Feeds bytes read from the serial port. Text to send is appended to `reply`; each "WL: ..." progress line
    /// is appended (with a newline) to `progress`.
    pub fn feed(self: *Driver, bytes: []const u8, reply: *std.ArrayList(u8), progress: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        for (bytes) |b| {
            switch (self.esc) {
                .saw_esc => {
                    self.esc = if (b == '[') .in_csi else .none;
                    continue;
                },
                .in_csi => {
                    if ((b >= 'A' and b <= 'Z') or (b >= 'a' and b <= 'z')) self.esc = .none;
                    continue;
                },
                .none => {},
            }
            switch (b) {
                0x1b => self.esc = .saw_esc,
                '\r' => {},
                '\n' => try self.completeLine(reply, progress),
                else => if (self.line.items.len < max_line) try self.line.append(self.gpa, b),
            }
        }
        try self.checkPartial(reply);
    }

    fn completeLine(self: *Driver, reply: *std.ArrayList(u8), progress: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        defer self.line.clearRetainingCapacity();
        const line = self.line.items;
        switch (self.step) {
            .wait_prompt, .wait_password => if (std.mem.indexOf(u8, line, "Login incorrect") != null) {
                self.step = .finished_failed;
                self.failure = "the live system rejected its documented login (root, chimera)";
            },
            .wait_ready => if (std.mem.eql(u8, line, "WL-READY")) {
                try reply.appendSlice(self.gpa, run_command);
                self.step = .running;
            },
            .running => {
                if (self.log.items.len < max_log) {
                    try self.log.appendSlice(self.gpa, line);
                    try self.log.append(self.gpa, '\n');
                }
                if (std.mem.startsWith(u8, line, "WL: ")) {
                    try progress.appendSlice(self.gpa, line);
                    try progress.append(self.gpa, '\n');
                    if (std.mem.eql(u8, line, "WL: INSTALL-OK")) self.saw_ok = true;
                } else if (std.mem.startsWith(u8, line, "WL-RC=")) {
                    const code = std.fmt.parseInt(u32, std.mem.trim(u8, line["WL-RC=".len..], " "), 10) catch 255;
                    self.exit_code = code;
                    if (code == 0 and self.saw_ok) {
                        self.step = .finished_ok;
                        try reply.appendSlice(self.gpa, "poweroff\n");
                    } else {
                        self.step = .finished_failed;
                        self.failure = "the install script reported a failure";
                    }
                }
            },
            else => {},
        }
    }

    /// Prompts have no trailing newline, so they are recognised on the unfinished line.
    fn checkPartial(self: *Driver, reply: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        const p = std.mem.trimEnd(u8, self.line.items, " ");
        switch (self.step) {
            .wait_login => if (std.mem.endsWith(u8, p, "login:")) {
                try reply.appendSlice(self.gpa, live_user ++ "\n");
                self.step = .wait_password;
                self.line.clearRetainingCapacity();
            },
            .wait_password => if (std.mem.endsWith(u8, p, "Password:")) {
                try reply.appendSlice(self.gpa, live_password ++ "\n");
                self.step = .wait_prompt;
                self.line.clearRetainingCapacity();
            },
            .wait_prompt => if (std.mem.endsWith(u8, self.line.items, "# ")) {
                try reply.appendSlice(self.gpa, probe_command);
                self.step = .wait_ready;
                self.line.clearRetainingCapacity();
            },
            else => {},
        }
    }
};

// ---------------------------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------------------------

fn opts() Options {
    return .{ .hostname = "chim1", .password = "Abcdefgh2345", .ssh_public_key = "ssh-ed25519 AAAAC3Nza test@winlab" };
}

test "config is written in single quotes and refuses anything that could break out of them" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try writeConf(opts(), &out.writer);
    try std.testing.expectEqualStrings("HOST='chim1'\nLABUSER='labadmin'\nPASS='Abcdefgh2345'\nPUBKEY='ssh-ed25519 AAAAC3Nza test@winlab'\n", out.written());

    var o = opts();
    o.password = "it's-a-trap-1";
    try std.testing.expectError(error.InvalidPassword, writeConf(o, &out.writer));
    o = opts();
    o.password = "short";
    try std.testing.expectError(error.InvalidPassword, writeConf(o, &out.writer));
    o = opts();
    o.ssh_public_key = "ssh-ed25519 AAA'; rm -rf / #";
    try std.testing.expectError(error.InvalidKey, writeConf(o, &out.writer));
    o = opts();
    o.ssh_public_key = "not a key";
    try std.testing.expectError(error.InvalidKey, writeConf(o, &out.writer));
    o = opts();
    o.hostname = "Bad Host";
    try std.testing.expectError(error.InvalidHostname, writeConf(o, &out.writer));
    o = opts();
    o.user = "x;y";
    try std.testing.expectError(error.InvalidUser, writeConf(o, &out.writer));
}

test "the seed is a CD that carries the three files" {
    const gpa = std.testing.allocator;
    const seed = try buildSeed(gpa, opts());
    defer gpa.free(seed);
    try std.testing.expect(seed.len % 2048 == 0);
    try std.testing.expect(std.mem.indexOf(u8, seed, "WLSEED") != null);
    try std.testing.expect(std.mem.indexOf(u8, seed, "INSTALL.SH;1") != null);
    try std.testing.expect(std.mem.indexOf(u8, seed, "CHROOT.SH;1") != null);
    try std.testing.expect(std.mem.indexOf(u8, seed, "WL.CONF;1") != null);
    try std.testing.expect(std.mem.indexOf(u8, seed, "HOST='chim1'") != null);
    // The scripts really are the repository's files, and they are plain POSIX sh.
    try std.testing.expect(std.mem.indexOf(u8, seed, "chimera-bootstrap -l") != null);
    try std.testing.expect(std.mem.startsWith(u8, install_script, "#!/bin/sh"));
    try std.testing.expect(std.mem.startsWith(u8, chroot_script, "#!/bin/sh"));
}

const Sim = struct {
    d: Driver,
    reply: std.ArrayList(u8) = .empty,
    progress: std.ArrayList(u8) = .empty,

    fn init() Sim {
        return .{ .d = Driver.init(std.testing.allocator) };
    }
    fn deinit(s: *Sim) void {
        s.d.deinit();
        s.reply.deinit(std.testing.allocator);
        s.progress.deinit(std.testing.allocator);
    }
    fn feed(s: *Sim, text: []const u8) !void {
        s.reply.clearRetainingCapacity();
        try s.d.feed(text, &s.reply, &s.progress);
    }
};

test "the serial driver logs in, runs the install and powers off on success" {
    var s = Sim.init();
    defer s.deinit();
    // Boot noise with escape sequences and CRLF, then the login prompt.
    try s.feed("[    1.2] kernel line\r\n\x1b[1;32m[ OK ]\x1b[0m early-fs\r\n\r\nchimera login: ");
    try std.testing.expectEqualStrings("root\n", s.reply.items);
    try std.testing.expectEqual(Step.wait_password, s.d.step);

    try s.feed("root\r\nPassword: ");
    try std.testing.expectEqualStrings("chimera\n", s.reply.items);

    // The echo of the password is not shown; a banner and the root prompt follow.
    try s.feed("\r\nWelcome to Chimera Linux.\r\n# ");
    try std.testing.expectEqualStrings("echo WL-REA''DY\n", s.reply.items);
    try std.testing.expectEqual(Step.wait_ready, s.d.step);

    // The echoed probe does not start the install; its output does.
    try s.feed("echo WL-REA''DY\r\n");
    try std.testing.expectEqual(@as(usize, 0), s.reply.items.len);
    try s.feed("WL-READY\r\n# ");
    try std.testing.expect(std.mem.startsWith(u8, s.reply.items, "{ mkdir -p /seed && mount -t iso9660"));
    // Never on the TTY: stdin detached, output through a pipe (see run_command).
    try std.testing.expect(std.mem.indexOf(u8, s.reply.items, "</dev/null 2>&1 | cat") != null);
    try std.testing.expectEqual(Step.running, s.d.step);

    // Progress lines are reported; chatter from the tools is only logged.
    try s.feed("mkdir -p /seed && ... echo \"WL-RC=$?\"\r\nWL: partitioning /dev/sda\r\nThe partition table has been altered.\r\nWL: ins");
    try s.feed("talling the bootloader\r\nWL: CHROOT-OK\r\nWL: INSTALL-OK\r\nWL-RC=0\r\n");
    try std.testing.expectEqualStrings("poweroff\n", s.reply.items);
    try std.testing.expectEqual(Step.finished_ok, s.d.step);
    try std.testing.expect(s.d.done());
    try std.testing.expectEqualStrings("WL: partitioning /dev/sda\nWL: installing the bootloader\nWL: CHROOT-OK\nWL: INSTALL-OK\n", s.progress.items);
    try std.testing.expect(std.mem.indexOf(u8, s.d.log.items, "The partition table has been altered.") != null);
}

test "a failed install, a bad login and a missing OK marker are failures" {
    {
        var s = Sim.init();
        defer s.deinit();
        try s.feed("login: ");
        try s.feed("Password: ");
        try s.feed("# ");
        try s.feed("WL-READY\r\n");
        try s.feed("WL: partitioning /dev/sda\r\nmkfs failed\r\nWL-RC=1\r\n");
        try std.testing.expectEqual(Step.finished_failed, s.d.step);
        try std.testing.expectEqual(@as(?u32, 1), s.d.exit_code);
        try std.testing.expectEqual(@as(usize, 0), s.reply.items.len); // no poweroff after a failure
    }
    {
        // Exit code 0 without the explicit success line is not trusted.
        var s = Sim.init();
        defer s.deinit();
        try s.feed("login: ");
        try s.feed("Password: ");
        try s.feed("# ");
        try s.feed("WL-READY\r\nWL-RC=0\r\n");
        try std.testing.expectEqual(Step.finished_failed, s.d.step);
    }
    {
        var s = Sim.init();
        defer s.deinit();
        try s.feed("login: ");
        try s.feed("Password: ");
        try s.feed("\r\nLogin incorrect\r\nchimera login: ");
        try std.testing.expectEqual(Step.finished_failed, s.d.step);
        try std.testing.expect(s.d.failure.len > 0);
    }
}
