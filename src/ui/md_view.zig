//! Markdown tree (md-zig) -> DVUI widgets, drawn every frame.
//!
//! Lesson text is untrusted (spec section 9): raw HTML is shown as plain text and never
//! interpreted, images show their alt text only, and a link is never opened here. A click only
//! reports the URL in `View.clicked`; the window asks the learner before launching anything.
const std = @import("std");
const dvui = @import("dvui");
const md = @import("winlab").md;
const highlight = @import("highlight.zig");

/// Per-frame drawing state. `clicked` is set when a link was activated during `render`.
pub const View = struct {
    clicked: ?[]const u8 = null,
    counter: usize = 0,
    /// Which page is drawn, so "answers shown" is remembered per page and never carries to another lesson.
    page: usize = 0,

    fn nextId(self: *View) usize {
        self.counter += 1;
        return self.counter;
    }
};

const Style = struct {
    bold: bool = false,
    italic: bool = false,
    strike: bool = false,
    /// Base size of this block's text; headings scale it.
    size: f32 = 0,
    heading: bool = false,
};

/// Draws the document's blocks into the current parent.
pub fn render(root: *md.Node, v: *View) void {
    v.counter = 0;
    // Consecutive paragraphs, headings and simple lists share ONE text widget, so a drag can select
    // across them. Anything that needs its own box (tables, code, quotes, answers) ends the run.
    var run: ?*dvui.TextLayoutWidget = null;
    var c = root.first_child;
    while (c) |n| : (c = n.next) {
        if (flowable(n)) {
            if (run == null) {
                run = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .id_extra = v.nextId(), .padding = .all(0), .margin = .{ .h = 4 } });
                quiet(run.?);
            }
            flow(run.?, n, v, 0);
        } else {
            if (run) |r| r.deinit();
            run = null;
            block(n, v);
        }
    }
    if (run) |r| r.deinit();
}

fn bodyFont(st: Style) dvui.Font {
    var f = dvui.Font.theme(.body);
    if (st.size > 0) f = f.withSize(st.size);
    if (st.heading) f = f.withLineHeight(1.1);
    if (st.bold) f = f.withWeight(.bold);
    if (st.italic) f = f.withStyle(.italic);
    if (st.strike) f = f.withStrike(.{});
    return f;
}

fn insideItem(node: *const md.Node) bool {
    const p = node.parent orelse return false;
    return p.kind == .item or p.kind == .deflist_def or p.kind == .table_cell;
}

fn block(n: *md.Node, v: *View) void {
    const gap: f32 = 10;
    switch (n.kind) {
        .paragraph => {
            if (isAnswers(n)) {
                answersBlock(n, v);
                return;
            }
            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .id_extra = v.nextId(), .margin = .{ .h = if (insideItem(n)) 4 else gap }, .padding = .all(0) });
            defer tl.deinit();
            quiet(tl);
            inlines(tl, n, .{}, v);
        },
        .heading => {
            const base = dvui.Font.theme(.body).size;
            const scale: f32 = switch (n.level) {
                1 => 1.9,
                2 => 1.5,
                3 => 1.25,
                else => 1.1,
            };
            if (n.level <= 2) {
                // Space above a section, so headings read as breaks.
                _ = dvui.spacer(@src(), .{ .min_size_content = .{ .h = 8 }, .id_extra = v.nextId() });
            }
            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .id_extra = v.nextId(), .margin = .{ .h = 6 }, .padding = .all(0) });
            defer tl.deinit();
            quiet(tl);
            inlines(tl, n, .{ .bold = true, .size = base * scale, .heading = true }, v);
            if (n.level == 1) {
                _ = dvui.separator(@src(), .{ .expand = .horizontal, .id_extra = v.nextId(), .margin = .{ .h = 6 } });
            }
        },
        .code_block, .html_block => {
            var cb = dvui.box(@src(), .{}, .{ .expand = .horizontal, .background = true, .style = .window, .border = .all(1), .corners = .all(4), .padding = .all(8), .margin = .{ .h = gap }, .id_extra = v.nextId() });
            defer cb.deinit();
            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .id_extra = v.nextId(), .padding = .all(0), .font = dvui.Font.theme(.mono) });
            defer tl.deinit();
            quiet(tl);
            const text = std.mem.trimEnd(u8, n.literal, "\n");
            if (n.kind == .code_block) highlighted(tl, text, highlight.langFor(n.title, text)) else tl.addText(text, .{});
            if (n.kind == .code_block and dvui.button(@src(), "Copy", .{}, .{ .gravity_x = 1.0, .id_extra = v.nextId(), .margin = .{ .y = 4 } })) dvui.clipboardTextSet(text);
        },
        .thematic_break => {
            _ = dvui.separator(@src(), .{ .expand = .horizontal, .id_extra = v.nextId(), .margin = .{ .y = 6, .h = 10 } });
        },
        .block_quote => {
            var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .id_extra = v.nextId(), .margin = .{ .h = gap } });
            defer row.deinit();
            _ = dvui.separator(@src(), .{ .expand = .vertical, .min_size_content = .{ .w = 3 }, .color_fill = .{ .color = dvui.themeGet().focus }, .id_extra = v.nextId(), .margin = .{ .w = 10 } });
            var body = dvui.box(@src(), .{}, .{ .expand = .horizontal, .id_extra = v.nextId() });
            defer body.deinit();
            children(n, v);
        },
        .list => list(n, v),
        .table => table(n, v),
        .deflist => {
            var c = n.first_child;
            while (c) |item| : (c = item.next) {
                switch (item.kind) {
                    .deflist_term => {
                        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .id_extra = v.nextId(), .margin = .{ .h = 2 }, .padding = .all(0) });
                        defer tl.deinit();
                        quiet(tl);
                        inlines(tl, item, .{ .bold = true }, v);
                    },
                    else => {
                        var body = dvui.box(@src(), .{}, .{ .expand = .horizontal, .id_extra = v.nextId(), .margin = .{ .x = 18, .h = 6 } });
                        defer body.deinit();
                        children(item, v);
                    },
                }
            }
        },
        .footnote_def => children(n, v),
        // YAML front matter is metadata, not lesson text.
        .front_matter => {},
        else => {},
    }
}

fn children(n: *md.Node, v: *View) void {
    var c = n.first_child;
    while (c) |ch| : (c = ch.next) block(ch, v);
}

fn list(n: *md.Node, v: *View) void {
    var outer = dvui.box(@src(), .{}, .{ .expand = .horizontal, .id_extra = v.nextId(), .margin = .{ .x = 6, .h = 4 } });
    defer outer.deinit();
    var idx: u32 = n.list.start;
    var c = n.first_child;
    while (c) |item| : ({
        c = item.next;
        idx += 1;
    }) {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .id_extra = v.nextId() });
        defer row.deinit();

        var buf: [24]u8 = undefined;
        const marker: []const u8 = if (n.list.kind == .ordered)
            std.fmt.bufPrint(&buf, "{d}{c}", .{ idx, @as(u8, if (n.list.delimiter == ')') ')' else '.') }) catch "-"
        else switch (item.task) {
            .checked => "[x]",
            .unchecked => "[ ]",
            .none => "\u{2022}",
        };
        dvui.labelNoFmt(@src(), marker, .{}, .{ .min_size_content = .{ .w = 14 }, .gravity_y = 0, .id_extra = v.nextId(), .padding = .{ .x = 2, .w = 6 } });

        var body = dvui.box(@src(), .{}, .{ .expand = .horizontal, .id_extra = v.nextId() });
        defer body.deinit();
        children(item, v);
    }
    _ = dvui.spacer(@src(), .{ .min_size_content = .{ .h = 4 }, .id_extra = v.nextId() });
}

fn table(n: *md.Node, v: *View) void {
    var tb = dvui.box(@src(), .{}, .{ .expand = .horizontal, .id_extra = v.nextId(), .margin = .{ .h = 10 }, .border = .all(1), .corners = .all(4) });
    defer tb.deinit();
    // Every column gets an equal share of the table width, so cells line up from row to row.
    var cols: usize = 1;
    if (n.first_child) |first| {
        cols = 0;
        var cc = first.first_child;
        while (cc) |x| : (cc = x.next) cols += 1;
        cols = @max(cols, 1);
    }
    const col_w = @max(60, (tb.data().contentRect().w - 2) / @as(f32, @floatFromInt(cols)));
    var r = n.first_child;
    while (r) |row_node| : (r = row_node.next) {
        if (row_node.kind != .table_row) continue;
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .expand = .horizontal,
            .id_extra = v.nextId(),
            .background = row_node.header,
            .style = .window,
        });
        defer row.deinit();
        var c = row_node.first_child;
        while (c) |cell| : (c = cell.next) {
            var tl = dvui.textLayout(@src(), .{}, .{
                .background = false,
                .id_extra = v.nextId(),
                .padding = .{ .x = 8, .y = 4, .w = 8, .h = 4 },
                .min_size_content = .{ .w = col_w - 16 },
                .max_size_content = .{ .w = col_w - 16, .h = std.math.floatMax(f32) },
            });
            defer tl.deinit();
            quiet(tl);
            inlines(tl, cell, .{ .bold = row_node.header }, v);
        }
        if (row_node.next != null) _ = dvui.separator(@src(), .{ .expand = .horizontal, .id_extra = v.nextId() });
    }
}

/// Adds the inline children of `parent` to `tl`.
fn inlines(tl: *dvui.TextLayoutWidget, parent: *md.Node, st: Style, v: *View) void {
    var c = parent.first_child;
    while (c) |n| : (c = n.next) inlineNode(tl, n, st, v);
}

fn inlineNode(tl: *dvui.TextLayoutWidget, n: *md.Node, st: Style, v: *View) void {
    switch (n.kind) {
        .text => tl.addText(n.literal, .{ .font = bodyFont(st) }),
        .html_inline => tl.addText(n.literal, .{ .font = dvui.Font.theme(.mono) }),
        .softbreak => tl.addText(" ", .{ .font = bodyFont(st) }),
        .linebreak => tl.addText("\n", .{ .font = bodyFont(st) }),
        .code => {
            var mono = dvui.Font.theme(.mono);
            if (st.size > 0) mono = mono.withSize(st.size * 0.95);
            tl.addText(n.literal, .{ .font = mono, .color_text = .{ .color = dvui.themeGet().highlight.fill orelse dvui.themeGet().text } });
        },
        .emph => {
            var s = st;
            s.italic = true;
            inlines(tl, n, s, v);
        },
        .strong => {
            var s = st;
            s.bold = true;
            inlines(tl, n, s, v);
        },
        .strikethrough => {
            var s = st;
            s.strike = true;
            inlines(tl, n, s, v);
        },
        .link => {
            // One run per link: its text is the concatenation of the children (any markup inside is dropped).
            var buf: [512]u8 = undefined;
            var len: usize = 0;
            var walker = md.Walker.init(n);
            while (walker.next()) |ev| {
                if (!ev.entering) continue;
                const piece: []const u8 = switch (ev.node.kind) {
                    .text, .code => ev.node.literal,
                    .softbreak => " ",
                    else => "",
                };
                const take = @min(piece.len, buf.len - len);
                @memcpy(buf[len..][0..take], piece[0..take]);
                len += take;
            }
            const text = if (len == 0) n.literal else buf[0..len];
            var f = bodyFont(st).withUnderline(.{});
            f.weight = if (st.bold) .bold else .normal;
            // Run text lives in `buf` only until this call returns; dvui copies what it draws.
            if (tl.addTextClick(text, .{ .font = f, .color_text = .{ .color = dvui.themeGet().focus } })) |ev| {
                if (ev == .mouse and ev.mouse.action == .release and ev.mouse.button.pointer()) v.clicked = n.literal;
            }
        },
        .image => {
            tl.addText("[image: ", .{ .font = bodyFont(.{ .italic = true }) });
            inlines(tl, n, .{ .italic = true }, v);
            tl.addText("]", .{ .font = bodyFont(.{ .italic = true }) });
        },
        .footnote_ref => tl.addText("[note]", .{ .font = bodyFont(st) }),
        else => inlines(tl, n, st, v),
    }
}

fn rgb(r: u8, g: u8, b: u8) dvui.Color {
    return .{ .r = r, .g = g, .b = b };
}

/// Colour for a token kind; null keeps the theme's text colour.
fn tokenColor(kind: highlight.Kind, dark: bool) ?dvui.Color {
    return switch (kind) {
        .plain => null,
        .comment => if (dark) rgb(0x8b, 0x94, 0x9e) else rgb(0x6a, 0x73, 0x7d),
        .string => if (dark) rgb(0xa5, 0xd6, 0xff) else rgb(0x0a, 0x6b, 0x2f),
        .variable => if (dark) rgb(0xd2, 0xa8, 0xff) else rgb(0x82, 0x50, 0xdf),
        .keyword => if (dark) rgb(0xff, 0x7b, 0x72) else rgb(0xcf, 0x22, 0x2e),
        .command => if (dark) rgb(0x79, 0xc0, 0xff) else rgb(0x05, 0x50, 0xae),
        .param => if (dark) rgb(0xff, 0xa6, 0x57) else rgb(0x95, 0x38, 0x00),
        .number => if (dark) rgb(0x79, 0xc0, 0xff) else rgb(0x0a, 0x30, 0x69),
    };
}

/// Adds `text` to `tl` as coloured runs. Neighbouring tokens of one colour are one run.
fn highlighted(tl: *dvui.TextLayoutWidget, text: []const u8, lang: highlight.Lang) void {
    const dark = dvui.themeGet().dark;
    var lx = highlight.Lexer.init(text, lang);
    var run_start: usize = 0;
    var run_end: usize = 0;
    var run_kind: highlight.Kind = .plain;
    while (lx.next()) |t| {
        // Whitespace joins whatever run is open; it has no colour of its own.
        const joins = t.kind == run_kind or (t.kind == .plain and std.mem.indexOfNone(u8, t.text, " \t\r\n") == null);
        if (joins) {
            run_end += t.text.len;
            continue;
        }
        flush(tl, text[run_start..run_end], run_kind, dark);
        run_start = run_end;
        run_end += t.text.len;
        run_kind = t.kind;
    }
    flush(tl, text[run_start..run_end], run_kind, dark);
}

fn flush(tl: *dvui.TextLayoutWidget, s: []const u8, kind: highlight.Kind, dark: bool) void {
    if (s.len == 0) return;
    if (tokenColor(kind, dark)) |c| tl.addText(s, .{ .color_text = .{ .color = c } }) else tl.addText(s, .{});
}

/// A selection made by click and drag belongs to one text block. Without this, every block keeps its
/// highlight after the user clicks somewhere else; only the focused block may hold a selection.
fn quiet(tl: *dvui.TextLayoutWidget) void {
    var outside = dvui.focusedWidgetId() != tl.data().id;
    const r = tl.data().borderRectScale().r;
    for (dvui.events()) |*e| {
        if (e.evt != .mouse or e.evt.mouse.action != .press or !e.evt.mouse.button.pointer()) continue;
        if (!r.contains(e.evt.mouse.p)) outside = true;
    }
    if (outside) {
        tl.selection.start = 0;
        tl.selection.end = 0;
        tl.selection.cursor = 0;
    }
}

/// A paragraph that starts with the bold words "Answers" or "Expected answers" holds the answers to a
/// "Check yourself" list. It stays hidden until the learner asks, so the questions can be tried first.
fn isAnswers(n: *md.Node) bool {
    const strong = n.first_child orelse return false;
    if (strong.kind != .strong) return false;
    const t = strong.first_child orelse return false;
    if (t.kind != .text) return false;
    return std.ascii.startsWithIgnoreCase(t.literal, "answer") or std.ascii.startsWithIgnoreCase(t.literal, "expected answer");
}

fn answersBlock(n: *md.Node, v: *View) void {
    var bx = dvui.box(@src(), .{}, .{ .expand = .horizontal, .background = false, .id_extra = (v.page + 1) * 100000 + v.nextId() });
    defer bx.deinit();
    const shown = dvui.dataGetPtrDefault(null, bx.data().id, "shown", bool, false);
    if (dvui.button(@src(), if (shown.*) "Hide answers" else "Show answers", .{}, .{ .margin = .{ .h = 6 } })) shown.* = !shown.*;
    if (shown.*) {
        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(0), .margin = .{ .h = 10 } });
        defer tl.deinit();
        quiet(tl);
        inlines(tl, n, .{}, v);
    }
}

// ---- Flowing text: paragraphs, headings and simple lists in one widget ----

/// A block that can be written into a shared text layout: prose, a heading, or a list whose items hold
/// only prose and nested lists.
fn flowable(n: *md.Node) bool {
    return switch (n.kind) {
        .paragraph => !isAnswers(n),
        .heading => true,
        .list => listFlowable(n),
        else => false,
    };
}

fn listFlowable(n: *md.Node) bool {
    var item = n.first_child;
    while (item) |it| : (item = it.next) {
        var ch = it.first_child;
        while (ch) |c| : (ch = c.next) {
            switch (c.kind) {
                .paragraph => if (isAnswers(c)) return false,
                .list => if (!listFlowable(c)) return false,
                else => return false,
            }
        }
    }
    return true;
}

/// A short empty line: the gap between blocks of the shared layout.
fn softGap(tl: *dvui.TextLayoutWidget, scale: f32) void {
    const base = dvui.Font.theme(.body);
    tl.addText("\n", .{ .font = base.withSize(base.size * scale) });
}

fn flow(tl: *dvui.TextLayoutWidget, n: *md.Node, v: *View, depth: usize) void {
    switch (n.kind) {
        .paragraph => {
            inlines(tl, n, .{}, v);
            tl.addText("\n", .{ .font = bodyFont(.{}) });
            if (depth == 0) softGap(tl, 0.25);
        },
        .heading => {
            const base = dvui.Font.theme(.body).size;
            const scale: f32 = switch (n.level) {
                1 => 1.9,
                2 => 1.5,
                3 => 1.25,
                else => 1.1,
            };
            if (n.level <= 2 and tl.bytes_seen > 0) softGap(tl, 0.45);
            const st: Style = .{ .bold = true, .size = base * scale, .heading = true };
            inlines(tl, n, st, v);
            tl.addText("\n", .{ .font = bodyFont(st) });
            softGap(tl, 0.15);
        },
        .list => {
            var idx: u32 = n.list.start;
            var item = n.first_child;
            while (item) |it| : ({
                item = it.next;
                idx += 1;
            }) {
                var buf: [24]u8 = undefined;
                const marker: []const u8 = if (n.list.kind == .ordered)
                    std.fmt.bufPrint(&buf, "{d}{c}", .{ idx, @as(u8, if (n.list.delimiter == ')') ')' else '.') }) catch "-"
                else switch (it.task) {
                    .checked => "[x]",
                    .unchecked => "[ ]",
                    .none => "\u{2022}",
                };
                var pad_buf: [64]u8 = undefined;
                const pad_len = @min(depth * 4 + 2, pad_buf.len);
                @memset(pad_buf[0..pad_len], ' ');
                tl.addText(pad_buf[0..pad_len], .{ .font = bodyFont(.{}) });
                tl.addText(marker, .{ .font = bodyFont(.{}) });
                tl.addText("  ", .{ .font = bodyFont(.{}) });
                var first = true;
                var ch = it.first_child;
                while (ch) |c| : (ch = c.next) {
                    switch (c.kind) {
                        .paragraph => {
                            if (!first) tl.addText(pad_buf[0..pad_len], .{ .font = bodyFont(.{}) });
                            inlines(tl, c, .{}, v);
                            tl.addText("\n", .{ .font = bodyFont(.{}) });
                        },
                        .list => {
                            if (first) tl.addText("\n", .{ .font = bodyFont(.{}) });
                            flow(tl, c, v, depth + 1);
                        },
                        else => {},
                    }
                    first = false;
                }
            }
            if (depth == 0) softGap(tl, 0.25);
        },
        else => {},
    }
}
