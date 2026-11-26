//! Lesson diagrams: a small, strict subset of SVG that WinLab draws itself (docs/diagrams.md).
//! Boxes, lines with arrowheads and one-line labels, styled by class name so the window can colour them
//! for the light or dark theme. Lesson files are untrusted: anything outside the subset is an error,
//! and nothing here follows a link, runs a script or reads another file.
const std = @import("std");
const md = @import("md");

pub const max_bytes = 64 * 1024;
pub const max_items = 600;
const max_coord: f32 = 4000;

/// What a shape or label looks like. The window picks the colours; `<style>` in the file is only for browsers.
pub const Style = struct {
    zone_user: bool = false,
    zone_kernel: bool = false,
    hardware: bool = false,
    accent: bool = false,
    dim: bool = false,
    bold: bool = false,
    mono: bool = false,
    dashed: bool = false,
};

pub const Anchor = enum { start, middle, end };

pub const Item = union(enum) {
    rect: struct { x: f32, y: f32, w: f32, h: f32, radius: f32 = 0, style: Style = .{} },
    line: struct { x1: f32, y1: f32, x2: f32, y2: f32, arrow: bool = false, style: Style = .{} },
    /// `y` is the baseline, as in SVG.
    text: struct { x: f32, y: f32, size: f32 = 14, anchor: Anchor = .start, text: []const u8, style: Style = .{} },
};

pub const Diagram = struct {
    width: f32,
    height: f32,
    items: []const Item,
};

pub const Failure = struct {
    line: u32 = 0,
    message: []const u8 = "",
};

pub const Error = error{ InvalidDiagram, OutOfMemory };

/// True for a path a lesson may name: relative, ending in `.svg`, with no way out of the lesson's folder.
pub fn validPath(path: []const u8) bool {
    if (path.len < 5 or path.len > 120 or !std.mem.endsWith(u8, path, ".svg")) return false;
    if (path[0] == '/' or path[0] == '.') return false;
    for (path) |c| switch (c) {
        'a'...'z', '0'...'9', '-', '_', '/', '.' => {},
        else => return false,
    };
    return std.mem.indexOf(u8, path, "..") == null and std.mem.indexOf(u8, path, "//") == null;
}

/// If `paragraph` holds nothing but one image of an SVG inside the lesson's folder, its path.
pub fn imageOnly(paragraph: *const md.Node) ?[]const u8 {
    const image = paragraph.first_child orelse return null;
    if (image.kind != .image or image.next != null or !validPath(image.literal)) return null;
    return image.literal;
}

/// The `text` code block that directly follows a diagram: the picture for plain-text view and copying.
pub fn textFallback(paragraph: *const md.Node) ?*md.Node {
    const next = paragraph.next orelse return null;
    return if (next.kind == .code_block and std.mem.eql(u8, next.title, "text")) next else null;
}

const Attr = struct { name: []const u8, value: []const u8 };

const Parser = struct {
    a: std.mem.Allocator,
    s: []const u8,
    i: usize = 0,
    failure: *Failure,

    fn fail(self: *Parser, message: []const u8) Error {
        var line: u32 = 1;
        for (self.s[0..@min(self.i, self.s.len)]) |c| {
            if (c == '\n') line += 1;
        }
        self.failure.* = .{ .line = line, .message = message };
        return error.InvalidDiagram;
    }

    fn startsWith(self: *const Parser, what: []const u8) bool {
        return std.mem.startsWith(u8, self.s[self.i..], what);
    }

    fn skipPast(self: *Parser, what: []const u8) Error!void {
        const at = std.mem.indexOfPos(u8, self.s, self.i, what) orelse return self.fail("something is not closed");
        self.i = at + what.len;
    }

    /// Skips blanks, comments and the XML declaration.
    fn skipSpace(self: *Parser) Error!void {
        while (self.i < self.s.len) {
            if (std.ascii.isWhitespace(self.s[self.i])) {
                self.i += 1;
            } else if (self.startsWith("<!--")) {
                try self.skipPast("-->");
            } else if (self.startsWith("<?xml ")) {
                try self.skipPast("?>");
            } else return;
        }
    }

    fn name(self: *Parser) []const u8 {
        const from = self.i;
        while (self.i < self.s.len) : (self.i += 1) switch (self.s[self.i]) {
            'a'...'z', 'A'...'Z', '0'...'9', '-', ':', '_' => {},
            else => break,
        };
        return self.s[from..self.i];
    }

    const Tag = struct { name: []const u8, attrs: []const Attr, empty: bool };

    /// Reads `<name attr="value" ...>` or `.../>`; the parser is at the `<`.
    fn openTag(self: *Parser) Error!Tag {
        if (!self.startsWith("<")) return self.fail("expected a tag");
        self.i += 1;
        const tag = self.name();
        if (tag.len == 0) return self.fail("this kind of markup is not allowed");
        var attrs: std.ArrayList(Attr) = .empty;
        while (true) {
            while (self.i < self.s.len and std.ascii.isWhitespace(self.s[self.i])) self.i += 1;
            if (self.startsWith("/>")) {
                self.i += 2;
                return .{ .name = tag, .attrs = attrs.items, .empty = true };
            }
            if (self.startsWith(">")) {
                self.i += 1;
                return .{ .name = tag, .attrs = attrs.items, .empty = false };
            }
            const key = self.name();
            if (key.len == 0 or !self.startsWith("=\"")) return self.fail("attributes must look like name=\"value\"");
            self.i += 2;
            const end = std.mem.indexOfScalarPos(u8, self.s, self.i, '"') orelse return self.fail("a value is not closed");
            if (attrs.items.len >= 24) return self.fail("too many attributes");
            try attrs.append(self.a, .{ .name = key, .value = self.s[self.i..end] });
            self.i = end + 1;
        }
    }

    fn number(self: *Parser, text: []const u8) Error!f32 {
        const v = std.fmt.parseFloat(f32, text) catch return self.fail("expected a plain number");
        if (!(v >= 0 and v <= max_coord)) return self.fail("a number is negative or too large");
        return v;
    }

    fn style(self: *Parser, classes: []const u8) Error!Style {
        var out: Style = .{};
        var words = std.mem.tokenizeScalar(u8, classes, ' ');
        const names = [_]struct { []const u8, []const u8 }{
            .{ "zone-user", "zone_user" }, .{ "zone-kernel", "zone_kernel" }, .{ "hardware", "hardware" }, .{ "accent", "accent" },
            .{ "dim", "dim" },             .{ "bold", "bold" },               .{ "mono", "mono" },         .{ "dashed", "dashed" },
        };
        next: while (words.next()) |word| {
            inline for (names) |pair| if (std.mem.eql(u8, word, pair[0])) {
                @field(out, pair[1]) = true;
                continue :next;
            };
            // "box", "wire" and "label" are the plain look; they exist so a browser's style sheet can name them.
            for ([_][]const u8{ "box", "wire", "label" }) |plain| if (std.mem.eql(u8, word, plain)) continue :next;
            return self.fail("unknown class name");
        }
        return out;
    }

    /// The text inside `<text>`: no child elements, and only the five standard entities.
    fn content(self: *Parser) Error![]const u8 {
        const end = std.mem.indexOfScalarPos(u8, self.s, self.i, '<') orelse return self.fail("text is not closed");
        const raw = self.s[self.i..end];
        self.i = end;
        if (!self.startsWith("</text>")) return self.fail("a label may not contain other elements");
        self.i += "</text>".len;
        if (raw.len > 200) return self.fail("a label is too long");
        var out: std.ArrayList(u8) = .empty;
        var i: usize = 0;
        const entities = [_]struct { []const u8, u8 }{ .{ "&lt;", '<' }, .{ "&gt;", '>' }, .{ "&amp;", '&' }, .{ "&quot;", '"' }, .{ "&apos;", '\'' } };
        next: while (i < raw.len) {
            if (raw[i] == '&') {
                for (entities) |e| if (std.mem.startsWith(u8, raw[i..], e[0])) {
                    try out.append(self.a, e[1]);
                    i += e[0].len;
                    continue :next;
                };
                return self.fail("only &lt; &gt; &amp; &quot; and &apos; are allowed");
            }
            if (raw[i] < ' ') return self.fail("a label must be on one line");
            try out.append(self.a, raw[i]);
            i += 1;
        }
        if (!std.unicode.utf8ValidateSlice(out.items)) return self.fail("a label is not valid UTF-8");
        return out.items;
    }
};

fn isOneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |item| if (std.mem.eql(u8, name, item)) return true;
    return false;
}

/// Parses `source`. Everything returned lives in `arena`.
pub fn parse(arena: std.mem.Allocator, source: []const u8, failure: *Failure) Error!Diagram {
    var p: Parser = .{ .a = arena, .s = source, .failure = failure };
    if (source.len > max_bytes) return p.fail("the file is too large");
    try p.skipSpace();
    const root = try p.openTag();
    if (!std.mem.eql(u8, root.name, "svg") or root.empty) return p.fail("the file must be an <svg> element");
    var width: f32 = 0;
    var height: f32 = 0;
    for (root.attrs) |attr| {
        if (std.mem.eql(u8, attr.name, "viewBox")) {
            var parts = std.mem.tokenizeScalar(u8, attr.value, ' ');
            for (0..4) |n| {
                const v = try p.number(parts.next() orelse return p.fail("viewBox needs four numbers"));
                if (n < 2 and v != 0) return p.fail("viewBox must start at 0 0");
                if (n == 2) width = v;
                if (n == 3) height = v;
            }
        } else if (!isOneOf(attr.name, &.{ "xmlns", "width", "height", "role", "aria-label", "font-family" })) {
            return p.fail("unknown attribute on <svg>");
        }
    }
    if (width < 1 or height < 1) return p.fail("<svg> needs a viewBox");

    var items: std.ArrayList(Item) = .empty;
    while (true) {
        try p.skipSpace();
        if (p.startsWith("</svg>")) {
            p.i += "</svg>".len;
            break;
        }
        const tag = try p.openTag();
        // For browsers only: a style sheet, the arrowhead definition and descriptions. Their content is not read.
        if (isOneOf(tag.name, &.{ "style", "defs", "title", "desc" })) {
            if (!tag.empty) try p.skipPast(try std.fmt.allocPrint(arena, "</{s}>", .{tag.name}));
            continue;
        }
        if (items.items.len >= max_items) return p.fail("too many elements");
        var s: Style = .{};
        for (tag.attrs) |attr| if (std.mem.eql(u8, attr.name, "class")) {
            s = try p.style(attr.value);
        };
        if (std.mem.eql(u8, tag.name, "rect")) {
            var x: f32 = 0;
            var y: f32 = 0;
            var w: f32 = 0;
            var h: f32 = 0;
            var radius: f32 = 0;
            for (tag.attrs) |attr| {
                if (std.mem.eql(u8, attr.name, "x")) x = try p.number(attr.value) else if (std.mem.eql(u8, attr.name, "y")) y = try p.number(attr.value) else if (std.mem.eql(u8, attr.name, "width")) w = try p.number(attr.value) else if (std.mem.eql(u8, attr.name, "height")) h = try p.number(attr.value) else if (std.mem.eql(u8, attr.name, "rx")) radius = try p.number(attr.value) else if (!std.mem.eql(u8, attr.name, "class")) return p.fail("unknown attribute on <rect>");
            }
            if (!tag.empty) return p.fail("<rect> must end in />");
            try items.append(arena, .{ .rect = .{ .x = x, .y = y, .w = w, .h = h, .radius = radius, .style = s } });
        } else if (std.mem.eql(u8, tag.name, "line")) {
            var v = [4]f32{ 0, 0, 0, 0 };
            var arrow = false;
            for (tag.attrs) |attr| {
                if (std.mem.eql(u8, attr.name, "x1")) v[0] = try p.number(attr.value) else if (std.mem.eql(u8, attr.name, "y1")) v[1] = try p.number(attr.value) else if (std.mem.eql(u8, attr.name, "x2")) v[2] = try p.number(attr.value) else if (std.mem.eql(u8, attr.name, "y2")) v[3] = try p.number(attr.value) else if (std.mem.eql(u8, attr.name, "marker-end")) arrow = true else if (!std.mem.eql(u8, attr.name, "class")) return p.fail("unknown attribute on <line>");
            }
            if (!tag.empty) return p.fail("<line> must end in />");
            try items.append(arena, .{ .line = .{ .x1 = v[0], .y1 = v[1], .x2 = v[2], .y2 = v[3], .arrow = arrow, .style = s } });
        } else if (std.mem.eql(u8, tag.name, "text")) {
            var x: f32 = 0;
            var y: f32 = 0;
            var size: f32 = 14;
            var anchor: Anchor = .start;
            for (tag.attrs) |attr| {
                if (std.mem.eql(u8, attr.name, "x")) x = try p.number(attr.value) else if (std.mem.eql(u8, attr.name, "y")) y = try p.number(attr.value) else if (std.mem.eql(u8, attr.name, "font-size")) size = try p.number(attr.value) else if (std.mem.eql(u8, attr.name, "text-anchor")) anchor = std.meta.stringToEnum(Anchor, attr.value) orelse return p.fail("text-anchor must be start, middle or end") else if (!std.mem.eql(u8, attr.name, "class")) return p.fail("unknown attribute on <text>");
            }
            if (size < 6 or size > 60) return p.fail("font-size must be from 6 to 60");
            if (tag.empty) return p.fail("<text> needs a label");
            try items.append(arena, .{ .text = .{ .x = x, .y = y, .size = size, .anchor = anchor, .text = try p.content(), .style = s } });
        } else return p.fail("this element is not supported (use rect, line and text)");
    }
    try p.skipSpace();
    if (p.i != source.len) return p.fail("there is content after </svg>");
    return .{ .width = width, .height = height, .items = items.items };
}

test "the supported subset parses, with browser-only blocks skipped" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var f: Failure = .{};
    const d = try parse(arena_state.allocator(),
        \\<?xml version="1.0"?>
        \\<!-- a comment -->
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100">
        \\  <style>.box { fill: none }</style>
        \\  <defs><marker id="a"><path d="M0 0"/></marker></defs>
        \\  <rect class="box zone-user" x="1" y="2" width="30" height="20" rx="4"/>
        \\  <line class="wire" x1="0" y1="0" x2="10" y2="10" marker-end="url(#a)"/>
        \\  <text class="label bold" x="100" y="50" text-anchor="middle">a &lt; b &amp; c</text>
        \\</svg>
        \\
    , &f);
    try std.testing.expectEqual(@as(f32, 200), d.width);
    try std.testing.expectEqual(@as(usize, 3), d.items.len);
    try std.testing.expect(d.items[0].rect.style.zone_user);
    try std.testing.expect(d.items[1].line.arrow);
    try std.testing.expectEqualStrings("a < b & c", d.items[2].text.text);
    try std.testing.expectEqual(Anchor.middle, d.items[2].text.anchor);
}

test "anything outside the subset is refused, with the line" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const head = "<svg viewBox=\"0 0 10 10\">\n";
    for ([_][]const u8{
        "<script>alert(1)</script>",
        "<image href=\"http://example.com/x.png\"/>",
        "<a href=\"x\"/>",
        "<rect x=\"1\" onclick=\"x\"/>",
        "<rect x=\"-5\"/>",
        "<rect x=\"1e99\"/>",
        "<text x=\"1\" y=\"1\"><tspan>x</tspan></text>",
        "<text x=\"1\" y=\"1\">&xxe;</text>",
        "<rect class=\"nope\"/>",
        "<!DOCTYPE x>",
    }) |bad| {
        var f: Failure = .{};
        const source = try std.mem.concat(arena_state.allocator(), u8, &.{ head, bad, "\n</svg>" });
        try std.testing.expectError(error.InvalidDiagram, parse(arena_state.allocator(), source, &f));
        try std.testing.expect(f.line >= 2);
    }
    var f: Failure = .{};
    try std.testing.expectError(error.InvalidDiagram, parse(arena_state.allocator(), head, &f)); // not closed
}

test "diagram paths stay inside the lesson folder" {
    try std.testing.expect(validPath("diagrams/user-kernel.svg"));
    for ([_][]const u8{ "../x.svg", "/etc/x.svg", "a/../b.svg", "http://e/x.svg", "C:\\x.svg", "a\\b.svg", "x.png", ".svg", "a//b.svg" }) |bad|
        try std.testing.expect(!validPath(bad));
}
