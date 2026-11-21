//! Lesson manifests (schema version 1): structured TOML next to each Markdown
//! lesson. See ai/specs.md section 5.1. Manifests are untrusted input: every
//! field is validated and failures name the offending key.
const std = @import("std");
const toml = @import("toml");

pub const schema_version: i64 = 1;
pub const max_level = 5;

pub const Privilege = enum { standard, administrator };

pub const Reference = struct {
    title: []const u8,
    /// Always an https:// URL (validated).
    url: []const u8,
};

pub const Lesson = struct {
    arena: std.heap.ArenaAllocator,
    id: []const u8,
    title: []const u8,
    summary: []const u8,
    /// Markdown file, relative to the manifest's directory (validated: no `..`, no absolute path).
    content: []const u8,
    estimated_minutes: u32,
    /// Difficulty 1 (first contact) to 5 (expert, open-book); 0 when the manifest does not say.
    level: u8,
    objectives: []const []const u8,
    /// Lessons this one assumes. Advice, never a gate: the app warns and offers a link (docs/learning-paths.md).
    prerequisites: []const []const u8,
    windows_features: []const []const u8,
    privilege: Privilege,
    vm_topology: []const u8,
    lab_fixtures: []const []const u8,
    evaluation_criteria: []const []const u8,
    references: []const Reference,
    /// Certification domains this lesson supports, as "exam-id/domain-id" tags (see certs/catalog.toml).
    certifications: []const []const u8,

    pub fn deinit(self: *Lesson) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Why a manifest was rejected. `key` and `message` are static strings.
pub const Failure = struct {
    key: []const u8 = "",
    message: []const u8 = "",
    toml_line: usize = 0,
    toml_column: usize = 0,
};

pub const Error = error{ InvalidToml, InvalidManifest, OutOfMemory };

pub fn parse(gpa: std.mem.Allocator, text: []const u8, failure: *Failure) Error!Lesson {
    var diag: toml.Diagnostic = .{};
    var doc = toml.Document.parse(gpa, text, .{}, &diag) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            failure.* = .{ .message = diag.message, .toml_line = diag.line, .toml_column = diag.column };
            return error.InvalidToml;
        },
    };
    defer doc.deinit();

    var lesson: Lesson = undefined;
    lesson.arena = std.heap.ArenaAllocator.init(gpa);
    errdefer lesson.arena.deinit();
    const a = lesson.arena.allocator();
    const t = doc.root;

    const version = t.getInt("schema_version") orelse return fail(failure, "schema_version", "missing or not an integer");
    if (version != schema_version) return fail(failure, "schema_version", "unsupported schema version");

    lesson.id = try dupeRequired(a, t, "id", failure);
    if (!validId(lesson.id)) return fail(failure, "id", "must be dotted lowercase segments like 'foundations.cmd-basics'");
    lesson.title = try dupeRequired(a, t, "title", failure);
    lesson.summary = try dupeOptional(a, t, "summary", failure);
    lesson.content = try dupeRequired(a, t, "content", failure);
    if (!validRelativePath(lesson.content)) return fail(failure, "content", "must be a relative path without '..' or drive letters");

    const minutes = t.getInt("estimated_minutes") orelse return fail(failure, "estimated_minutes", "missing or not an integer");
    if (minutes < 1 or minutes > 24 * 60) return fail(failure, "estimated_minutes", "must be between 1 and 1440");
    lesson.estimated_minutes = @intCast(minutes);

    if (t.get("level") == null) {
        lesson.level = 0;
    } else {
        const level = t.getInt("level") orelse return fail(failure, "level", "not an integer");
        if (level < 1 or level > max_level) return fail(failure, "level", "must be between 1 and 5");
        lesson.level = @intCast(level);
    }

    lesson.objectives = try stringList(a, t, "objectives", failure);
    if (lesson.objectives.len == 0) return fail(failure, "objectives", "at least one measurable objective is required");
    lesson.prerequisites = try stringList(a, t, "prerequisites", failure);
    for (lesson.prerequisites) |p| if (!validId(p)) return fail(failure, "prerequisites", "entry is not a valid lesson id");
    lesson.windows_features = try stringList(a, t, "windows_features", failure);
    lesson.lab_fixtures = try stringList(a, t, "lab_fixtures", failure);
    lesson.evaluation_criteria = try stringList(a, t, "evaluation_criteria", failure);
    lesson.vm_topology = if (t.get("vm_topology") == null) "none" else try dupeRequired(a, t, "vm_topology", failure);

    const priv_text = if (t.get("privilege") == null) "standard" else try dupeRequired(a, t, "privilege", failure);
    lesson.privilege = std.meta.stringToEnum(Privilege, priv_text) orelse return fail(failure, "privilege", "must be 'standard' or 'administrator'");

    lesson.references = try references(a, t, failure);
    lesson.certifications = try certTags(a, t, failure);
    return lesson;
}

fn fail(failure: *Failure, key: []const u8, message: []const u8) error{InvalidManifest} {
    failure.* = .{ .key = key, .message = message };
    return error.InvalidManifest;
}

fn dupeRequired(a: std.mem.Allocator, t: *const toml.Table, key: []const u8, failure: *Failure) Error![]const u8 {
    const s = t.getString(key) orelse return fail(failure, key, "missing or not a string");
    if (s.len == 0) return fail(failure, key, "must not be empty");
    return try a.dupe(u8, s);
}

fn dupeOptional(a: std.mem.Allocator, t: *const toml.Table, key: []const u8, failure: *Failure) Error![]const u8 {
    if (t.get(key) == null) return "";
    const s = t.getString(key) orelse return fail(failure, key, "not a string");
    return try a.dupe(u8, s);
}

fn stringList(a: std.mem.Allocator, t: *const toml.Table, key: []const u8, failure: *Failure) Error![]const []const u8 {
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

fn references(a: std.mem.Allocator, t: *const toml.Table, failure: *Failure) Error![]const Reference {
    if (t.get("references") == null) return &.{};
    const arr = t.getArray("references") orelse return fail(failure, "references", "not an array of tables");
    const out = try a.alloc(Reference, arr.items.items.len);
    for (arr.items.items, out) |item, *slot| {
        const tbl = switch (item) {
            .table => |tb| tb,
            else => return fail(failure, "references", "entries must be tables with title and url"),
        };
        const title = try dupeRequired(a, tbl, "title", failure);
        const url = try dupeRequired(a, tbl, "url", failure);
        if (!validHttpsUrl(url)) return fail(failure, "references.url", "must be an https:// URL without spaces or control characters");
        slot.* = .{ .title = title, .url = url };
    }
    return out;
}

/// Dotted lowercase segments: `foundations.cmd-basics`.
pub fn validId(id: []const u8) bool {
    if (id.len == 0 or id.len > 128) return false;
    var seg_len: usize = 0;
    for (id) |c| {
        switch (c) {
            'a'...'z', '0'...'9' => seg_len += 1,
            '-' => if (seg_len == 0) return false else {
                seg_len += 1;
            },
            '.' => {
                if (seg_len == 0) return false;
                seg_len = 0;
            },
            else => return false,
        }
    }
    return seg_len > 0;
}

pub fn validRelativePath(path: []const u8) bool {
    if (path.len == 0 or path.len > 260) return false;
    if (path[0] == '/' or path[0] == '\\') return false;
    if (std.mem.indexOfScalar(u8, path, ':') != null) return false;
    if (std.mem.indexOfScalar(u8, path, '\\') != null) return false;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |seg| {
        if (seg.len == 0 or std.mem.eql(u8, seg, ".") or std.mem.eql(u8, seg, "..")) return false;
    }
    return true;
}

fn validHttpsUrl(url: []const u8) bool {
    if (!std.mem.startsWith(u8, url, "https://") or url.len <= "https://".len) return false;
    for (url) |c| if (c <= ' ' or c == 127 or c == '<' or c == '>') return false;
    return true;
}

/// Catalog-level checks: duplicate ids and prerequisites that are unknown or form a cycle.
pub const CatalogProblem = struct {
    lesson_id: []const u8,
    message: []const u8,
};

pub fn validateCatalog(gpa: std.mem.Allocator, lessons: []const Lesson, problems: *std.ArrayList(CatalogProblem)) std.mem.Allocator.Error!void {
    var index: std.StringHashMapUnmanaged(usize) = .empty;
    defer index.deinit(gpa);
    for (lessons, 0..) |l, i| {
        const gop = try index.getOrPut(gpa, l.id);
        if (gop.found_existing) try problems.append(gpa, .{ .lesson_id = l.id, .message = "duplicate lesson id" }) else gop.value_ptr.* = i;
    }
    for (lessons) |l| for (l.prerequisites) |p| {
        if (!index.contains(p)) try problems.append(gpa, .{ .lesson_id = l.id, .message = "unknown prerequisite" });
    };

    // Cycle detection: iterative DFS with colors (0 new, 1 on stack, 2 done).
    const color = try gpa.alloc(u8, lessons.len);
    defer gpa.free(color);
    @memset(color, 0);
    const Frame = struct { lesson: usize, next_pre: usize };
    var stack: std.ArrayList(Frame) = .empty;
    defer stack.deinit(gpa);
    for (0..lessons.len) |start| {
        if (color[start] != 0) continue;
        try stack.append(gpa, .{ .lesson = start, .next_pre = 0 });
        color[start] = 1;
        while (stack.items.len > 0) {
            const top = &stack.items[stack.items.len - 1];
            const pres = lessons[top.lesson].prerequisites;
            if (top.next_pre == pres.len) {
                color[top.lesson] = 2;
                _ = stack.pop();
                continue;
            }
            const pre = pres[top.next_pre];
            top.next_pre += 1;
            const j = index.get(pre) orelse continue;
            if (color[j] == 1) {
                try problems.append(gpa, .{ .lesson_id = lessons[j].id, .message = "prerequisite cycle" });
            } else if (color[j] == 0) {
                color[j] = 1;
                try stack.append(gpa, .{ .lesson = j, .next_pre = 0 });
            }
        }
    }
}

const sample =
    \\schema_version = 1
    \\id = "foundations.sample"
    \\title = "Sample"
    \\content = "sample.md"
    \\estimated_minutes = 15
    \\level = 3
    \\objectives = ["Explain X", "Perform Y"]
    \\prerequisites = ["foundations.intro"]
    \\privilege = "administrator"
    \\
    \\[[references]]
    \\title = "Microsoft Learn"
    \\url = "https://learn.microsoft.com/windows/"
    \\
;

test "parses a valid manifest" {
    var f: Failure = .{};
    var l = try parse(std.testing.allocator, sample, &f);
    defer l.deinit();
    try std.testing.expectEqualStrings("foundations.sample", l.id);
    try std.testing.expectEqual(@as(u32, 15), l.estimated_minutes);
    try std.testing.expectEqual(@as(u8, 3), l.level);
    try std.testing.expectEqual(@as(usize, 2), l.objectives.len);
    try std.testing.expectEqual(Privilege.administrator, l.privilege);
    try std.testing.expectEqualStrings("none", l.vm_topology);
    try std.testing.expectEqualStrings("https://learn.microsoft.com/windows/", l.references[0].url);
}

fn expectRejected(text: []const u8, key: []const u8) !void {
    var f: Failure = .{};
    try std.testing.expectError(error.InvalidManifest, parse(std.testing.allocator, text, &f));
    try std.testing.expectEqualStrings(key, f.key);
}

test "rejects bad manifests with the offending key" {
    try expectRejected("schema_version = 2\n", "schema_version");
    try expectRejected("schema_version = 1\nid = \"Bad Id\"\n", "id");
    const base = "schema_version = 1\nid = \"a.b\"\ntitle = \"t\"\nestimated_minutes = 5\nobjectives = [\"o\"]\n";
    try expectRejected(base ++ "content = \"../x.md\"\n", "content");
    try expectRejected(base ++ "content = \"C:/x.md\"\n", "content");
    try expectRejected("schema_version = 1\nid = \"a.b\"\ntitle = \"t\"\ncontent = \"x.md\"\nestimated_minutes = 5\nobjectives = []\n", "objectives");
    try expectRejected(base ++ "content = \"x.md\"\nprivilege = \"root\"\n", "privilege");
    try expectRejected(base ++ "content = \"x.md\"\nlevel = 0\n", "level");
    try expectRejected(base ++ "content = \"x.md\"\nlevel = 6\n", "level");
    try expectRejected(base ++ "content = \"x.md\"\nlevel = \"hard\"\n", "level");
    try expectRejected(base ++ "content = \"x.md\"\n[[references]]\ntitle = \"t\"\nurl = \"javascript:alert(1)\"\n", "references.url");
}

test "invalid toml is reported with a position" {
    var f: Failure = .{};
    try std.testing.expectError(error.InvalidToml, parse(std.testing.allocator, "id = \n", &f));
    try std.testing.expect(f.toml_line == 1);
}

test "catalog checks" {
    const gpa = std.testing.allocator;
    var f: Failure = .{};
    const mk = struct {
        fn lesson(g: std.mem.Allocator, fl: *Failure, id: []const u8, pre: []const u8) !Lesson {
            const text = try std.fmt.allocPrint(g, "schema_version = 1\nid = \"{s}\"\ntitle = \"t\"\ncontent = \"x.md\"\nestimated_minutes = 5\nobjectives = [\"o\"]\nprerequisites = [{s}]\n", .{ id, pre });
            defer g.free(text);
            return parse(g, text, fl);
        }
    };
    var ls = [_]Lesson{
        try mk.lesson(gpa, &f, "a.one", "\"a.two\""),
        try mk.lesson(gpa, &f, "a.two", "\"a.one\""),
        try mk.lesson(gpa, &f, "a.three", "\"a.missing\""),
        try mk.lesson(gpa, &f, "a.three", ""),
    };
    defer for (&ls) |*l| l.deinit();
    var problems: std.ArrayList(CatalogProblem) = .empty;
    defer problems.deinit(gpa);
    try validateCatalog(gpa, &ls, &problems);
    var dup = false;
    var unknown = false;
    var cycle = false;
    for (problems.items) |p| {
        if (std.mem.eql(u8, p.message, "duplicate lesson id")) dup = true;
        if (std.mem.eql(u8, p.message, "unknown prerequisite")) unknown = true;
        if (std.mem.eql(u8, p.message, "prerequisite cycle")) cycle = true;
    }
    try std.testing.expect(dup and unknown and cycle);
}

/// Optional `certifications = ["exam-id/domain-id", ...]`. Only the SHAPE is checked here; whether the exam
/// and domain exist is checked against certs/catalog.toml by `winlab check`.
fn certTags(a: std.mem.Allocator, t: *const toml.Table, failure: *Failure) Error![]const []const u8 {
    if (t.get("certifications") == null) return &.{};
    const arr = t.getArray("certifications") orelse return fail(failure, "certifications", "not an array");
    const out = try a.alloc([]const u8, arr.items.items.len);
    for (arr.items.items, out) |item, *slot| {
        const s = switch (item) {
            .string => |x| x,
            else => return fail(failure, "certifications", "entries must be strings"),
        };
        if (!@import("certs.zig").validTagShape(s)) return fail(failure, "certifications", "tags look like exam-id/domain-id (lowercase letters, digits, hyphens)");
        slot.* = try a.dupe(u8, s);
    }
    return out;
}
