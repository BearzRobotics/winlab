//! Learning paths (docs/learning-paths.md): a goal, and an ordered, staged list of lessons and labs that
//! reaches it. One file per path in `paths/<id>.toml`. A path is advice, not a lock: it only names
//! lessons; progress stays per lesson, so finishing a lesson on one path counts on every path.
//!
//! Path files are untrusted input like manifests: every field is validated and failures name the key.
const std = @import("std");
const toml = @import("toml");
const manifest = @import("manifest.zig");
const catalog = @import("catalog.zig");

pub const schema_version: i64 = 1;
pub const max_stages = 16;
pub const max_items = 128;

pub const Stage = struct {
    title: []const u8,
    /// Shown above the stage: who can skip it or start here.
    entry_hint: []const u8,
    /// Lesson ids, in teaching order.
    lessons: []const []const u8,
    /// Lesson ids worth doing on this path but not needed to finish it.
    optional: []const []const u8,
    /// Lab ids that practise this stage.
    labs: []const []const u8,
};

pub const Path = struct {
    arena: std.heap.ArenaAllocator,
    id: []const u8,
    title: []const u8,
    goal: []const u8,
    audience: []const u8,
    /// Sort key for the picker (lowest first); ties break on id.
    order: i64,
    certifications: []const []const u8,
    stages: []const Stage,

    pub fn deinit(self: *Path) void {
        self.arena.deinit();
        self.* = undefined;
    }

    /// Every lesson id on the path, required ones first by stage, then each stage's optional ones.
    pub fn lessonCount(self: *const Path) usize {
        var n: usize = 0;
        for (self.stages) |s| n += s.lessons.len;
        return n;
    }

    pub fn hasLesson(self: *const Path, id: []const u8) bool {
        for (self.stages) |s| {
            for (s.lessons) |l| if (std.mem.eql(u8, l, id)) return true;
            for (s.optional) |l| if (std.mem.eql(u8, l, id)) return true;
        }
        return false;
    }
};

pub const Failure = struct {
    key: []const u8 = "",
    message: []const u8 = "",
    toml_line: usize = 0,
    toml_column: usize = 0,
};

pub const Error = error{ InvalidToml, InvalidPath, OutOfMemory };

pub fn parse(gpa: std.mem.Allocator, text: []const u8, failure: *Failure) Error!Path {
    var diag: toml.Diagnostic = .{};
    var doc = toml.Document.parse(gpa, text, .{}, &diag) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            failure.* = .{ .message = diag.message, .toml_line = diag.line, .toml_column = diag.column };
            return error.InvalidToml;
        },
    };
    defer doc.deinit();

    var path: Path = undefined;
    path.arena = std.heap.ArenaAllocator.init(gpa);
    errdefer path.arena.deinit();
    const a = path.arena.allocator();
    const t = doc.root;

    const version = t.getInt("schema_version") orelse return fail(failure, "schema_version", "missing or not an integer");
    if (version != schema_version) return fail(failure, "schema_version", "unsupported schema version");

    path.id = try required(a, t, "id", failure);
    if (!validPathId(path.id)) return fail(failure, "id", "must be lowercase letters, digits and hyphens, like 'windows-scripting'");
    path.title = try required(a, t, "title", failure);
    path.goal = try required(a, t, "goal", failure);
    path.audience = try optional(a, t, "audience", failure);
    path.order = if (t.get("order") == null) 1000 else (t.getInt("order") orelse return fail(failure, "order", "not an integer"));
    path.certifications = try strings(a, t, "certifications", failure);
    for (path.certifications) |c| {
        if (!@import("certs.zig").validTagShape(c)) return fail(failure, "certifications", "tags look like exam-id/domain-id");
    }

    if (t.get("stage") == null) return fail(failure, "stage", "at least one [[stage]] is required");
    const arr = t.getArray("stage") orelse return fail(failure, "stage", "must be [[stage]] tables");
    if (arr.items.items.len == 0 or arr.items.items.len > max_stages) return fail(failure, "stage", "between 1 and 16 stages");
    const stages = try a.alloc(Stage, arr.items.items.len);
    for (arr.items.items, stages) |item, *slot| {
        const st = switch (item) {
            .table => |tb| tb,
            else => return fail(failure, "stage", "entries must be tables"),
        };
        slot.* = .{
            .title = try required(a, st, "title", failure),
            .entry_hint = try optional(a, st, "entry_hint", failure),
            .lessons = try strings(a, st, "lessons", failure),
            .optional = try strings(a, st, "optional", failure),
            .labs = try strings(a, st, "labs", failure),
        };
        if (slot.lessons.len == 0) return fail(failure, "stage.lessons", "a stage needs at least one lesson");
        if (slot.lessons.len + slot.optional.len > max_items) return fail(failure, "stage.lessons", "too many lessons in one stage");
        for (slot.lessons) |l| if (!manifest.validId(l)) return fail(failure, "stage.lessons", "entry is not a valid lesson id");
        for (slot.optional) |l| if (!manifest.validId(l)) return fail(failure, "stage.optional", "entry is not a valid lesson id");
        for (slot.labs) |l| if (!manifest.validId(l)) return fail(failure, "stage.labs", "entry is not a valid lab id");
    }
    path.stages = stages;
    return path;
}

fn fail(failure: *Failure, key: []const u8, message: []const u8) error{InvalidPath} {
    failure.* = .{ .key = key, .message = message };
    return error.InvalidPath;
}

fn required(a: std.mem.Allocator, t: *const toml.Table, key: []const u8, failure: *Failure) Error![]const u8 {
    const s = t.getString(key) orelse return fail(failure, key, "missing or not a string");
    if (s.len == 0) return fail(failure, key, "must not be empty");
    return try a.dupe(u8, s);
}

fn optional(a: std.mem.Allocator, t: *const toml.Table, key: []const u8, failure: *Failure) Error![]const u8 {
    if (t.get(key) == null) return "";
    const s = t.getString(key) orelse return fail(failure, key, "not a string");
    return try a.dupe(u8, s);
}

fn strings(a: std.mem.Allocator, t: *const toml.Table, key: []const u8, failure: *Failure) Error![]const []const u8 {
    if (t.get(key) == null) return &.{};
    const arr = t.getArray(key) orelse return fail(failure, key, "not an array");
    const out = try a.alloc([]const u8, arr.items.items.len);
    for (arr.items.items, out) |item, *slot| {
        const s = switch (item) {
            .string => |s| s,
            else => return fail(failure, key, "array entries must be strings"),
        };
        if (s.len == 0) return fail(failure, key, "array entries must not be empty");
        slot.* = try a.dupe(u8, s);
    }
    return out;
}

/// Lowercase letters, digits and single hyphens inside: `windows-scripting`.
pub fn validPathId(id: []const u8) bool {
    if (id.len == 0 or id.len > 64) return false;
    if (id[0] == '-' or id[id.len - 1] == '-') return false;
    for (id) |c| switch (c) {
        'a'...'z', '0'...'9', '-' => {},
        else => return false,
    };
    return true;
}

pub const Severity = enum { problem, warning };

pub const Finding = struct {
    severity: Severity,
    path_id: []const u8,
    message: []const u8,
};

/// Checks a path against the course. Unknown or repeated ids are problems. A lesson whose prerequisite is
/// not earlier on the path is only a warning, because prerequisites are advice (a learner who knows the
/// topic may start later). Messages are allocated from `a`.
pub fn validate(a: std.mem.Allocator, path: *const Path, cat: *const catalog.Catalog, lab_ids: []const []const u8, out: *std.ArrayList(Finding)) std.mem.Allocator.Error!void {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(a);
    for (path.stages) |stage| {
        for (stage.lessons) |id| {
            if (findLesson(cat, id) == null) {
                try out.append(a, .{ .severity = .problem, .path_id = path.id, .message = try std.fmt.allocPrint(a, "unknown lesson '{s}'", .{id}) });
                continue;
            }
            const gop = try seen.getOrPut(a, id);
            if (gop.found_existing) try out.append(a, .{ .severity = .problem, .path_id = path.id, .message = try std.fmt.allocPrint(a, "lesson '{s}' appears twice", .{id}) });
        }
        for (stage.optional) |id| {
            if (findLesson(cat, id) == null) try out.append(a, .{ .severity = .problem, .path_id = path.id, .message = try std.fmt.allocPrint(a, "unknown optional lesson '{s}'", .{id}) });
        }
        for (stage.labs) |id| {
            var known = false;
            for (lab_ids) |l| if (std.mem.eql(u8, l, id)) {
                known = true;
            };
            if (!known) try out.append(a, .{ .severity = .problem, .path_id = path.id, .message = try std.fmt.allocPrint(a, "unknown lab '{s}'", .{id}) });
        }
    }

    // Prerequisite advice: walk the required lessons in order and note any that assume a lesson not yet seen.
    var done: std.StringHashMapUnmanaged(void) = .empty;
    defer done.deinit(a);
    for (path.stages) |stage| {
        for (stage.lessons) |id| {
            const entry = findLesson(cat, id) orelse continue;
            for (entry.lesson.prerequisites) |pre| {
                if (done.contains(pre)) continue;
                try out.append(a, .{ .severity = .warning, .path_id = path.id, .message = try std.fmt.allocPrint(a, "'{s}' recommends '{s}', which is not earlier on this path", .{ id, pre }) });
            }
            try done.put(a, id, {});
        }
    }
}

pub fn findLesson(cat: *const catalog.Catalog, id: []const u8) ?*const catalog.Entry {
    for (cat.entries) |*e| if (std.mem.eql(u8, e.lesson.id, id)) return e;
    return null;
}

pub const Summary = struct {
    lessons: usize = 0,
    minutes: u32 = 0,
    level_min: u8 = 0,
    level_max: u8 = 0,
};

/// Required lessons only. Lessons the catalog does not have are skipped (validate reports them).
pub fn summarize(path: *const Path, cat: *const catalog.Catalog) Summary {
    var s: Summary = .{};
    for (path.stages) |stage| for (stage.lessons) |id| {
        const e = findLesson(cat, id) orelse continue;
        s.lessons += 1;
        s.minutes += e.lesson.estimated_minutes;
        const lv = e.lesson.level;
        if (lv != 0) {
            s.level_min = if (s.level_min == 0) lv else @min(s.level_min, lv);
            s.level_max = @max(s.level_max, lv);
        }
    };
    return s;
}

/// A set of paths from one folder, sorted for the picker.
pub const Set = struct {
    gpa: std.mem.Allocator,
    paths: []Path,
    /// Files that could not be used, "name: reason". Owned by `arena`.
    problems: []const []const u8,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *Set) void {
        for (self.paths) |*p| p.deinit();
        self.gpa.free(self.paths);
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn find(self: *const Set, id: []const u8) ?usize {
        for (self.paths, 0..) |p, i| if (std.mem.eql(u8, p.id, id)) return i;
        return null;
    }
};

/// Loads every `*.toml` in `dir` (opened with `.iterate = true`). Bad files are listed in `problems` and
/// skipped. A missing folder is the caller's concern: pass nothing and get an empty set.
pub fn loadDir(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) std.mem.Allocator.Error!Set {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();
    var list: std.ArrayList(Path) = .empty;
    errdefer for (list.items) |*p| p.deinit();
    var problems: std.ArrayList([]const u8) = .empty;

    var it = dir.iterate();
    while (it.next(io) catch null) |e| {
        if (e.kind != .file or !std.mem.endsWith(u8, e.name, ".toml")) continue;
        const text = dir.readFileAlloc(io, e.name, gpa, .limited(256 * 1024)) catch |err| {
            try problems.append(a, try std.fmt.allocPrint(a, "{s}: cannot read: {t}", .{ e.name, err }));
            continue;
        };
        defer gpa.free(text);
        var failure: Failure = .{};
        var path = parse(gpa, text, &failure) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidToml => {
                try problems.append(a, try std.fmt.allocPrint(a, "{s}: line {d}, column {d}: {s}", .{ e.name, failure.toml_line, failure.toml_column, failure.message }));
                continue;
            },
            error.InvalidPath => {
                try problems.append(a, try std.fmt.allocPrint(a, "{s}: {s}: {s}", .{ e.name, failure.key, failure.message }));
                continue;
            },
        };
        errdefer path.deinit();
        // The file name must match the id, so a path can be found by name.
        const want = try std.fmt.allocPrint(a, "{s}.toml", .{path.id});
        if (!std.mem.eql(u8, want, e.name)) {
            try problems.append(a, try std.fmt.allocPrint(a, "{s}: file must be named {s} after the path id", .{ e.name, want }));
            path.deinit();
            continue;
        }
        var dup = false;
        for (list.items) |p| if (std.mem.eql(u8, p.id, path.id)) {
            dup = true;
        };
        if (dup) {
            path.deinit();
            continue;
        }
        try list.append(gpa, path);
    }
    std.mem.sort(Path, list.items, {}, struct {
        fn less(_: void, x: Path, y: Path) bool {
            if (x.order != y.order) return x.order < y.order;
            return std.mem.lessThan(u8, x.id, y.id);
        }
    }.less);
    const owned = try gpa.dupe(Path, list.items);
    list.deinit(gpa);
    return .{ .gpa = gpa, .paths = owned, .problems = try problems.toOwnedSlice(a), .arena = arena };
}

// ---------------------------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------------------------

const sample =
    \\schema_version = 1
    \\id = "demo-path"
    \\title = "Demo"
    \\goal = "Do the thing."
    \\order = 5
    \\
    \\[[stage]]
    \\title = "First"
    \\entry_hint = "Know it already? Skip."
    \\lessons = ["a.one", "a.two"]
    \\labs = ["labs.x"]
    \\
    \\[[stage]]
    \\title = "Second"
    \\lessons = ["a.three"]
    \\optional = ["a.four"]
    \\
;

test "parses a valid path" {
    var f: Failure = .{};
    var p = try parse(std.testing.allocator, sample, &f);
    defer p.deinit();
    try std.testing.expectEqualStrings("demo-path", p.id);
    try std.testing.expectEqual(@as(i64, 5), p.order);
    try std.testing.expectEqual(@as(usize, 2), p.stages.len);
    try std.testing.expectEqual(@as(usize, 3), p.lessonCount());
    try std.testing.expect(p.hasLesson("a.four"));
    try std.testing.expect(!p.hasLesson("a.zzz"));
    try std.testing.expectEqualStrings("labs.x", p.stages[0].labs[0]);
}

fn expectRejected(text: []const u8, key: []const u8) !void {
    var f: Failure = .{};
    try std.testing.expectError(error.InvalidPath, parse(std.testing.allocator, text, &f));
    try std.testing.expectEqualStrings(key, f.key);
}

test "rejects bad paths with the offending key" {
    const head = "schema_version = 1\nid = \"p\"\ntitle = \"t\"\ngoal = \"g\"\n";
    try expectRejected("schema_version = 2\n", "schema_version");
    try expectRejected("schema_version = 1\nid = \"Bad_Id\"\ntitle = \"t\"\ngoal = \"g\"\n", "id");
    try expectRejected(head, "stage");
    try expectRejected(head ++ "[[stage]]\ntitle = \"s\"\nlessons = []\n", "stage.lessons");
    try expectRejected(head ++ "[[stage]]\ntitle = \"s\"\nlessons = [\"Not An Id\"]\n", "stage.lessons");
    try expectRejected(head ++ "[[stage]]\nlessons = [\"a.b\"]\n", "title");
    try expectRejected(head ++ "order = \"x\"\n[[stage]]\ntitle = \"s\"\nlessons = [\"a.b\"]\n", "order");
}

test "path ids" {
    try std.testing.expect(validPathId("windows-scripting"));
    try std.testing.expect(validPathId("it-support2"));
    try std.testing.expect(!validPathId("-x"));
    try std.testing.expect(!validPathId("x-"));
    try std.testing.expect(!validPathId("a.b"));
    try std.testing.expect(!validPathId(""));
}

fn tmpLesson(dir: std.Io.Dir, io: std.Io, id: []const u8, pre: []const u8, level: u8) !void {
    var buf: [512]u8 = undefined;
    const text = try std.fmt.bufPrint(&buf, "schema_version = 1\nid = \"{s}\"\ntitle = \"T\"\ncontent = \"c.md\"\nestimated_minutes = 10\nlevel = {d}\nobjectives = [\"o\"]\nprerequisites = [{s}]\n", .{ id, level, pre });
    var p: [64]u8 = undefined;
    try dir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&p, "{s}.toml", .{id}), .data = text });
    try dir.writeFile(io, .{ .sub_path = "c.md", .data = "# x\n" });
}

test "validate finds unknown ids, repeats and advice" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmpLesson(tmp.dir, io, "a.one", "", 1);
    try tmpLesson(tmp.dir, io, "a.two", "\"a.one\"", 3);
    var cat = try catalog.load(gpa, io, tmp.dir);
    defer cat.deinit();

    var f: Failure = .{};
    var p = try parse(gpa, "schema_version = 1\nid = \"p\"\ntitle = \"t\"\ngoal = \"g\"\n[[stage]]\ntitle = \"s\"\nlessons = [\"a.two\", \"a.one\", \"a.one\", \"a.nope\"]\nlabs = [\"labs.q\"]\n", &f);
    defer p.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var out: std.ArrayList(Finding) = .empty;
    try validate(arena.allocator(), &p, &cat, &.{"labs.x"}, &out);
    var problems: usize = 0;
    var warnings: usize = 0;
    for (out.items) |x| switch (x.severity) {
        .problem => problems += 1,
        .warning => warnings += 1,
    };
    try std.testing.expectEqual(@as(usize, 3), problems); // repeat, unknown lesson, unknown lab
    try std.testing.expectEqual(@as(usize, 1), warnings); // a.two before its prerequisite a.one

    const s = summarize(&p, &cat);
    try std.testing.expectEqual(@as(usize, 3), s.lessons);
    try std.testing.expectEqual(@as(u32, 30), s.minutes);
    try std.testing.expectEqual(@as(u8, 1), s.level_min);
    try std.testing.expectEqual(@as(u8, 3), s.level_max);
}

test "loadDir sorts by order, enforces file names, reports bad files" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const mk = struct {
        fn body(g: std.mem.Allocator, id: []const u8, order: i64) ![]u8 {
            return std.fmt.allocPrint(g, "schema_version = 1\nid = \"{s}\"\ntitle = \"t\"\ngoal = \"g\"\norder = {d}\n[[stage]]\ntitle = \"s\"\nlessons = [\"a.b\"]\n", .{ id, order });
        }
    };
    const b1 = try mk.body(gpa, "zeta", 1);
    defer gpa.free(b1);
    const b2 = try mk.body(gpa, "alpha", 2);
    defer gpa.free(b2);
    const b3 = try mk.body(gpa, "wrongname", 3);
    defer gpa.free(b3);
    try tmp.dir.writeFile(io, .{ .sub_path = "zeta.toml", .data = b1 });
    try tmp.dir.writeFile(io, .{ .sub_path = "alpha.toml", .data = b2 });
    try tmp.dir.writeFile(io, .{ .sub_path = "other.toml", .data = b3 });
    try tmp.dir.writeFile(io, .{ .sub_path = "broken.toml", .data = "id = \n" });

    var set = try loadDir(gpa, io, tmp.dir);
    defer set.deinit();
    try std.testing.expectEqual(@as(usize, 2), set.paths.len);
    try std.testing.expectEqualStrings("zeta", set.paths[0].id); // order 1 before order 2
    try std.testing.expectEqualStrings("alpha", set.paths[1].id);
    try std.testing.expectEqual(@as(usize, 2), set.problems.len);
    try std.testing.expectEqual(@as(?usize, 1), set.find("alpha"));
}
