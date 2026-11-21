//! First-boot configuration for Linux cloud images (cloud-init "NoCloud" seed). Pure text generation:
//! the caller packs the two files into a small ISO labelled CIDATA (see iso9660.zig) and attaches it.
//! The seed creates one lab user with passwordless sudo, authorises the per-VM SSH key, sets a console
//! password (so the learner can use the VM window) and turns off SSH password logins.
const std = @import("std");

pub const Options = struct {
    /// Host name (letters, digits, hyphens; 1..63).
    hostname: []const u8,
    user: []const u8 = "labadmin",
    /// Console password for the VM window. SSH password logins stay disabled.
    password: []const u8,
    /// One OpenSSH public key line.
    ssh_public_key: []const u8,
    /// Used to make the seed's instance id unique per VM.
    instance_id: []const u8,
};

pub const Error = error{ InvalidHostname, InvalidUser, InvalidPassword, InvalidKey, OutOfMemory } || std.Io.Writer.Error;

fn validName(s: []const u8, max: usize) bool {
    if (s.len == 0 or s.len > max) return false;
    for (s, 0..) |c, i| switch (c) {
        'a'...'z', '0'...'9' => {},
        '-', '_' => if (i == 0) return false,
        else => return false,
    };
    return true;
}

fn validKey(k: []const u8) bool {
    if (!std.mem.startsWith(u8, k, "ssh-") or k.len > 600) return false;
    for (k) |c| if (c < 0x20 or c == 0x7F or c == '"' or c == '\\' or c == '\n' or c == '\r') return false;
    return true;
}

pub fn writeUserData(o: Options, w: *std.Io.Writer) Error!void {
    if (!validName(o.hostname, 63)) return error.InvalidHostname;
    if (!validName(o.user, 32)) return error.InvalidUser;
    if (o.password.len < 8 or o.password.len > 100) return error.InvalidPassword;
    for (o.password) |c| switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9' => {},
        else => return error.InvalidPassword, // keeps the YAML below trivially safe
    };
    if (!validKey(o.ssh_public_key)) return error.InvalidKey;
    try w.print(
        \\#cloud-config
        \\hostname: {s}
        \\manage_etc_hosts: true
        \\users:
        \\  - name: {s}
        \\    gecos: WinLab lab user
        \\    sudo: ALL=(ALL) NOPASSWD:ALL
        \\    shell: /bin/bash
        \\    lock_passwd: false
        \\    ssh_authorized_keys:
        \\      - "{s}"
        \\chpasswd:
        \\  expire: false
        \\  users:
        \\    - name: {s}
        \\      password: {s}
        \\      type: text
        \\ssh_pwauth: false
        \\package_update: false
        \\package_upgrade: false
        \\
    , .{ o.hostname, o.user, o.ssh_public_key, o.user, o.password });
}

pub fn writeMetaData(o: Options, w: *std.Io.Writer) Error!void {
    if (!validName(o.hostname, 63)) return error.InvalidHostname;
    for (o.instance_id) |c| switch (c) {
        'a'...'z', '0'...'9', '-' => {},
        else => return error.InvalidHostname,
    };
    try w.print("instance-id: winlab-{s}\nlocal-hostname: {s}\n", .{ o.instance_id, o.hostname });
}

const sample: Options = .{ .hostname = "lab-linux", .password = "Abcdef123456", .ssh_public_key = "ssh-ed25519 AAAAC3Nza winlab-x", .instance_id = "lab-linux" };

test "user-data authorises the key and disables password ssh" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try writeUserData(sample, &out.writer);
    const t = out.written();
    try std.testing.expect(std.mem.startsWith(u8, t, "#cloud-config\n"));
    try std.testing.expect(std.mem.indexOf(u8, t, "- \"ssh-ed25519 AAAAC3Nza winlab-x\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, t, "ssh_pwauth: false") != null);
    try std.testing.expect(std.mem.indexOf(u8, t, "NOPASSWD:ALL") != null);
}

test "meta-data" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try writeMetaData(sample, &out.writer);
    try std.testing.expectEqualStrings("instance-id: winlab-lab-linux\nlocal-hostname: lab-linux\n", out.written());
}

test "bad input is refused" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    var o = sample;
    o.hostname = "Bad Name";
    try std.testing.expectError(error.InvalidHostname, writeUserData(o, &out.writer));
    o = sample;
    o.password = "short";
    try std.testing.expectError(error.InvalidPassword, writeUserData(o, &out.writer));
    o = sample;
    o.password = "has space 1234";
    try std.testing.expectError(error.InvalidPassword, writeUserData(o, &out.writer));
    o = sample;
    o.ssh_public_key = "not a key";
    try std.testing.expectError(error.InvalidKey, writeUserData(o, &out.writer));
    o = sample;
    o.ssh_public_key = "ssh-ed25519 AAAA\nruncmd: [evil]";
    try std.testing.expectError(error.InvalidKey, writeUserData(o, &out.writer));
}
