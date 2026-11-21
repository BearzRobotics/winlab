//! A VT/ANSI screen model: feed it the bytes a ConPTY produces and it maintains
//! a grid of cells, a cursor, a scrollback buffer and any replies the shell is
//! waiting for (cursor position, device attributes). UI-independent and fully
//! testable. Terminal output is untrusted input (AGENTS.md): unknown or
//! malformed sequences are ignored, nothing is ever executed or interpreted
//! beyond drawing characters, and all sizes are bounded.
//!
//! Supported: printable UTF-8, CR/LF/BS/TAB, cursor movement and positioning,
//! erase (display/line/chars), insert/delete (lines/chars), scroll regions,
//! SGR colours and attributes (16, 256 and truecolor), cursor visibility,
//! alternate screen, save/restore cursor, DSR 6 and DA replies, and the OSC
//! title and working-directory announcements (kept as bounded display text).
//! Other OSC and all DCS strings are consumed and discarded.
const std = @import("std");

pub const default_color: u32 = 0xFF000000;

pub const Attr = packed struct(u8) {
    bold: bool = false,
    underline: bool = false,
    reverse: bool = false,
    _pad: u5 = 0,
};

pub const Cell = struct {
    ch: u21 = ' ',
    fg: u32 = default_color,
    bg: u32 = default_color,
    attr: Attr = .{},
};

const max_params = 16;
const max_scrollback = 5000;
const max_dim = 500;

const ansi16 = [16]u32{
    0x000000, 0xCD3131, 0x0DBC79, 0xE5E510, 0x2472C8, 0xBC3FBC, 0x11A8CD, 0xE5E5E5,
    0x666666, 0xF14C4C, 0x23D18B, 0xF5F543, 0x3B8EEA, 0xD670D6, 0x29B8DB, 0xFFFFFF,
};

fn palette256(n: u32) u32 {
    if (n < 16) return ansi16[n];
    if (n < 232) {
        const i = n - 16;
        const levels = [6]u32{ 0, 95, 135, 175, 215, 255 };
        return (levels[i / 36] << 16) | (levels[(i / 6) % 6] << 8) | levels[i % 6];
    }
    const g = 8 + (n - 232) * 10;
    return (g << 16) | (g << 8) | g;
}

const State = enum { ground, esc, esc_inter, csi, osc, osc_esc, dcs, dcs_esc };

pub const Screen = struct {
    gpa: std.mem.Allocator,
    cols: u16,
    rows: u16,
    grid: []Cell,
    /// Primary-screen content parked while the alternate screen is shown.
    saved_grid: ?[]Cell = null,
    scrollback: std.ArrayList([]Cell) = .empty,
    cx: u16 = 0,
    cy: u16 = 0,
    wrap_pending: bool = false,
    pen: Cell = .{},
    saved_cursor: struct { x: u16 = 0, y: u16 = 0, pen: Cell = .{} } = .{},
    top: u16 = 0,
    bottom: u16, // inclusive
    cursor_visible: bool = true,
    alt_active: bool = false,
    /// Bytes to send back to the shell (replies to queries); drain with `takeReplies`.
    replies: std.ArrayList(u8) = .empty,
    /// Window title set by the shell (OSC 0/2) and working directory announced by it
    /// (OSC 9;9, which some prompts emit). Untrusted text: bounded, display only.
    title_buf: [256]u8 = undefined,
    title_len: usize = 0,
    cwd_buf: [512]u8 = undefined,
    cwd_len: usize = 0,
    osc_buf: [512]u8 = undefined,
    osc_len: usize = 0,
    /// Incremented on every change, so a window knows when to repaint.
    generation: u64 = 0,

    state: State = .ground,
    params: [max_params]u32 = @splat(0),
    nparams: usize = 0,
    have_param: bool = false,
    private: bool = false,
    utf8_left: u3 = 0,
    utf8_acc: u21 = 0,

    pub fn init(gpa: std.mem.Allocator, cols: u16, rows: u16) !Screen {
        const c = std.math.clamp(cols, 1, max_dim);
        const r = std.math.clamp(rows, 1, max_dim);
        const grid = try gpa.alloc(Cell, @as(usize, c) * r);
        @memset(grid, .{});
        return .{ .gpa = gpa, .cols = c, .rows = r, .grid = grid, .bottom = r - 1 };
    }

    pub fn deinit(self: *Screen) void {
        self.gpa.free(self.grid);
        if (self.saved_grid) |g| self.gpa.free(g);
        for (self.scrollback.items) |l| self.gpa.free(l);
        self.scrollback.deinit(self.gpa);
        self.replies.deinit(self.gpa);
        self.* = undefined;
    }

    // ---- reading -------------------------------------------------------

    pub fn cell(self: *const Screen, x: u16, y: u16) *const Cell {
        return &self.grid[@as(usize, y) * self.cols + x];
    }

    /// Lines available to scroll through: scrollback plus the visible rows.
    pub fn totalLines(self: *const Screen) usize {
        return self.scrollback.items.len + self.rows;
    }

    /// Line `i` of scrollback-then-screen. A scrollback line may be shorter than `cols` after a resize.
    pub fn line(self: *const Screen, i: usize) []const Cell {
        const sb = self.scrollback.items.len;
        if (i < sb) return self.scrollback.items[i];
        const y = i - sb;
        return self.grid[y * self.cols ..][0..self.cols];
    }

    /// Takes the pending replies; caller frees with `gpa`.
    pub fn takeReplies(self: *Screen) ![]u8 {
        return self.replies.toOwnedSlice(self.gpa);
    }

    /// Plain text of one line with trailing blanks removed (UTF-8, caller frees).
    pub fn lineText(self: *const Screen, gpa: std.mem.Allocator, i: usize) ![]u8 {
        const cells = self.line(i);
        var end = cells.len;
        while (end > 0 and cells[end - 1].ch == ' ') end -= 1;
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        for (cells[0..end]) |c| {
            var b: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(c.ch, &b) catch continue;
            try out.appendSlice(gpa, b[0..n]);
        }
        return out.toOwnedSlice(gpa);
    }

    // ---- input ---------------------------------------------------------

    pub fn feed(self: *Screen, bytes: []const u8) std.mem.Allocator.Error!void {
        for (bytes) |b| try self.byte(b);
        self.generation +%= 1;
    }

    fn byte(self: *Screen, b: u8) !void {
        switch (self.state) {
            .ground => try self.ground(b),
            .esc => try self.escape(b),
            .esc_inter => self.state = .ground, // one byte after ESC ( ) # etc.; ignored
            .csi => try self.csiByte(b),
            .osc => switch (b) {
                0x07 => {
                    self.state = .ground;
                    self.finishOsc();
                },
                0x1B => self.state = .osc_esc,
                else => if (b >= 0x20 and self.osc_len < self.osc_buf.len) {
                    self.osc_buf[self.osc_len] = b;
                    self.osc_len += 1;
                },
            },
            .osc_esc => {
                self.state = if (b == '\\') .ground else .osc;
                if (b == '\\') self.finishOsc();
            },
            .dcs => if (b == 0x1B) {
                self.state = .dcs_esc;
            },
            .dcs_esc => self.state = if (b == '\\') .ground else .dcs,
        }
    }

    fn ground(self: *Screen, b: u8) !void {
        if (self.utf8_left > 0) {
            if (b & 0xC0 == 0x80) {
                self.utf8_acc = (self.utf8_acc << 6) | (b & 0x3F);
                self.utf8_left -= 1;
                if (self.utf8_left == 0) try self.put(if (std.unicode.utf8ValidCodepoint(self.utf8_acc)) self.utf8_acc else 0xFFFD);
                return;
            }
            self.utf8_left = 0; // broken sequence: fall through and treat this byte normally
            try self.put(0xFFFD);
        }
        switch (b) {
            0x07 => {},
            0x08 => {
                if (self.cx > 0) self.cx -= 1;
                self.wrap_pending = false;
            },
            0x09 => {
                self.cx = @min(((self.cx / 8) + 1) * 8, self.cols - 1);
                self.wrap_pending = false;
            },
            0x0A, 0x0B, 0x0C => try self.lineFeed(),
            0x0D => {
                self.cx = 0;
                self.wrap_pending = false;
            },
            0x1B => self.state = .esc,
            0x20...0x7E => try self.put(b),
            0xC2...0xDF => {
                self.utf8_left = 1;
                self.utf8_acc = b & 0x1F;
            },
            0xE0...0xEF => {
                self.utf8_left = 2;
                self.utf8_acc = b & 0x0F;
            },
            0xF0...0xF4 => {
                self.utf8_left = 3;
                self.utf8_acc = b & 0x07;
            },
            else => {},
        }
    }

    fn escape(self: *Screen, b: u8) !void {
        self.state = .ground;
        switch (b) {
            '[' => {
                self.state = .csi;
                self.nparams = 0;
                self.have_param = false;
                self.private = false;
                @memset(&self.params, 0);
            },
            ']' => {
                self.state = .osc;
                self.osc_len = 0;
            },
            'P', 'X', '^', '_' => self.state = .dcs,
            '(', ')', '*', '+', '#', '%' => self.state = .esc_inter,
            'M' => try self.reverseIndex(),
            'D' => try self.lineFeed(),
            'E' => {
                self.cx = 0;
                try self.lineFeed();
            },
            '7' => self.saveCursor(),
            '8' => self.restoreCursor(),
            'c' => try self.reset(),
            else => {},
        }
    }

    fn csiByte(self: *Screen, b: u8) !void {
        switch (b) {
            '0'...'9' => {
                if (self.nparams < max_params) {
                    self.params[self.nparams] = @min(self.params[self.nparams] *| 10 +| (b - '0'), 65535);
                    self.have_param = true;
                }
            },
            ';' => {
                if (self.nparams < max_params) self.nparams += 1;
                self.have_param = false;
            },
            '?', '>', '<', '=' => self.private = b == '?',
            0x20...0x2F => {}, // intermediate bytes (for example "ESC [ 1 SP q") are ignored
            0x40...0x7E => {
                if (self.have_param and self.nparams < max_params) self.nparams += 1;
                self.state = .ground;
                try self.csiDispatch(b);
            },
            0x1B => self.state = .esc,
            else => self.state = .ground,
        }
    }

    fn param(self: *const Screen, i: usize, default: u32) u32 {
        if (i >= self.nparams) return default;
        const v = self.params[i];
        return if (v == 0) default else v;
    }

    fn csiDispatch(self: *Screen, final: u8) !void {
        const n = self.param(0, 1);
        switch (final) {
            'A' => self.moveTo(self.cx, self.cy -| @as(u16, @intCast(@min(n, 65535)))),
            'B' => self.moveTo(self.cx, self.cy +| @as(u16, @intCast(@min(n, 65535)))),
            'C' => self.moveTo(self.cx +| @as(u16, @intCast(@min(n, 65535))), self.cy),
            'D' => self.moveTo(self.cx -| @as(u16, @intCast(@min(n, 65535))), self.cy),
            'E' => self.moveTo(0, self.cy +| @as(u16, @intCast(@min(n, 65535)))),
            'F' => self.moveTo(0, self.cy -| @as(u16, @intCast(@min(n, 65535)))),
            'G', '`' => self.moveTo(@intCast(@min(n - 1, 65535)), self.cy),
            'd' => self.moveTo(self.cx, @intCast(@min(n - 1, 65535))),
            'H', 'f' => self.moveTo(@intCast(@min(self.param(1, 1) - 1, 65535)), @intCast(@min(self.param(0, 1) - 1, 65535))),
            'J' => self.eraseDisplay(if (self.nparams == 0) 0 else self.params[0]),
            'K' => self.eraseLine(if (self.nparams == 0) 0 else self.params[0]),
            'L' => self.insertLines(n),
            'M' => self.deleteLines(n),
            '@' => self.insertChars(n),
            'P' => self.deleteChars(n),
            'X' => self.eraseChars(n),
            'S' => for (0..@min(n, max_dim)) |_| try self.scrollUp(),
            'T' => for (0..@min(n, max_dim)) |_| self.scrollDown(),
            'm' => self.sgr(),
            'r' => {
                const t = self.param(0, 1) - 1;
                const b = self.param(1, self.rows) - 1;
                if (t < b and b < self.rows) {
                    self.top = @intCast(t);
                    self.bottom = @intCast(b);
                    self.moveTo(0, 0);
                }
            },
            's' => if (!self.private) self.saveCursor(),
            'u' => if (!self.private) self.restoreCursor(),
            'h', 'l' => if (self.private) try self.privateMode(self.param(0, 0), final == 'h'),
            'n' => if (!self.private and self.param(0, 0) == 6) {
                try self.replies.print(self.gpa, "\x1b[{d};{d}R", .{ @as(u32, self.cy) + 1, @as(u32, self.cx) + 1 });
            },
            'c' => if (!self.private and self.param(0, 0) == 0) try self.replies.appendSlice(self.gpa, "\x1b[?1;0c"),
            else => {},
        }
    }

    fn finishOsc(self: *Screen) void {
        const s = self.osc_buf[0..self.osc_len];
        if (std.mem.startsWith(u8, s, "0;") or std.mem.startsWith(u8, s, "2;")) {
            const t = s[2..];
            const n = @min(t.len, self.title_buf.len);
            @memcpy(self.title_buf[0..n], t[0..n]);
            self.title_len = n;
        } else if (std.mem.startsWith(u8, s, "9;9;")) {
            var t = s[4..];
            if (t.len >= 2 and t[0] == '"' and t[t.len - 1] == '"') t = t[1 .. t.len - 1];
            const n = @min(t.len, self.cwd_buf.len);
            @memcpy(self.cwd_buf[0..n], t[0..n]);
            self.cwd_len = n;
        }
    }

    pub fn title(self: *const Screen) []const u8 {
        return self.title_buf[0..self.title_len];
    }

    pub fn cwd(self: *const Screen) []const u8 {
        return self.cwd_buf[0..self.cwd_len];
    }

    fn privateMode(self: *Screen, mode: u32, on: bool) !void {
        switch (mode) {
            25 => self.cursor_visible = on,
            47, 1047, 1049 => try self.setAlt(on),
            else => {},
        }
    }

    // ---- editing primitives -------------------------------------------

    fn moveTo(self: *Screen, x: u16, y: u16) void {
        self.cx = @min(x, self.cols - 1);
        self.cy = @min(y, self.rows - 1);
        self.wrap_pending = false;
    }

    fn at(self: *Screen, x: u16, y: u16) *Cell {
        return &self.grid[@as(usize, y) * self.cols + x];
    }

    fn blank(self: *const Screen) Cell {
        return .{ .bg = self.pen.bg };
    }

    fn put(self: *Screen, ch: u21) !void {
        if (self.wrap_pending) {
            self.cx = 0;
            self.wrap_pending = false;
            try self.lineFeed();
        }
        var c = self.pen;
        c.ch = ch;
        self.at(self.cx, self.cy).* = c;
        if (self.cx + 1 >= self.cols) self.wrap_pending = true else self.cx += 1;
    }

    fn lineFeed(self: *Screen) !void {
        self.wrap_pending = false;
        if (self.cy == self.bottom) try self.scrollUp() else if (self.cy + 1 < self.rows) self.cy += 1;
    }

    fn reverseIndex(self: *Screen) !void {
        self.wrap_pending = false;
        if (self.cy == self.top) self.scrollDown() else if (self.cy > 0) self.cy -= 1;
    }

    fn rowSlice(self: *Screen, y: u16) []Cell {
        return self.grid[@as(usize, y) * self.cols ..][0..self.cols];
    }

    /// Scrolls the region up one line; the top line joins the scrollback when the
    /// region is the whole primary screen.
    fn scrollUp(self: *Screen) !void {
        if (self.top == 0 and self.bottom == self.rows - 1 and !self.alt_active) {
            const copy = try self.gpa.dupe(Cell, self.rowSlice(0));
            errdefer self.gpa.free(copy);
            try self.scrollback.append(self.gpa, copy);
            if (self.scrollback.items.len > max_scrollback) {
                const drop = 500;
                for (self.scrollback.items[0..drop]) |l| self.gpa.free(l);
                std.mem.copyForwards([]Cell, self.scrollback.items, self.scrollback.items[drop..]);
                self.scrollback.shrinkRetainingCapacity(self.scrollback.items.len - drop);
            }
        }
        var y = self.top;
        while (y < self.bottom) : (y += 1) @memcpy(self.rowSlice(y), self.rowSlice(y + 1));
        @memset(self.rowSlice(self.bottom), self.blank());
    }

    fn scrollDown(self: *Screen) void {
        var y = self.bottom;
        while (y > self.top) : (y -= 1) @memcpy(self.rowSlice(y), self.rowSlice(y - 1));
        @memset(self.rowSlice(self.top), self.blank());
    }

    fn eraseDisplay(self: *Screen, mode: u32) void {
        const b = self.blank();
        switch (mode) {
            0 => {
                @memset(self.rowSlice(self.cy)[self.cx..], b);
                for (self.cy + 1..self.rows) |y| @memset(self.rowSlice(@intCast(y)), b);
            },
            1 => {
                for (0..self.cy) |y| @memset(self.rowSlice(@intCast(y)), b);
                @memset(self.rowSlice(self.cy)[0 .. self.cx + 1], b);
            },
            2 => @memset(self.grid, b),
            3 => {
                for (self.scrollback.items) |l| self.gpa.free(l);
                self.scrollback.clearRetainingCapacity();
            },
            else => {},
        }
    }

    fn eraseLine(self: *Screen, mode: u32) void {
        const row = self.rowSlice(self.cy);
        const b = self.blank();
        switch (mode) {
            0 => @memset(row[self.cx..], b),
            1 => @memset(row[0 .. self.cx + 1], b),
            2 => @memset(row, b),
            else => {},
        }
    }

    fn insertLines(self: *Screen, n: u32) void {
        if (self.cy < self.top or self.cy > self.bottom) return;
        const saved_top = self.top;
        self.top = self.cy;
        for (0..@min(n, max_dim)) |_| self.scrollDown();
        self.top = saved_top;
    }

    fn deleteLines(self: *Screen, n: u32) void {
        if (self.cy < self.top or self.cy > self.bottom) return;
        const saved_top = self.top;
        self.top = self.cy;
        const was_alt = self.alt_active;
        self.alt_active = true; // deleting lines must not push them into scrollback
        for (0..@min(n, max_dim)) |_| self.scrollUp() catch {};
        self.alt_active = was_alt;
        self.top = saved_top;
    }

    fn insertChars(self: *Screen, n: u32) void {
        const row = self.rowSlice(self.cy);
        const k: usize = @min(n, self.cols - self.cx);
        std.mem.copyBackwards(Cell, row[self.cx + k ..], row[self.cx .. row.len - k]);
        @memset(row[self.cx .. self.cx + k], self.blank());
    }

    fn deleteChars(self: *Screen, n: u32) void {
        const row = self.rowSlice(self.cy);
        const k: usize = @min(n, self.cols - self.cx);
        std.mem.copyForwards(Cell, row[self.cx..], row[self.cx + k ..]);
        @memset(row[row.len - k ..], self.blank());
    }

    fn eraseChars(self: *Screen, n: u32) void {
        const row = self.rowSlice(self.cy);
        const k: usize = @min(n, self.cols - self.cx);
        @memset(row[self.cx .. self.cx + k], self.blank());
    }

    fn saveCursor(self: *Screen) void {
        self.saved_cursor = .{ .x = self.cx, .y = self.cy, .pen = self.pen };
    }

    fn restoreCursor(self: *Screen) void {
        self.moveTo(self.saved_cursor.x, self.saved_cursor.y);
        self.pen = self.saved_cursor.pen;
    }

    fn setAlt(self: *Screen, on: bool) !void {
        if (on == self.alt_active) return;
        if (on) {
            const fresh = try self.gpa.alloc(Cell, self.grid.len);
            @memset(fresh, .{});
            self.saved_grid = self.grid;
            self.grid = fresh;
            self.alt_active = true;
        } else {
            self.gpa.free(self.grid);
            self.grid = self.saved_grid.?;
            self.saved_grid = null;
            self.alt_active = false;
        }
        self.top = 0;
        self.bottom = self.rows - 1;
    }

    fn reset(self: *Screen) !void {
        if (self.alt_active) try self.setAlt(false);
        @memset(self.grid, .{});
        self.pen = .{};
        self.cx = 0;
        self.cy = 0;
        self.top = 0;
        self.bottom = self.rows - 1;
        self.cursor_visible = true;
        self.wrap_pending = false;
    }

    fn sgr(self: *Screen) void {
        if (self.nparams == 0) {
            self.pen = .{};
            return;
        }
        var i: usize = 0;
        while (i < self.nparams) : (i += 1) {
            const p = self.params[i];
            switch (p) {
                0 => self.pen = .{},
                1 => self.pen.attr.bold = true,
                4 => self.pen.attr.underline = true,
                7 => self.pen.attr.reverse = true,
                22 => self.pen.attr.bold = false,
                24 => self.pen.attr.underline = false,
                27 => self.pen.attr.reverse = false,
                30...37 => self.pen.fg = ansi16[p - 30],
                39 => self.pen.fg = default_color,
                40...47 => self.pen.bg = ansi16[p - 40],
                49 => self.pen.bg = default_color,
                90...97 => self.pen.fg = ansi16[p - 90 + 8],
                100...107 => self.pen.bg = ansi16[p - 100 + 8],
                38, 48 => {
                    var color: ?u32 = null;
                    if (i + 2 < self.nparams and self.params[i + 1] == 5) {
                        color = palette256(@min(self.params[i + 2], 255));
                        i += 2;
                    } else if (i + 4 < self.nparams and self.params[i + 1] == 2) {
                        const rr: u32 = @min(self.params[i + 2], 255);
                        const gg: u32 = @min(self.params[i + 3], 255);
                        const bb: u32 = @min(self.params[i + 4], 255);
                        color = (rr << 16) | (gg << 8) | bb;
                        i += 4;
                    }
                    if (color) |c| {
                        if (p == 38) self.pen.fg = c else self.pen.bg = c;
                    }
                },
                else => {},
            }
        }
    }

    // ---- size ----------------------------------------------------------

    /// Changes the grid size. Content is kept top-left; if the cursor would fall
    /// off the bottom, the top lines move into the scrollback instead.
    pub fn resize(self: *Screen, cols: u16, rows: u16) !void {
        const nc = std.math.clamp(cols, 1, max_dim);
        const nr = std.math.clamp(rows, 1, max_dim);
        if (nc == self.cols and nr == self.rows) return;
        if (self.alt_active) try self.setAlt(false);
        var shift: u16 = 0;
        if (self.cy >= nr) shift = self.cy - nr + 1;
        for (0..shift) |y| {
            const copy = try self.gpa.dupe(Cell, self.rowSlice(@intCast(y)));
            errdefer self.gpa.free(copy);
            try self.scrollback.append(self.gpa, copy);
        }
        const fresh = try self.gpa.alloc(Cell, @as(usize, nc) * nr);
        @memset(fresh, .{});
        const copy_rows = @min(self.rows - shift, nr);
        const copy_cols = @min(self.cols, nc);
        for (0..copy_rows) |y| {
            @memcpy(fresh[y * nc ..][0..copy_cols], self.rowSlice(@intCast(y + shift))[0..copy_cols]);
        }
        self.gpa.free(self.grid);
        self.grid = fresh;
        self.cols = nc;
        self.rows = nr;
        self.cy -= shift;
        self.cx = @min(self.cx, nc - 1);
        self.top = 0;
        self.bottom = nr - 1;
        self.wrap_pending = false;
        self.generation +%= 1;
    }
};

fn rowString(s: *const Screen, y: u16, buf: []u8) []const u8 {
    var n: usize = 0;
    for (0..s.cols) |x| {
        const c = s.cell(@intCast(x), y).ch;
        buf[n] = if (c < 128) @intCast(c) else '?';
        n += 1;
    }
    while (n > 0 and buf[n - 1] == ' ') n -= 1;
    return buf[0..n];
}

test "text, newline and carriage return" {
    var s = try Screen.init(std.testing.allocator, 20, 5);
    defer s.deinit();
    try s.feed("hello\r\nworld");
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("hello", rowString(&s, 0, &buf));
    try std.testing.expectEqualStrings("world", rowString(&s, 1, &buf));
    try std.testing.expectEqual(@as(u16, 5), s.cx);
}

test "cursor positioning, erase and SGR" {
    var s = try Screen.init(std.testing.allocator, 20, 5);
    defer s.deinit();
    try s.feed("\x1b[2J\x1b[3;4H\x1b[31mX\x1b[0mY\x1b[1;1Hab\x1b[K");
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("ab", rowString(&s, 0, &buf));
    try std.testing.expectEqual(@as(u21, 'X'), s.cell(3, 2).ch);
    try std.testing.expectEqual(@as(u32, 0xCD3131), s.cell(3, 2).fg);
    try std.testing.expectEqual(default_color, s.cell(4, 2).fg);
}

test "scrolling fills the scrollback" {
    var s = try Screen.init(std.testing.allocator, 10, 3);
    defer s.deinit();
    try s.feed("1\r\n2\r\n3\r\n4\r\n5");
    try std.testing.expectEqual(@as(usize, 2), s.scrollback.items.len);
    const t = try s.lineText(std.testing.allocator, 0);
    defer std.testing.allocator.free(t);
    try std.testing.expectEqualStrings("1", t);
    try std.testing.expectEqual(@as(usize, 5), s.totalLines());
}

test "wrapping at the right edge" {
    var s = try Screen.init(std.testing.allocator, 4, 3);
    defer s.deinit();
    try s.feed("abcdef");
    var buf: [8]u8 = undefined;
    try std.testing.expectEqualStrings("abcd", rowString(&s, 0, &buf));
    try std.testing.expectEqualStrings("ef", rowString(&s, 1, &buf));
}

test "UTF-8, broken UTF-8 and unknown sequences do not crash" {
    var s = try Screen.init(std.testing.allocator, 20, 3);
    defer s.deinit();
    try s.feed("caf\xc3\xa9 \xe6\x97\xa5\xe6\x9c\xac \xff\xc3(\x1b[999999999;99999Z\x1b]0;title\x07\x1bPjunk\x1b\\ok");
    try std.testing.expectEqual(@as(u21, 0xE9), s.cell(3, 0).ch);
    try std.testing.expectEqual(@as(u21, 0x65E5), s.cell(5, 0).ch);
}

test "cursor position report and device attributes replies" {
    var s = try Screen.init(std.testing.allocator, 20, 5);
    defer s.deinit();
    try s.feed("\x1b[2;3H\x1b[6n\x1b[c");
    const r = try s.takeReplies();
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("\x1b[2;3R\x1b[?1;0c", r);
}

test "alternate screen preserves the primary screen" {
    var s = try Screen.init(std.testing.allocator, 10, 3);
    defer s.deinit();
    try s.feed("keep\x1b[?1049h\x1b[2JALT\x1b[?1049l");
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("keep", rowString(&s, 0, &buf));
}

test "scroll region, insert and delete" {
    var s = try Screen.init(std.testing.allocator, 6, 4);
    defer s.deinit();
    try s.feed("a\r\nb\r\nc\r\nd\x1b[2;1H\x1b[M");
    var buf: [8]u8 = undefined;
    try std.testing.expectEqualStrings("a", rowString(&s, 0, &buf));
    try std.testing.expectEqualStrings("c", rowString(&s, 1, &buf));
    try std.testing.expectEqualStrings("d", rowString(&s, 2, &buf));
    try std.testing.expectEqualStrings("", rowString(&s, 3, &buf));
    try std.testing.expectEqual(@as(usize, 0), s.scrollback.items.len);
}

test "resize keeps the cursor line visible" {
    var s = try Screen.init(std.testing.allocator, 10, 4);
    defer s.deinit();
    try s.feed("a\r\nb\r\nc\r\nd");
    try s.resize(10, 2);
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("d", rowString(&s, 1, &buf));
    try std.testing.expectEqual(@as(usize, 2), s.scrollback.items.len);
}

test "title and working directory announcements" {
    var s = try Screen.init(std.testing.allocator, 20, 3);
    defer s.deinit();
    try s.feed("\x1b]0;My shell\x07\x1b]9;9;\"C:\\Users\\me\"\x1b\\x");
    try std.testing.expectEqualStrings("My shell", s.title());
    try std.testing.expectEqualStrings("C:\\Users\\me", s.cwd());
    try std.testing.expectEqual(@as(u21, 'x'), s.cell(0, 0).ch);
}
