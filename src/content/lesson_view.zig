//! Builds the Markdown shown for a lesson: a generated header from the manifest
//! (objectives, prerequisites, effort, privilege, references) followed by the
//! lesson's own Markdown. Manifest strings are escaped so they cannot inject
//! Markdown structure.
const std = @import("std");
const catalog = @import("catalog.zig");
const certs = @import("certs.zig");

fn writeEscaped(w: *std.Io.Writer, text: []const u8) std.Io.Writer.Error!void {
    for (text) |c| {
        switch (c) {
            '\\', '`', '*', '_', '[', ']', '<', '>', '#', '|', '~', '!' => try w.writeByte('\\'),
            '\n', '\r' => {
                try w.writeByte(' ');
                continue;
            },
            else => {},
        }
        try w.writeByte(c);
    }
}

fn titleOf(cat: *const catalog.Catalog, id: []const u8) ?[]const u8 {
    for (cat.entries) |e| if (std.mem.eql(u8, e.lesson.id, id)) return e.lesson.title;
    return null;
}

pub fn build(gpa: std.mem.Allocator, cat: *const catalog.Catalog, entry: catalog.Entry, body: []const u8) std.mem.Allocator.Error![]u8 {
    return buildWith(gpa, cat, null, entry, body);
}

/// Like `build`, with the certification catalog so tags show as readable names.
pub fn buildWith(gpa: std.mem.Allocator, cat: *const catalog.Catalog, certs_cat: ?*const certs.Catalog, entry: catalog.Entry, body: []const u8) std.mem.Allocator.Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    write(&out.writer, cat, certs_cat, entry, body) catch return error.OutOfMemory;
    return out.toOwnedSlice();
}

fn write(w: *std.Io.Writer, cat: *const catalog.Catalog, certs_cat: ?*const certs.Catalog, entry: catalog.Entry, body: []const u8) std.Io.Writer.Error!void {
    const l = entry.lesson;
    try w.writeAll("# ");
    try writeEscaped(w, l.title);
    try w.writeAll("\n\n");
    if (l.summary.len > 0) {
        try writeEscaped(w, l.summary);
        try w.writeAll("\n\n");
    }
    try w.print("`{s}` | about {d} min | {s}\n\n", .{ l.id, l.estimated_minutes, switch (l.privilege) {
        .standard => "standard user",
        .administrator => "needs administrator rights",
    } });

    try w.writeAll("**Objectives**\n\n");
    for (l.objectives) |o| {
        try w.writeAll("- ");
        try writeEscaped(w, o);
        try w.writeAll("\n");
    }
    if (l.prerequisites.len > 0) {
        try w.writeAll("\n**Prerequisites**\n\n");
        for (l.prerequisites) |p| {
            try w.writeAll("- ");
            try writeEscaped(w, titleOf(cat, p) orelse p);
            try w.print(" (`{s}`)\n", .{p});
        }
    }
    if (l.windows_features.len > 0) {
        try w.writeAll("\n**Windows features**\n\n");
        for (l.windows_features) |f| {
            try w.writeAll("- ");
            try writeEscaped(w, f);
            try w.writeAll("\n");
        }
    }
    if (l.references.len > 0) {
        try w.writeAll("\n**References**\n\n");
        for (l.references) |r| {
            try w.writeAll("- [");
            try writeEscaped(w, r.title);
            try w.print("](<{s}>)\n", .{r.url});
        }
    }
    if (l.certifications.len > 0) {
        try w.writeAll("\n**Supports these certification domains**\n\n");
        for (l.certifications) |tag| {
            try w.writeAll("- ");
            if (certs_cat) |c| {
                if (c.resolve(tag)) |r| {
                    try writeEscaped(w, r.exam.name);
                    try w.writeAll(": ");
                    try writeEscaped(w, r.domain.title);
                    try w.writeAll("\n");
                    continue;
                }
            }
            try writeEscaped(w, tag);
            try w.writeAll("\n");
        }
        try w.writeAll("\nThis lists topics the lesson supports; it is not a promise of exam coverage. The vendor's current objectives are the authority.\n");
    }
    try w.writeAll("\n---\n\n");
    try w.writeAll(body);
}

test "header lists objectives, resolves prerequisite titles and escapes text" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "a.toml", .data = "schema_version = 1\nid = \"p.a\"\ntitle = \"First\"\ncontent = \"a.md\"\nestimated_minutes = 5\nobjectives = [\"o\"]\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "a.md", .data = "x" });
    try tmp.dir.writeFile(io, .{ .sub_path = "b.toml", .data = "schema_version = 1\nid = \"p.b\"\ntitle = \"Second *star*\"\ncontent = \"a.md\"\nestimated_minutes = 7\nobjectives = [\"Explain [x]\"]\nprerequisites = [\"p.a\"]\nprivilege = \"administrator\"\n[[references]]\ntitle = \"Docs\"\nurl = \"https://learn.microsoft.com/a_(b)\"\n" });

    var cat = try catalog.load(gpa, io, tmp.dir);
    defer cat.deinit();
    try std.testing.expectEqual(@as(usize, 0), cat.problems.len);
    const md_text = try build(gpa, &cat, cat.entries[1], "BODY\n");
    defer gpa.free(md_text);
    for ([_][]const u8{ "# Second \\*star\\*", "needs administrator rights", "Explain \\[x\\]", "- First (`p.a`)", "[Docs](<https://learn.microsoft.com/a_(b)>)", "\n---\n\nBODY\n" }) |n| {
        std.testing.expect(std.mem.indexOf(u8, md_text, n) != null) catch |e| {
            std.debug.print("missing '{s}' in:\n{s}\n", .{ n, md_text });
            return e;
        };
    }
}
