//! Reading and writing settings.toml under a base directory (normally %APPDATA%).
//! Takes an open `Dir` so tests use a temporary directory and never touch the
//! real profile. Writes are atomic (temp file + replace), so a crash cannot leave
//! a half-written file (spec section 9).
const std = @import("std");
const settings = @import("settings.zig");

pub const sub_dir = "WinLab";
pub const file_name = "settings.toml";
const sub_path = sub_dir ++ "/" ++ file_name;
const max_bytes = 64 * 1024;

/// Loads settings; a missing file yields defaults. A present but unparsable
/// file is an error, so the caller can tell the user instead of silently
/// overwriting their hand-edited file with defaults.
pub fn load(gpa: std.mem.Allocator, io: std.Io, base: std.Io.Dir) !settings.Loaded {
    const text = base.readFileAlloc(io, sub_path, gpa, .limited(max_bytes)) catch |err| switch (err) {
        error.FileNotFound => return settings.parse(gpa, "", null),
        else => return err,
    };
    defer gpa.free(text);
    return settings.parse(gpa, text, null);
}

pub fn save(io: std.Io, base: std.Io.Dir, s: settings.Settings) !void {
    var buf: [1024]u8 = undefined;
    var body: std.Io.Writer = .fixed(&buf);
    try settings.write(s, &body);

    var atomic = try base.createFileAtomic(io, sub_path, .{ .make_path = true, .replace = true });
    defer atomic.deinit(io);
    var fw: std.Io.File.Writer = .init(atomic.file, io, &.{});
    try fw.interface.writeAll(body.buffered());
    try fw.interface.flush();
    try atomic.replace(io);
}

test "missing file gives defaults; save then load round-trips" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var l0 = try load(gpa, io, tmp.dir);
    try std.testing.expectEqual(settings.Theme.system, l0.settings.theme);
    l0.deinit();

    try save(io, tmp.dir, .{ .theme = .dark, .text_scale = 175, .content_path = "D:\\course" });
    var l1 = try load(gpa, io, tmp.dir);
    defer l1.deinit();
    try std.testing.expectEqual(settings.Theme.dark, l1.settings.theme);
    try std.testing.expectEqual(@as(u32, 175), l1.settings.text_scale);
    try std.testing.expectEqualStrings("D:\\course", l1.settings.content_path);

    // Saving again replaces the file.
    try save(io, tmp.dir, .{ .theme = .light });
    var l2 = try load(gpa, io, tmp.dir);
    defer l2.deinit();
    try std.testing.expectEqual(settings.Theme.light, l2.settings.theme);
}

test "corrupt file is an error, not silently defaulted" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, sub_dir);
    try tmp.dir.writeFile(io, .{ .sub_path = sub_path, .data = "theme = \n" });
    try std.testing.expectError(error.InvalidToml, load(std.testing.allocator, io, tmp.dir));
}
