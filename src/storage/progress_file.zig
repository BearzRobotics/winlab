//! Reading and writing progress.toml under a base directory (normally %APPDATA%).
//! Same rules as settings_file: takes an open `Dir`, writes atomically, and a
//! corrupt file is an error so the caller never overwrites it with an empty one.
const std = @import("std");
const progress = @import("progress.zig");

pub const sub_dir = "WinLab";
pub const file_name = "progress.toml";
const sub_path = sub_dir ++ "/" ++ file_name;
const max_bytes = 16 * 1024 * 1024;

pub fn load(gpa: std.mem.Allocator, io: std.Io, base: std.Io.Dir) !progress.Progress {
    const text = base.readFileAlloc(io, sub_path, gpa, .limited(max_bytes)) catch |err| switch (err) {
        error.FileNotFound => return progress.Progress.init(gpa),
        else => return err,
    };
    defer gpa.free(text);
    return progress.Progress.parse(gpa, text);
}

pub fn save(gpa: std.mem.Allocator, io: std.Io, base: std.Io.Dir, p: *const progress.Progress) !void {
    var body: std.Io.Writer.Allocating = .init(gpa);
    defer body.deinit();
    try p.write(&body.writer);

    var atomic = try base.createFileAtomic(io, sub_path, .{ .make_path = true, .replace = true });
    defer atomic.deinit(io);
    var fw: std.Io.File.Writer = .init(atomic.file, io, &.{});
    try fw.interface.writeAll(body.written());
    try fw.interface.flush();
    try atomic.replace(io);
}

test "missing is empty; save then load; corrupt is an error" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var p0 = try load(gpa, io, tmp.dir);
    try std.testing.expectEqual(@as(usize, 0), p0.countCompleted());
    try p0.setStatus("a.b", .completed);
    try p0.setNotes("a.b", "hello\nworld");
    try save(gpa, io, tmp.dir, &p0);
    p0.deinit();

    var p1 = try load(gpa, io, tmp.dir);
    defer p1.deinit();
    try std.testing.expectEqualStrings("hello\nworld", p1.get("a.b").notes);

    try tmp.dir.writeFile(io, .{ .sub_path = sub_path, .data = "x = \n" });
    try std.testing.expectError(error.InvalidToml, load(gpa, io, tmp.dir));
}
