//! User settings (TOML). Unknown keys are ignored; a missing, mistyped or
//! out-of-range key keeps its default, so a hand-edited file never prevents
//! startup. Settings are read from %APPDATA%\WinLab\settings.toml by the caller;
//! this module only parses and serialises text.
const std = @import("std");
const toml = @import("toml");

pub const Theme = enum { system, light, dark };

pub const min_text_scale = 100;
pub const max_text_scale = 300;

pub const Settings = struct {
    theme: Theme = .system,
    /// Percent; applied on top of the system DPI scale.
    text_scale: u32 = 100,
    /// Directory containing the `course/` folder (empty: `./course` relative to the working directory). Not validated here.
    content_path: []const u8 = "",
    /// Folder containing qemu-system-x86_64.exe and qemu-img.exe (empty: search PATH and known locations).
    qemu_path: []const u8 = "",
    /// Id of the registered training VM the Lab button uses (empty: the first usable one).
    lab_vm: []const u8 = "",
    /// The first-run setup window has been shown and closed; it does not open by itself again.
    setup_done: bool = false,
};

pub const Loaded = struct {
    arena: std.heap.ArenaAllocator,
    settings: Settings,
    /// Keys that were present but unusable and replaced by defaults (static strings).
    ignored: []const []const u8,

    pub fn deinit(self: *Loaded) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub const Error = error{ InvalidToml, OutOfMemory };

pub fn parse(gpa: std.mem.Allocator, text: []const u8, diag: ?*toml.Diagnostic) Error!Loaded {
    var doc = toml.Document.parse(gpa, text, .{}, diag) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidToml,
    };
    defer doc.deinit();

    var loaded: Loaded = .{ .arena = std.heap.ArenaAllocator.init(gpa), .settings = .{}, .ignored = &.{} };
    errdefer loaded.arena.deinit();
    const a = loaded.arena.allocator();
    var ignored: std.ArrayList([]const u8) = .empty;
    const t = doc.root;

    if (t.get("theme")) |_| {
        if (t.getString("theme")) |s| {
            if (std.meta.stringToEnum(Theme, s)) |th| loaded.settings.theme = th else try ignored.append(a, "theme");
        } else try ignored.append(a, "theme");
    }
    if (t.get("text-scale")) |_| {
        if (t.getInt("text-scale")) |n| {
            if (n >= min_text_scale and n <= max_text_scale) loaded.settings.text_scale = @intCast(n) else try ignored.append(a, "text-scale");
        } else try ignored.append(a, "text-scale");
    }
    if (t.get("content-path")) |_| {
        if (t.getString("content-path")) |s| loaded.settings.content_path = try a.dupe(u8, s) else try ignored.append(a, "content-path");
    }
    if (t.get("qemu-path")) |_| {
        if (t.getString("qemu-path")) |s| loaded.settings.qemu_path = try a.dupe(u8, s) else try ignored.append(a, "qemu-path");
    }
    if (t.get("lab-vm")) |_| {
        if (t.getString("lab-vm")) |s| loaded.settings.lab_vm = try a.dupe(u8, s) else try ignored.append(a, "lab-vm");
    }
    if (t.get("setup-done")) |_| {
        if (t.getBool("setup-done")) |b| loaded.settings.setup_done = b else try ignored.append(a, "setup-done");
    }
    loaded.ignored = try ignored.toOwnedSlice(a);
    return loaded;
}

fn writeQuoted(w: *std.Io.Writer, s: []const u8) std.Io.Writer.Error!void {
    try w.writeByte('"');
    for (s) |c| switch (c) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        0...31, 127 => try w.print("\\u{x:0>4}", .{c}),
        else => try w.writeByte(c),
    };
    try w.writeByte('"');
}

/// Writes `s` as TOML. Strings are escaped as TOML basic strings.
pub fn write(s: Settings, w: *std.Io.Writer) std.Io.Writer.Error!void {
    try w.print("theme = \"{s}\"\ntext-scale = {d}\ncontent-path = ", .{ @tagName(s.theme), s.text_scale });
    try writeQuoted(w, s.content_path);
    try w.writeAll("\nqemu-path = ");
    try writeQuoted(w, s.qemu_path);
    try w.writeAll("\nlab-vm = ");
    try writeQuoted(w, s.lab_vm);
    try w.print("\nsetup-done = {s}", .{if (s.setup_done) "true" else "false"});
    try w.writeByte('\n');
}

test "defaults for empty file" {
    var l = try parse(std.testing.allocator, "", null);
    defer l.deinit();
    try std.testing.expectEqual(Theme.system, l.settings.theme);
    try std.testing.expectEqual(@as(u32, 100), l.settings.text_scale);
    try std.testing.expectEqual(@as(usize, 0), l.ignored.len);
}

test "valid values are used, bad ones are reported and defaulted" {
    var l = try parse(std.testing.allocator, "theme = \"dark\"\ntext-scale = 5000\ncontent-path = 3\nextra = true\n", null);
    defer l.deinit();
    try std.testing.expectEqual(Theme.dark, l.settings.theme);
    try std.testing.expectEqual(@as(u32, 100), l.settings.text_scale);
    try std.testing.expectEqual(@as(usize, 2), l.ignored.len);
}

test "round trip" {
    const gpa = std.testing.allocator;
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try write(.{ .theme = .light, .text_scale = 150, .content_path = "C:\\WinLab \"x\"", .setup_done = true }, &out.writer);
    var l = try parse(gpa, out.written(), null);
    defer l.deinit();
    try std.testing.expectEqual(Theme.light, l.settings.theme);
    try std.testing.expectEqual(@as(u32, 150), l.settings.text_scale);
    try std.testing.expectEqualStrings("C:\\WinLab \"x\"", l.settings.content_path);
    try std.testing.expectEqualStrings("", l.settings.qemu_path);
    try std.testing.expectEqualStrings("", l.settings.lab_vm);
    try std.testing.expect(l.settings.setup_done);
}

test "invalid toml" {
    try std.testing.expectError(error.InvalidToml, parse(std.testing.allocator, "theme = \n", null));
}
