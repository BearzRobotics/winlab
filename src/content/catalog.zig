//! The course catalog: every lesson manifest (`*.toml`) found under a course
//! directory, validated, with problems collected rather than aborting on the
//! first one. UI-independent.
const std = @import("std");
const manifest = @import("manifest.zig");

pub const Entry = struct {
    lesson: manifest.Lesson,
    /// Directory of the manifest relative to the course root, '/'-separated ("" for the root).
    dir: []const u8,
};

pub const Problem = struct {
    /// Path (or lesson id) the problem belongs to.
    where: []const u8,
    message: []const u8,
};

pub const Catalog = struct {
    arena: std.heap.ArenaAllocator,
    /// Sorted by lesson id.
    entries: []Entry,
    problems: []Problem,

    pub fn deinit(self: *Catalog) void {
        for (self.entries) |*e| e.lesson.deinit();
        self.arena.deinit();
        self.* = undefined;
    }

    /// Path of the lesson's Markdown relative to the course root.
    pub fn contentPath(self: *const Catalog, a: std.mem.Allocator, entry: Entry) std.mem.Allocator.Error![]u8 {
        _ = self;
        if (entry.dir.len == 0) return a.dupe(u8, entry.lesson.content);
        return std.fmt.allocPrint(a, "{s}/{s}", .{ entry.dir, entry.lesson.content });
    }
};

const max_manifest_bytes = 1024 * 1024;

/// `root` must be opened with `.iterate = true`.
pub fn load(gpa: std.mem.Allocator, io: std.Io, root: std.Io.Dir) !Catalog {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();

    var entries: std.ArrayList(Entry) = .empty;
    errdefer for (entries.items) |*e| e.lesson.deinit();
    var problems: std.ArrayList(Problem) = .empty;

    var walker = try root.walk(gpa);
    defer walker.deinit();
    while (try walker.next(io)) |item| {
        if (item.kind != .file or !std.mem.endsWith(u8, item.path, ".toml")) continue;
        const rel = try normalize(a, item.path);

        const text = item.dir.readFileAlloc(io, item.basename, gpa, .limited(max_manifest_bytes)) catch |err| {
            try problems.append(a, .{ .where = rel, .message = try std.fmt.allocPrint(a, "cannot read: {t}", .{err}) });
            continue;
        };
        defer gpa.free(text);

        var failure: manifest.Failure = .{};
        var lesson = manifest.parse(gpa, text, &failure) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.InvalidToml => {
                try problems.append(a, .{ .where = rel, .message = try std.fmt.allocPrint(a, "line {d}, column {d}: {s}", .{ failure.toml_line, failure.toml_column, failure.message }) });
                continue;
            },
            error.InvalidManifest => {
                try problems.append(a, .{ .where = rel, .message = try std.fmt.allocPrint(a, "{s}: {s}", .{ failure.key, failure.message }) });
                continue;
            },
        };
        errdefer lesson.deinit();

        const dir = if (std.mem.lastIndexOfScalar(u8, rel, '/')) |i| rel[0..i] else "";
        // The content file must exist, as a regular file, next to the manifest.
        if (item.dir.statFile(io, lesson.content, .{})) |st| {
            if (st.kind != .file) try problems.append(a, .{ .where = rel, .message = "content is not a regular file" });
        } else |err| {
            try problems.append(a, .{ .where = rel, .message = try std.fmt.allocPrint(a, "content '{s}': {t}", .{ lesson.content, err }) });
        }
        try entries.append(a, .{ .lesson = lesson, .dir = dir });
    }

    std.mem.sort(Entry, entries.items, {}, struct {
        fn less(_: void, x: Entry, y: Entry) bool {
            return std.mem.lessThan(u8, x.lesson.id, y.lesson.id);
        }
    }.less);

    // Catalog-wide checks (duplicate ids, unknown prerequisites, cycles).
    const lessons = try gpa.alloc(manifest.Lesson, entries.items.len);
    defer gpa.free(lessons);
    for (entries.items, lessons) |e, *l| l.* = e.lesson;
    var catalog_problems: std.ArrayList(manifest.CatalogProblem) = .empty;
    defer catalog_problems.deinit(gpa);
    try manifest.validateCatalog(gpa, lessons, &catalog_problems);
    for (catalog_problems.items) |p| try problems.append(a, .{ .where = p.lesson_id, .message = p.message });

    return .{ .arena = arena, .entries = try entries.toOwnedSlice(a), .problems = try problems.toOwnedSlice(a) };
}

fn normalize(a: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error![]u8 {
    const out = try a.dupe(u8, path);
    std.mem.replaceScalar(u8, out, '\\', '/');
    return out;
}

fn writeLesson(dir: std.Io.Dir, io: std.Io, sub: []const u8, id: []const u8, pre: []const u8, with_content: bool) !void {
    var buf: [512]u8 = undefined;
    const toml_text = try std.fmt.bufPrint(&buf, "schema_version = 1\nid = \"{s}\"\ntitle = \"T {s}\"\ncontent = \"c.md\"\nestimated_minutes = 5\nobjectives = [\"o\"]\nprerequisites = [{s}]\n", .{ id, id, pre });
    try dir.createDirPath(io, sub);
    var p: [128]u8 = undefined;
    try dir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&p, "{s}/l.toml", .{sub}), .data = toml_text });
    if (with_content) try dir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&p, "{s}/c.md", .{sub}), .data = "# x\n" });
}

test "loads, sorts, and reports problems" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try writeLesson(tmp.dir, io, "part/b", "p.b", "\"p.a\"", true);
    try writeLesson(tmp.dir, io, "part/a", "p.a", "", true);
    try writeLesson(tmp.dir, io, "part/c", "p.c", "\"p.zzz\"", false);
    try tmp.dir.writeFile(io, .{ .sub_path = "part/broken.toml", .data = "id = \n" });

    var cat = try load(gpa, io, tmp.dir);
    defer cat.deinit();
    try std.testing.expectEqual(@as(usize, 3), cat.entries.len);
    try std.testing.expectEqualStrings("p.a", cat.entries[0].lesson.id);
    try std.testing.expectEqualStrings("p.c", cat.entries[2].lesson.id);

    var missing_content = false;
    var unknown_pre = false;
    var broken = false;
    for (cat.problems) |p| {
        if (std.mem.indexOf(u8, p.message, "FileNotFound") != null) missing_content = true;
        if (std.mem.eql(u8, p.message, "unknown prerequisite")) unknown_pre = true;
        if (std.mem.eql(u8, p.where, "part/broken.toml")) broken = true;
    }
    try std.testing.expect(missing_content and unknown_pre and broken);

    const path = try cat.contentPath(gpa, cat.entries[0]);
    defer gpa.free(path);
    try std.testing.expectEqualStrings("part/a/c.md", path);
}
