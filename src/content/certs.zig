//! Certification catalog (`certs/catalog.toml`): which outside exams WinLab maps to and the TITLES of
//! their domains. Lessons and labs carry tags of the form `exam-id/domain-id`. Official objective wording
//! is deliberately not copied: each exam links to the vendor's own objectives page, which is the
//! authority and changes over time. A tag means "this material supports that domain", never "this
//! passes that exam".
const std = @import("std");
const toml = @import("toml");

pub const Domain = struct {
    id: []const u8,
    title: []const u8,
};

pub const Exam = struct {
    id: []const u8,
    name: []const u8,
    vendor: []const u8,
    /// Vendor's exam code, for example 220-1202.
    code: []const u8,
    /// Where the vendor publishes the current objectives (https).
    url: []const u8,
    domains: []Domain,
};

pub const Catalog = struct {
    arena: std.heap.ArenaAllocator,
    exams: []Exam,

    pub fn deinit(self: *Catalog) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn findExam(self: *const Catalog, id: []const u8) ?*const Exam {
        for (self.exams) |*e| {
            if (std.mem.eql(u8, e.id, id)) return e;
        }
        return null;
    }

    /// Resolves "exam-id/domain-id" to its exam and domain, or null if either does not exist.
    pub fn resolve(self: *const Catalog, tag: []const u8) ?struct { exam: *const Exam, domain: *const Domain } {
        const slash = std.mem.indexOfScalar(u8, tag, '/') orelse return null;
        const exam = self.findExam(tag[0..slash]) orelse return null;
        for (exam.domains) |*d| {
            if (std.mem.eql(u8, d.id, tag[slash + 1 ..])) return .{ .exam = exam, .domain = d };
        }
        return null;
    }
};

pub const ParseError = error{ InvalidToml, UnsupportedSchema, InvalidEntry, OutOfMemory };

/// Shape check for a tag in a manifest: `exam-id/domain-id`, lowercase letters, digits and hyphens.
pub fn validTagShape(tag: []const u8) bool {
    const slash = std.mem.indexOfScalar(u8, tag, '/') orelse return false;
    if (slash == 0 or slash + 1 >= tag.len or tag.len > 96) return false;
    for (tag, 0..) |c, i| {
        if (i == slash) continue;
        switch (c) {
            'a'...'z', '0'...'9', '-' => {},
            else => return false,
        }
    }
    return std.mem.indexOfScalar(u8, tag[slash + 1 ..], '/') == null;
}

fn validId(s: []const u8) bool {
    if (s.len == 0 or s.len > 48) return false;
    for (s) |c| switch (c) {
        'a'...'z', '0'...'9', '-' => {},
        else => return false,
    };
    return true;
}

pub fn parse(gpa: std.mem.Allocator, text: []const u8) ParseError!Catalog {
    var doc = toml.Document.parse(gpa, text, .{}, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidToml,
    };
    defer doc.deinit();
    const v = doc.root.getInt("schema_version") orelse return error.UnsupportedSchema;
    if (v != 1) return error.UnsupportedSchema;

    var cat: Catalog = .{ .arena = std.heap.ArenaAllocator.init(gpa), .exams = &.{} };
    errdefer cat.arena.deinit();
    const a = cat.arena.allocator();
    const arr = doc.root.getArray("exam") orelse return cat;
    const exams = try a.alloc(Exam, arr.items.items.len);
    for (arr.items.items, exams, 0..) |item, *slot, i| {
        const t = switch (item) {
            .table => |x| x,
            else => return error.InvalidEntry,
        };
        const eid = t.getString("id") orelse return error.InvalidEntry;
        if (!validId(eid)) return error.InvalidEntry;
        for (exams[0..i]) |prev| if (std.mem.eql(u8, prev.id, eid)) return error.InvalidEntry;
        const url = t.getString("url") orelse return error.InvalidEntry;
        if (!std.mem.startsWith(u8, url, "https://")) return error.InvalidEntry;
        const darr = t.getArray("domain") orelse return error.InvalidEntry;
        const domains = try a.alloc(Domain, darr.items.items.len);
        for (darr.items.items, domains, 0..) |ditem, *dslot, j| {
            const dt = switch (ditem) {
                .table => |x| x,
                else => return error.InvalidEntry,
            };
            const did = dt.getString("id") orelse return error.InvalidEntry;
            if (!validId(did)) return error.InvalidEntry;
            for (domains[0..j]) |prev| if (std.mem.eql(u8, prev.id, did)) return error.InvalidEntry;
            dslot.* = .{ .id = try a.dupe(u8, did), .title = try a.dupe(u8, dt.getString("title") orelse return error.InvalidEntry) };
        }
        slot.* = .{
            .id = try a.dupe(u8, eid),
            .name = try a.dupe(u8, t.getString("name") orelse return error.InvalidEntry),
            .vendor = try a.dupe(u8, t.getString("vendor") orelse return error.InvalidEntry),
            .code = try a.dupe(u8, t.getString("code") orelse ""),
            .url = try a.dupe(u8, url),
            .domains = domains,
        };
    }
    cat.exams = exams;
    return cat;
}

test "catalog parses and tags resolve" {
    var c = try parse(std.testing.allocator,
        \\schema_version = 1
        \\[[exam]]
        \\id = "comptia-a-core2"
        \\name = "CompTIA A+ Core 2"
        \\vendor = "CompTIA"
        \\code = "220-1202"
        \\url = "https://www.comptia.org/"
        \\[[exam.domain]]
        \\id = "operating-systems"
        \\title = "Operating Systems"
        \\[[exam.domain]]
        \\id = "security"
        \\title = "Security"
        \\
    );
    defer c.deinit();
    const r = c.resolve("comptia-a-core2/security").?;
    try std.testing.expectEqualStrings("Security", r.domain.title);
    try std.testing.expectEqualStrings("CompTIA A+ Core 2", r.exam.name);
    try std.testing.expect(c.resolve("comptia-a-core2/nope") == null);
    try std.testing.expect(c.resolve("nope/security") == null);
    try std.testing.expect(c.resolve("noslash") == null);
}

test "tag shape and bad catalogs" {
    try std.testing.expect(validTagShape("comptia-a-core2/operating-systems"));
    try std.testing.expect(!validTagShape("no-slash"));
    try std.testing.expect(!validTagShape("a/b/c"));
    try std.testing.expect(!validTagShape("A/b"));
    try std.testing.expect(!validTagShape("/b"));
    try std.testing.expectError(error.UnsupportedSchema, parse(std.testing.allocator, ""));
    try std.testing.expectError(error.InvalidEntry, parse(std.testing.allocator, "schema_version = 1\n[[exam]]\nid=\"x\"\nname=\"n\"\nvendor=\"v\"\nurl=\"http://x\"\n"));
}
