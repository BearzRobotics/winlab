//! Links of a Markdown document, for activation in the reader.
//! Observed on Windows 11: for a RTF HYPERLINK field RichEdit reports the link's
//! target URL as the clicked text (not the display name), so the reader resolves a
//! click by URL first and by display text second, and only ever opens a URL that is
//! in this page's table. The reader also shows the exact URL in a confirmation
//! prompt before opening anything.
const std = @import("std");
const md = @import("md");

pub const Link = struct {
    /// Concatenated text of the link's children (UTF-8).
    text: []const u8,
    url: []const u8,
};

pub const Table = struct {
    arena: std.heap.ArenaAllocator,
    links: []const Link,

    pub fn deinit(self: *Table) void {
        self.arena.deinit();
        self.* = undefined;
    }

    /// What a click on a link reports: its URL (observed) or, failing that, its display text.
    /// Only links of this document can match.
    pub fn resolve(self: *const Table, clicked: []const u8) ?Link {
        for (self.links) |l| if (std.mem.eql(u8, l.url, clicked)) return l;
        return self.find(clicked);
    }

    pub fn find(self: *const Table, text: []const u8) ?Link {
        for (self.links) |l| if (std.mem.eql(u8, l.text, text)) return l;
        return null;
    }
};

pub fn collect(gpa: std.mem.Allocator, root: *md.Node) std.mem.Allocator.Error!Table {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();
    var list: std.ArrayList(Link) = .empty;
    var walker = md.Walker.init(root);
    while (walker.next()) |ev| {
        if (!ev.entering or ev.node.kind != .link) continue;
        var text: std.ArrayList(u8) = .empty;
        var inner = md.Walker.init(ev.node);
        while (inner.next()) |iev| {
            if (!iev.entering) continue;
            switch (iev.node.kind) {
                .text, .code => try text.appendSlice(a, iev.node.literal),
                .softbreak => try text.append(a, ' '),
                else => {},
            }
        }
        try list.append(a, .{ .text = try text.toOwnedSlice(a), .url = try a.dupe(u8, ev.node.literal) });
    }
    return .{ .arena = arena, .links = try list.toOwnedSlice(a) };
}

/// Only web links may be launched from lesson content.
pub fn isLaunchable(url: []const u8) bool {
    const ok = std.ascii.startsWithIgnoreCase(url, "https://") or std.ascii.startsWithIgnoreCase(url, "http://");
    if (!ok) return false;
    for (url) |c| if (c <= ' ' or c == 127) return false;
    return true;
}

test "collects links with nested formatting" {
    const gpa = std.testing.allocator;
    var doc = try md.Document.parse(gpa, "see [**bold** and `code`](https://a.example/x) and [two](file:///c:/x)\n", .{});
    defer doc.deinit();
    var t = try collect(gpa, doc.root);
    defer t.deinit();
    try std.testing.expectEqual(@as(usize, 2), t.links.len);
    try std.testing.expectEqualStrings("bold and code", t.links[0].text);
    try std.testing.expect(isLaunchable(t.find("bold and code").?.url));
    try std.testing.expect(!isLaunchable(t.find("two").?.url));
}

test "launchable rejects other schemes and whitespace" {
    try std.testing.expect(isLaunchable("HTTPS://x.example/a"));
    try std.testing.expect(!isLaunchable("javascript:alert(1)"));
    try std.testing.expect(!isLaunchable("ms-settings:network"));
    try std.testing.expect(!isLaunchable("https://x.example/a b"));
}

test "resolve accepts the url or the text, and nothing else" {
    const gpa = std.testing.allocator;
    var doc = try md.Document.parse(gpa, "[Docs](https://a.example/x)\n", .{});
    defer doc.deinit();
    var t = try collect(gpa, doc.root);
    defer t.deinit();
    try std.testing.expectEqualStrings("https://a.example/x", t.resolve("https://a.example/x").?.url);
    try std.testing.expectEqualStrings("https://a.example/x", t.resolve("Docs").?.url);
    try std.testing.expect(t.resolve("https://evil.example/") == null);
}
