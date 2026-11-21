//! Guest control over OpenSSH (decision record 0006). Each lab VM has its own
//! key pair and known_hosts in its folder, and SSH is reachable only through a
//! QEMU port forward bound to 127.0.0.1. WinLab runs a PowerShell script in the
//! guest and returns its exit code and output; it never interprets the script.
const std = @import("std");
const toml = @import("toml");
const p = @import("provider.zig");

pub const Shell = enum { powershell, bash };

pub const Access = struct {
    /// What runs scripts in the guest (Windows: PowerShell; Linux: bash).
    shell: Shell = .powershell,
    port: u16,
    /// Guest account name (owned by the caller's arena/allocator).
    user: []const u8,
    /// QEMU CPU model. Windows 11 24H2 needs SSE4.2/POPCNT, which `qemu64` lacks; installs of client
    /// Windows write `cpu = "max"` to guest.toml.
    cpu: []const u8 = "qemu64",
    /// Linux distribution label from guest.toml (for example "ubuntu", "almalinux"); empty if unspecified.
    distro: []const u8 = "",
};

pub const guest_file = "guest.toml";
pub const key_file = "id_ed25519";
pub const known_hosts_file = "known_hosts";
pub const max_script_bytes = 4000;

pub const LoadError = error{ NoGuestConfig, InvalidGuestConfig, OutOfMemory };

/// Reads `<vm_dir>/guest.toml` (`ssh_port`, `ssh_user`). The user string is allocated with `arena`.
pub fn load(arena: std.mem.Allocator, io: std.Io, vm_dir: []const u8) LoadError!Access {
    const path = std.fs.path.join(arena, &.{ vm_dir, guest_file }) catch return error.OutOfMemory;
    const text = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(16 * 1024)) catch return error.NoGuestConfig;
    var doc = toml.Document.parse(arena, text, .{}, null) catch return error.InvalidGuestConfig;
    defer doc.deinit();
    const port = doc.root.getInt("ssh_port") orelse return error.InvalidGuestConfig;
    if (port < 1024 or port > 65535) return error.InvalidGuestConfig;
    const user = doc.root.getString("ssh_user") orelse return error.InvalidGuestConfig;
    for (user) |c| switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '_' => {},
        else => return error.InvalidGuestConfig,
    };
    if (user.len == 0 or user.len > 20) return error.InvalidGuestConfig;
    var cpu: []const u8 = "qemu64";
    if (doc.root.getString("cpu")) |c| {
        for (c) |ch| switch (ch) {
            'a'...'z', '0'...'9', '_', '-' => {},
            else => return error.InvalidGuestConfig,
        };
        if (c.len == 0 or c.len > 24) return error.InvalidGuestConfig;
        cpu = try arena.dupe(u8, c);
    }
    const shell = if (doc.root.getString("shell")) |s| (std.meta.stringToEnum(Shell, s) orelse return error.InvalidGuestConfig) else Shell.powershell;
    var distro: []const u8 = "";
    if (doc.root.getString("distro")) |d| {
        for (d) |ch| if (!(std.ascii.isLower(ch) or std.ascii.isDigit(ch) or ch == '-')) return error.InvalidGuestConfig;
        distro = try arena.dupe(u8, d);
    }
    return .{ .port = @intCast(port), .user = try arena.dupe(u8, user), .cpu = cpu, .shell = shell, .distro = distro };
}

/// Base64 of the script as UTF-16LE, the form `powershell -EncodedCommand` expects.
pub fn encodeCommand(arena: std.mem.Allocator, script: []const u8) ![]u8 {
    const w = try std.unicode.utf8ToUtf16LeAlloc(arena, script);
    const bytes = std.mem.sliceAsBytes(w);
    const out = try arena.alloc(u8, std.base64.standard.Encoder.calcSize(bytes.len));
    return @constCast(std.base64.standard.Encoder.encode(out, bytes));
}

pub fn sshArgv(arena: std.mem.Allocator, ssh_exe: []const u8, vm_dir: []const u8, a: Access, script: []const u8) ![]const []const u8 {
    const key = try std.fs.path.join(arena, &.{ vm_dir, key_file });
    const hosts = try std.fmt.allocPrint(arena, "UserKnownHostsFile={s}", .{try std.fs.path.join(arena, &.{ vm_dir, known_hosts_file })});
    var v: std.ArrayList([]const u8) = .empty;
    try v.appendSlice(arena, &.{
        ssh_exe,
        "-i",
        key,
        "-p",
        try std.fmt.allocPrint(arena, "{d}", .{a.port}),
        "-o",
        "BatchMode=yes",
        "-o",
        "IdentitiesOnly=yes",
        "-o",
        "LogLevel=ERROR",
        "-o",
        "ConnectTimeout=15",
        "-o",
        "StrictHostKeyChecking=accept-new", // only ever connects to 127.0.0.1:<forwarded port>
        "-o",
        hosts,
        try std.fmt.allocPrint(arena, "{s}@127.0.0.1", .{a.user}),
    });
    switch (a.shell) {
        .powershell => try v.appendSlice(arena, &.{
            "powershell",
            "-NoProfile",
            "-NonInteractive",
            "-OutputFormat",
            "Text", // without this, progress records arrive as CLIXML noise on stderr
            "-EncodedCommand",
            try encodeCommand(arena, try std.fmt.allocPrint(arena, "$ProgressPreference = 'SilentlyContinue'; {s}", .{script})), // no progress records (they arrive as CLIXML noise)
        }),
        // One remote command line: the script travels as base64 so no quoting can break it. It runs as root
        // (the lab user has passwordless sudo): labs break and fix system state, as an administrator would.
        .bash => try v.append(arena, try std.fmt.allocPrint(arena, "echo {s} | base64 -d | sudo -n bash -s", .{try encodeBash(arena, script)})),
    }
    return v.items;
}

/// Base64 of the script's UTF-8 bytes, for `echo ... | base64 -d | bash -s`.
pub fn encodeBash(arena: std.mem.Allocator, script: []const u8) ![]u8 {
    const out = try arena.alloc(u8, std.base64.standard.Encoder.calcSize(script.len));
    return @constCast(std.base64.standard.Encoder.encode(out, script));
}

/// Runs `script` in the guest. `output` is stdout followed by stderr, owned by `gpa`.
pub fn exec(gpa: std.mem.Allocator, io: std.Io, ssh_exe: []const u8, vm_dir: []const u8, a: Access, script: []const u8) p.Error!p.GuestResult {
    if (script.len > max_script_bytes) return error.ProviderFailed;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const argv = sshArgv(arena_state.allocator(), ssh_exe, vm_dir, a, script) catch return error.OutOfMemory;
    const r = std.process.run(gpa, io, .{ .argv = argv, .stdout_limit = .limited(1024 * 1024), .stderr_limit = .limited(1024 * 1024) }) catch return error.ProviderFailed;
    defer gpa.free(r.stdout);
    defer gpa.free(r.stderr);
    const code: u32 = switch (r.term) {
        .exited => |c| c,
        else => return error.ProviderFailed,
    };
    // ssh itself exits 255 when it cannot connect or authenticate; that is not a script result.
    if (code == 255) return error.ProviderFailed;
    const out = std.mem.concat(gpa, u8, &.{ r.stdout, r.stderr }) catch return error.OutOfMemory;
    return .{ .exit_code = code, .output = out };
}

test "command encoding is base64 of UTF-16LE" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // "dir" -> 64 00 69 00 72 00 -> ZABpAHIA
    try std.testing.expectEqualStrings("ZABpAHIA", try encodeCommand(arena.allocator(), "dir"));
}

test "ssh arguments pin the key, known_hosts, loopback and batch mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const argv = try sshArgv(arena.allocator(), "ssh.exe", "D:/vm/x", .{ .port = 2222, .user = "Administrator" }, "exit 0");
    const joined = try std.mem.join(arena.allocator(), " ", argv);
    try std.testing.expect(std.mem.indexOf(u8, joined, "Administrator@127.0.0.1") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "BatchMode=yes") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "IdentitiesOnly=yes") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "-p 2222") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "-EncodedCommand") != null);
}

test "guest.toml is validated" {
    const io = std.testing.io;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realPathFileAlloc(io, ".", arena.allocator());
    try std.testing.expectError(error.NoGuestConfig, load(arena.allocator(), io, dir));
    try tmp.dir.writeFile(io, .{ .sub_path = guest_file, .data = "ssh_port = 2222\nssh_user = \"Administrator\"\n" });
    const a = try load(arena.allocator(), io, dir);
    try std.testing.expectEqual(@as(u16, 2222), a.port);
    try tmp.dir.writeFile(io, .{ .sub_path = guest_file, .data = "ssh_port = 22\nssh_user = \"x\"\n" });
    try std.testing.expectError(error.InvalidGuestConfig, load(arena.allocator(), io, dir));
    try tmp.dir.writeFile(io, .{ .sub_path = guest_file, .data = "ssh_port = 2222\nssh_user = \"a b\"\n" });
    try std.testing.expectError(error.InvalidGuestConfig, load(arena.allocator(), io, dir));
}
