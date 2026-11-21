//! Lesson search (decision record 0004: in-memory scan, no index). A query is
//! split on whitespace; a lesson matches when EVERY term occurs somewhere in its
//! title, summary or body. Matching is ASCII case-insensitive (non-ASCII text
//! matches exactly). The body is the raw Markdown, so link URLs and markup
//! characters are searchable too; that is acceptable for a course-sized corpus.
const std = @import("std");

pub const Doc = struct {
    title: []const u8,
    summary: []const u8 = "",
    body: []const u8 = "",
};

const title_weight = 100;
const summary_weight = 10;
const body_weight = 1;

/// Fills `out` with indices of matching `docs`, best first (title hits outrank
/// summary hits outrank body hits; ties keep catalog order). An empty or
/// all-whitespace query matches everything in the original order.
pub fn search(gpa: std.mem.Allocator, docs: []const Doc, query: []const u8, out: *std.ArrayList(usize)) std.mem.Allocator.Error!void {
    out.clearRetainingCapacity();
    const Scored = struct { index: usize, score: u32 };
    var scored: std.ArrayList(Scored) = .empty;
    defer scored.deinit(gpa);

    for (docs, 0..) |d, i| {
        var score: u32 = 0;
        var ok = true;
        var terms = std.mem.tokenizeAny(u8, query, " \t\r\n");
        while (terms.next()) |term| {
            var s: u32 = 0;
            if (contains(d.title, term)) s += title_weight;
            if (contains(d.summary, term)) s += summary_weight;
            if (contains(d.body, term)) s += body_weight;
            if (s == 0) {
                ok = false;
                break;
            }
            score += s;
        }
        if (ok) try scored.append(gpa, .{ .index = i, .score = score });
    }
    std.mem.sort(Scored, scored.items, {}, struct {
        fn less(_: void, a: Scored, b: Scored) bool {
            if (a.score != b.score) return a.score > b.score;
            return a.index < b.index;
        }
    }.less);
    try out.ensureTotalCapacity(gpa, scored.items.len);
    for (scored.items) |s| out.appendAssumeCapacity(s.index);
}

const sample = [_]Doc{
    .{ .title = "Users and groups", .summary = "Local accounts", .body = "Use net user to list accounts." },
    .{ .title = "Services", .summary = "Windows services", .body = "Restart a service with sc." },
    .{ .title = "Event logs", .summary = "Reading logs", .body = "Users may clear the Security log." },
};

test "empty query matches everything in order" {
    var out: std.ArrayList(usize) = .empty;
    defer out.deinit(std.testing.allocator);
    try search(std.testing.allocator, &sample, "  ", &out);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, out.items);
}

test "title hits outrank body hits; case-insensitive" {
    var out: std.ArrayList(usize) = .empty;
    defer out.deinit(std.testing.allocator);
    try search(std.testing.allocator, &sample, "USERS", &out);
    try std.testing.expectEqualSlices(usize, &.{ 0, 2 }, out.items);
}

test "all terms must match, anywhere" {
    var out: std.ArrayList(usize) = .empty;
    defer out.deinit(std.testing.allocator);
    try search(std.testing.allocator, &sample, "services restart", &out);
    try std.testing.expectEqualSlices(usize, &.{1}, out.items);
    try search(std.testing.allocator, &sample, "services zzz", &out);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.startsWithIgnoreCase(haystack[i..], needle)) return true;
    }
    return false;
}
