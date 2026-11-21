//! Terminal window: a real shell (via ConPTY) shown in a GDI-drawn character
//! grid. WinLab only moves bytes and draws the screen model; the shell's own
//! behaviour is untouched. The shell runs on the HOST as the current user (no
//! elevation), and the window title says so.
//!
//! Accessibility note: a custom-drawn grid is not exposed to screen readers the
//! way a standard control is. Ctrl+Shift+A copies the whole buffer as text as a
//! workaround; see docs/decisions/0005-terminal.md.
const std = @import("std");
const winlab = @import("winlab");
const conpty = winlab.conpty;
const Screen = winlab.terminal_screen.Screen;
const Cell = winlab.terminal_screen.Cell;
const default_color = winlab.terminal_screen.default_color;

const HWND = ?*anyopaque;
const HANDLE = ?*anyopaque;
const BOOL = i32;
const WPARAM = usize;
const LPARAM = isize;
const LRESULT = isize;
const WNDPROC = *const fn (HWND, u32, WPARAM, LPARAM) callconv(.winapi) LRESULT;

const RECT = extern struct { left: i32 = 0, top: i32 = 0, right: i32 = 0, bottom: i32 = 0 };
const PAINTSTRUCT = extern struct { hdc: HANDLE, fErase: BOOL, rcPaint: RECT, fRestore: BOOL, fIncUpdate: BOOL, rgbReserved: [32]u8 };
const TEXTMETRICW = extern struct {
    tmHeight: i32,
    tmAscent: i32,
    tmDescent: i32,
    tmInternalLeading: i32,
    tmExternalLeading: i32,
    tmAveCharWidth: i32,
    tmMaxCharWidth: i32,
    tmWeight: i32,
    tmOverhang: i32,
    tmDigitizedAspectX: i32,
    tmDigitizedAspectY: i32,
    tmFirstChar: u16,
    tmLastChar: u16,
    tmDefaultChar: u16,
    tmBreakChar: u16,
    tmItalic: u8,
    tmUnderlined: u8,
    tmStruckOut: u8,
    tmPitchAndFamily: u8,
    tmCharSet: u8,
};
const WNDCLASSEXW = extern struct {
    cbSize: u32 = @sizeOf(WNDCLASSEXW),
    style: u32 = 0,
    lpfnWndProc: WNDPROC,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: HANDLE,
    hIcon: HANDLE = null,
    hCursor: HANDLE = null,
    hbrBackground: HANDLE = null,
    lpszMenuName: ?[*:0]const u16 = null,
    lpszClassName: [*:0]const u16,
    hIconSm: HANDLE = null,
};

extern "user32" fn RegisterClassExW(*const WNDCLASSEXW) callconv(.winapi) u16;
extern "user32" fn CreateWindowExW(u32, [*:0]const u16, [*:0]const u16, u32, i32, i32, i32, i32, HWND, HANDLE, HANDLE, ?*anyopaque) callconv(.winapi) HWND;
extern "user32" fn DefWindowProcW(HWND, u32, WPARAM, LPARAM) callconv(.winapi) LRESULT;
extern "user32" fn DestroyWindow(HWND) callconv(.winapi) BOOL;
extern "user32" fn ShowWindow(HWND, i32) callconv(.winapi) BOOL;
extern "user32" fn SetFocus(HWND) callconv(.winapi) HWND;
extern "user32" fn GetFocus() callconv(.winapi) HWND;
extern "user32" fn GetClientRect(HWND, *RECT) callconv(.winapi) BOOL;
extern "user32" fn InvalidateRect(HWND, ?*const RECT, BOOL) callconv(.winapi) BOOL;
extern "user32" fn BeginPaint(HWND, *PAINTSTRUCT) callconv(.winapi) HANDLE;
extern "user32" fn EndPaint(HWND, *const PAINTSTRUCT) callconv(.winapi) BOOL;
extern "user32" fn FillRect(HANDLE, *const RECT, HANDLE) callconv(.winapi) i32;
extern "user32" fn SetTimer(HWND, usize, u32, ?*anyopaque) callconv(.winapi) usize;
extern "user32" fn KillTimer(HWND, usize) callconv(.winapi) BOOL;
extern "user32" fn SetCapture(HWND) callconv(.winapi) HWND;
extern "user32" fn ReleaseCapture() callconv(.winapi) BOOL;
extern "user32" fn GetKeyState(i32) callconv(.winapi) i16;
extern "user32" fn SetWindowTextW(HWND, [*:0]const u16) callconv(.winapi) BOOL;
extern "user32" fn GetSysColor(i32) callconv(.winapi) u32;
extern "user32" fn GetDpiForWindow(HWND) callconv(.winapi) u32;
extern "user32" fn LoadCursorW(HANDLE, usize) callconv(.winapi) HANDLE;
extern "user32" fn MessageBoxW(HWND, [*:0]const u16, [*:0]const u16, u32) callconv(.winapi) i32;
extern "user32" fn GetWindowLongPtrW(HWND, i32) callconv(.winapi) isize;
extern "user32" fn SetWindowLongPtrW(HWND, i32, isize) callconv(.winapi) isize;
extern "user32" fn MoveWindow(HWND, i32, i32, i32, i32, BOOL) callconv(.winapi) BOOL;
extern "user32" fn OpenClipboard(HWND) callconv(.winapi) BOOL;
extern "user32" fn CloseClipboard() callconv(.winapi) BOOL;
extern "user32" fn EmptyClipboard() callconv(.winapi) BOOL;
extern "user32" fn GetClipboardData(u32) callconv(.winapi) HANDLE;
extern "user32" fn SetClipboardData(u32, HANDLE) callconv(.winapi) HANDLE;
extern "kernel32" fn GlobalAlloc(u32, usize) callconv(.winapi) HANDLE;
extern "kernel32" fn GlobalLock(HANDLE) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GlobalUnlock(HANDLE) callconv(.winapi) BOOL;
extern "kernel32" fn GlobalFree(HANDLE) callconv(.winapi) HANDLE;
extern "kernel32" fn GetModuleHandleW(?[*:0]const u16) callconv(.winapi) HANDLE;
extern "gdi32" fn CreateFontW(i32, i32, i32, i32, i32, u32, u32, u32, u32, u32, u32, u32, u32, [*:0]const u16) callconv(.winapi) HANDLE;
extern "gdi32" fn DeleteObject(HANDLE) callconv(.winapi) BOOL;
extern "gdi32" fn DeleteDC(HANDLE) callconv(.winapi) BOOL;
extern "gdi32" fn CreateSolidBrush(u32) callconv(.winapi) HANDLE;
extern "gdi32" fn CreateCompatibleDC(HANDLE) callconv(.winapi) HANDLE;
extern "gdi32" fn CreateCompatibleBitmap(HANDLE, i32, i32) callconv(.winapi) HANDLE;
extern "gdi32" fn SelectObject(HANDLE, HANDLE) callconv(.winapi) HANDLE;
extern "gdi32" fn BitBlt(HANDLE, i32, i32, i32, i32, HANDLE, i32, i32, u32) callconv(.winapi) BOOL;
extern "gdi32" fn SetTextColor(HANDLE, u32) callconv(.winapi) u32;
extern "gdi32" fn SetBkColor(HANDLE, u32) callconv(.winapi) u32;
extern "gdi32" fn ExtTextOutW(HANDLE, i32, i32, u32, ?*const RECT, ?[*]const u16, u32, ?[*]const i32) callconv(.winapi) BOOL;
extern "gdi32" fn GetTextMetricsW(HANDLE, *TEXTMETRICW) callconv(.winapi) BOOL;

const L = std.unicode.utf8ToUtf16LeStringLiteral;

const WM_NCCREATE = 0x0081;
const WM_NCDESTROY = 0x0082;
const WM_DESTROY = 0x0002;
const WM_SIZE = 0x0005;
const WM_SETFOCUS = 0x0007;
const WM_KILLFOCUS = 0x0008;
const WM_CLOSE = 0x0010;
const WM_PAINT = 0x000F;
const WM_ERASEBKGND = 0x0014;
const WM_KEYDOWN = 0x0100;
const WM_CHAR = 0x0102;
const WM_TIMER = 0x0113;
const WM_MOUSEMOVE = 0x0200;
const WM_LBUTTONDOWN = 0x0201;
const WM_LBUTTONUP = 0x0202;
const WM_MOUSEWHEEL = 0x020A;
const WM_DPICHANGED = 0x02E0;
const WS_OVERLAPPEDWINDOW = 0x00CF0000;
const SW_SHOW = 5;
const SRCCOPY = 0x00CC0020;
const ETO_OPAQUE = 0x2;
const CF_UNICODETEXT = 13;
const GMEM_MOVEABLE = 0x2;
const GWLP_USERDATA = -21;
const IDC_IBEAM = 32513;
const IDYES = 6;
const MB_YESNO = 0x4;
const MB_ICONQUESTION = 0x20;
const MB_DEFBUTTON2 = 0x100;
const VK_SHIFT = 0x10;
const VK_CONTROL = 0x11;
const VK_PRIOR = 0x21;
const VK_NEXT = 0x22;
const VK_END = 0x23;
const VK_HOME = 0x24;
const VK_LEFT = 0x25;
const VK_UP = 0x26;
const VK_RIGHT = 0x27;
const VK_DOWN = 0x28;
const VK_INSERT = 0x2D;
const VK_DELETE = 0x2E;
const COLOR_HIGHLIGHT = 13;
const COLOR_HIGHLIGHTTEXT = 14;
const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));
const timer_id = 1;
const timer_ms = 15;
const wheel_lines = 3;
const max_paste_bytes = 64 * 1024;

pub const Config = struct {
    /// Command line, for example "cmd.exe" or "powershell.exe -NoLogo".
    command: []const u8,
    /// Human name for the title, for example "Command Prompt".
    shell_name: []const u8,
    /// The lesson the terminal was opened from (title only).
    lesson_title: []const u8 = "",
    /// Starting directory; null uses the process's own.
    start_dir: ?[]const u8 = null,
    text_scale: u32 = 100,
    dark: bool = false,
};

pub const Error = error{ WindowClass, CreateWindow, OutOfMemory };

const Pos = struct { line: usize, col: u16 };

const Term = struct {
    gpa: std.mem.Allocator,
    hwnd: HWND = null,
    session: ?conpty.Session = null,
    screen: Screen,
    font: HANDLE = null,
    font_bold: HANDLE = null,
    cw: i32 = 8,
    ch: i32 = 16,
    text_scale: u32,
    dark: bool,
    shell_name: []u8,
    lesson_title: []u8,
    start_dir: []u8,
    last_title: []u8 = &.{},
    exited: bool = false,
    focused: bool = false,
    /// Top line of the view while scrolled back; null follows the live screen.
    view_top: ?usize = null,
    sel_anchor: ?Pos = null,
    sel_end: ?Pos = null,
    dragging: bool = false,
    high_surrogate: u16 = 0,
    shown_generation: u64 = 0,

    fn deinit(self: *Term) void {
        if (self.session) |*s| s.close();
        self.screen.deinit();
        if (self.font != null) _ = DeleteObject(self.font);
        if (self.font_bold != null) _ = DeleteObject(self.font_bold);
        self.gpa.free(self.shell_name);
        self.gpa.free(self.lesson_title);
        self.gpa.free(self.start_dir);
        self.gpa.free(self.last_title);
    }
};

fn termOf(hwnd: HWND) ?*Term {
    const raw: usize = @bitCast(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    return if (raw == 0) null else @ptrFromInt(raw);
}

var class_registered = false;

/// Opens a terminal window owned by `owner` (so it closes with it) and returns
/// at once; the owner's message loop drives it.
pub fn open(gpa: std.mem.Allocator, owner: HWND, cfg: Config) Error!void {
    const hinst = GetModuleHandleW(null);
    const class_name = L("WinLabTerminal");
    if (!class_registered) {
        const wc: WNDCLASSEXW = .{ .lpfnWndProc = wndProc, .hInstance = hinst, .hCursor = LoadCursorW(null, IDC_IBEAM), .lpszClassName = class_name };
        if (RegisterClassExW(&wc) == 0) return error.WindowClass;
        class_registered = true;
    }

    const t = try gpa.create(Term);
    errdefer gpa.destroy(t);
    t.* = .{
        .gpa = gpa,
        .screen = try Screen.init(gpa, 100, 30),
        .text_scale = cfg.text_scale,
        .dark = cfg.dark,
        .shell_name = try gpa.dupe(u8, cfg.shell_name),
        .lesson_title = try gpa.dupe(u8, cfg.lesson_title),
        .start_dir = try gpa.dupe(u8, cfg.start_dir orelse ""),
    };
    errdefer t.deinit();

    const hwnd = CreateWindowExW(0, class_name, L("WinLab Terminal"), WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 1000, 640, owner, null, hinst, t) orelse return error.CreateWindow;
    t.hwnd = hwnd;
    makeFonts(t);

    var rc: RECT = .{};
    _ = GetClientRect(hwnd, &rc);
    const cols: u16 = @intCast(std.math.clamp(@divTrunc(rc.right, t.cw), 20, 500));
    const rows: u16 = @intCast(std.math.clamp(@divTrunc(rc.bottom, t.ch), 5, 500));
    t.screen.resize(cols, rows) catch {};
    t.session = conpty.Session.start(gpa, cfg.command, cfg.start_dir, cols, rows) catch {
        _ = MessageBoxW(owner, L("The shell could not be started."), L("WinLab Terminal"), 0x10);
        _ = DestroyWindow(hwnd); // WM_NCDESTROY frees `t`
        return;
    };
    _ = SetTimer(hwnd, timer_id, timer_ms, null);
    updateTitle(t);
    _ = ShowWindow(hwnd, SW_SHOW);
    _ = SetFocus(hwnd);
}

fn makeFonts(t: *Term) void {
    const dpi: i32 = @intCast(@max(GetDpiForWindow(t.hwnd), 96));
    const px: i32 = -@divTrunc(10 * dpi * @as(i32, @intCast(t.text_scale)), 72 * 100);
    if (t.font != null) _ = DeleteObject(t.font);
    if (t.font_bold != null) _ = DeleteObject(t.font_bold);
    t.font = CreateFontW(px, 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0x31, L("Consolas")); // FIXED_PITCH | FF_MODERN
    t.font_bold = CreateFontW(px, 0, 0, 0, 700, 0, 0, 0, 1, 0, 0, 5, 0x31, L("Consolas"));
    const dc = BeginMeasure(t.hwnd);
    defer EndMeasure(t.hwnd, dc);
    const old = SelectObject(dc, t.font);
    var tm: TEXTMETRICW = undefined;
    if (GetTextMetricsW(dc, &tm) != 0) {
        t.cw = @max(tm.tmAveCharWidth, 1);
        t.ch = @max(tm.tmHeight + tm.tmExternalLeading, 1);
    }
    _ = SelectObject(dc, old);
}

extern "user32" fn GetDC(HWND) callconv(.winapi) HANDLE;
extern "user32" fn ReleaseDC(HWND, HANDLE) callconv(.winapi) i32;
fn BeginMeasure(hwnd: HWND) HANDLE {
    return GetDC(hwnd);
}
fn EndMeasure(hwnd: HWND, dc: HANDLE) void {
    _ = ReleaseDC(hwnd, dc);
}

fn rgb(c: u32) u32 {
    // 0xRRGGBB -> COLORREF 0x00BBGGRR
    return ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF);
}

fn defaultColors(t: *const Term) struct { fg: u32, bg: u32 } {
    // Always dark, whatever the app theme: shells (PSReadLine, ls colours, ...) pick colours
    // that assume a dark console, and light-on-white makes some of them unreadable.
    _ = t;
    return .{ .fg = 0x00CCCCCC, .bg = 0x000C0C0C };
}

fn topLine(t: *const Term) usize {
    const total = t.screen.totalLines();
    const live = total - t.screen.rows;
    return if (t.view_top) |v| @min(v, live) else live;
}

fn scrollView(t: *Term, delta: isize) void {
    const live: isize = @intCast(t.screen.totalLines() - t.screen.rows);
    const cur: isize = @intCast(topLine(t));
    const next = std.math.clamp(cur + delta, 0, live);
    t.view_top = if (next >= live) null else @intCast(next);
    _ = InvalidateRect(t.hwnd, null, 0);
}

fn selectionOrdered(t: *const Term) ?struct { a: Pos, b: Pos } {
    const a = t.sel_anchor orelse return null;
    const b = t.sel_end orelse return null;
    if (a.line == b.line and a.col == b.col) return null;
    const a_first = a.line < b.line or (a.line == b.line and a.col <= b.col);
    return if (a_first) .{ .a = a, .b = b } else .{ .a = b, .b = a };
}

fn isSelected(sel: anytype, line: usize, col: u16) bool {
    if (line < sel.a.line or line > sel.b.line) return false;
    if (line == sel.a.line and col < sel.a.col) return false;
    if (line == sel.b.line and col > sel.b.col) return false;
    return true;
}

fn paint(t: *Term, hdc: HANDLE, rc: RECT) void {
    const w = rc.right - rc.left;
    const h = rc.bottom - rc.top;
    if (w <= 0 or h <= 0) return;
    const mem = CreateCompatibleDC(hdc);
    defer _ = DeleteDC(mem);
    const bmp = CreateCompatibleBitmap(hdc, w, h);
    defer _ = DeleteObject(bmp);
    const old_bmp = SelectObject(mem, bmp);
    defer _ = SelectObject(mem, old_bmp);

    const dc = defaultColors(t);
    const bg_brush = CreateSolidBrush(dc.bg);
    defer _ = DeleteObject(bg_brush);
    const full: RECT = .{ .left = 0, .top = 0, .right = w, .bottom = h };
    _ = FillRect(mem, &full, bg_brush);

    const old_font = SelectObject(mem, t.font);
    defer _ = SelectObject(mem, old_font);
    const sel = selectionOrdered(t);
    const top = topLine(t);
    const at_live = t.view_top == null;
    const hl_bg = GetSysColor(COLOR_HIGHLIGHT);
    const hl_fg = GetSysColor(COLOR_HIGHLIGHTTEXT);

    var text: [512]u16 = undefined;
    var row: u16 = 0;
    while (row < t.screen.rows) : (row += 1) {
        const li = top + row;
        if (li >= t.screen.totalLines()) break;
        const cells = t.screen.line(li);
        const y = @as(i32, row) * t.ch;
        var x: u16 = 0;
        const limit: u16 = @intCast(@min(cells.len, t.screen.cols));
        while (x < limit) {
            const run_start = x;
            const first = cells[x];
            const colors = cellColors(t, first, sel != null and isSelected(sel.?, li, x), at_live and li == top + t.screen.cy and x == t.screen.cx, dc, hl_fg, hl_bg);
            var n: usize = 0;
            while (x < limit and n < text.len - 2) {
                const c = cells[x];
                const cc = cellColors(t, c, sel != null and isSelected(sel.?, li, x), at_live and li == top + t.screen.cy and x == t.screen.cx, dc, hl_fg, hl_bg);
                if (cc.fg != colors.fg or cc.bg != colors.bg or c.attr.bold != first.attr.bold) break;
                // One UTF-16 unit per cell keeps the monospace grid aligned; wider characters are replaced.
                text[n] = if (c.ch < 0x10000) @intCast(c.ch) else 0xFFFD;
                n += 1;
                x += 1;
            }
            _ = SelectObject(mem, if (first.attr.bold) t.font_bold else t.font);
            _ = SetTextColor(mem, colors.fg);
            _ = SetBkColor(mem, colors.bg);
            const run: RECT = .{ .left = @as(i32, run_start) * t.cw, .top = y, .right = @as(i32, x) * t.cw, .bottom = y + t.ch };
            _ = ExtTextOutW(mem, run.left, y, ETO_OPAQUE, &run, &text, @intCast(n), null);
            if (first.attr.underline) {
                const ul: RECT = .{ .left = run.left, .top = y + t.ch - 2, .right = run.right, .bottom = y + t.ch - 1 };
                const b = CreateSolidBrush(colors.fg);
                _ = FillRect(mem, &ul, b);
                _ = DeleteObject(b);
            }
        }
    }
    _ = BitBlt(hdc, rc.left, rc.top, w, h, mem, 0, 0, SRCCOPY);
}

fn cellColors(t: *const Term, c: Cell, selected: bool, is_cursor: bool, dc: anytype, hl_fg: u32, hl_bg: u32) struct { fg: u32, bg: u32 } {
    var fg: u32 = if (c.fg == default_color) dc.fg else rgb(c.fg);
    var bg: u32 = if (c.bg == default_color) dc.bg else rgb(c.bg);
    if (c.attr.reverse) std.mem.swap(u32, &fg, &bg);
    if (selected) return .{ .fg = hl_fg, .bg = hl_bg };
    if (is_cursor and t.screen.cursor_visible and t.focused and !t.exited) std.mem.swap(u32, &fg, &bg);
    return .{ .fg = fg, .bg = bg };
}

// ---- clipboard -------------------------------------------------------------

fn copyToClipboard(t: *Term, utf8: []const u8) void {
    const w = std.unicode.utf8ToUtf16LeAllocZ(t.gpa, utf8) catch return;
    defer t.gpa.free(w);
    const bytes = (w.len + 1) * 2;
    const mem = GlobalAlloc(GMEM_MOVEABLE, bytes) orelse return;
    const p = GlobalLock(mem) orelse {
        _ = GlobalFree(mem);
        return;
    };
    @memcpy(@as([*]u8, @ptrCast(p))[0..bytes], std.mem.sliceAsBytes(w.ptr[0 .. w.len + 1]));
    _ = GlobalUnlock(mem);
    if (OpenClipboard(t.hwnd) == 0) {
        _ = GlobalFree(mem);
        return;
    }
    defer _ = CloseClipboard();
    _ = EmptyClipboard();
    if (SetClipboardData(CF_UNICODETEXT, mem) == null) _ = GlobalFree(mem); // on success the clipboard owns it
}

/// Text of the selection (or, with `all`, the whole buffer), lines joined with CRLF.
fn extractText(t: *Term, all: bool) ?[]u8 {
    var out: std.ArrayList(u8) = .empty;
    const total = t.screen.totalLines();
    var first: usize = 0;
    var last: usize = total - 1;
    var first_col: u16 = 0;
    var last_col: u16 = std.math.maxInt(u16);
    if (!all) {
        const sel = selectionOrdered(t) orelse return null;
        first = sel.a.line;
        last = @min(sel.b.line, total - 1);
        first_col = sel.a.col;
        last_col = sel.b.col;
    }
    var li = first;
    while (li <= last) : (li += 1) {
        const cells = t.screen.line(li);
        const from: usize = if (li == first) @min(first_col, cells.len) else 0;
        var to: usize = if (li == last) @min(@as(usize, last_col) + 1, cells.len) else cells.len;
        while (to > from and cells[to - 1].ch == ' ') to -= 1;
        for (cells[from..to]) |c| {
            var b: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(c.ch, &b) catch continue;
            out.appendSlice(t.gpa, b[0..n]) catch {
                out.deinit(t.gpa);
                return null;
            };
        }
        if (li != last) out.appendSlice(t.gpa, "\r\n") catch {
            out.deinit(t.gpa);
            return null;
        };
    }
    return out.toOwnedSlice(t.gpa) catch null;
}

fn copySelection(t: *Term, all: bool) bool {
    const text = extractText(t, all) orelse return false;
    defer t.gpa.free(text);
    copyToClipboard(t, text);
    return true;
}

fn paste(t: *Term) void {
    const s = &(t.session orelse return);
    if (t.exited) return;
    if (OpenClipboard(t.hwnd) == 0) return;
    defer _ = CloseClipboard();
    const mem = GetClipboardData(CF_UNICODETEXT) orelse return;
    const p = GlobalLock(mem) orelse return;
    defer _ = GlobalUnlock(mem);
    const units: [*:0]const u16 = @ptrCast(@alignCast(p));
    const utf8 = std.unicode.utf16LeToUtf8Alloc(t.gpa, std.mem.span(units)) catch return;
    defer t.gpa.free(utf8);
    if (utf8.len > max_paste_bytes) {
        _ = MessageBoxW(t.hwnd, L("That text is too large to paste into the terminal."), L("WinLab Terminal"), 0x30);
        return;
    }
    // Strip control characters (notably ESC) that could drive the shell in unintended ways;
    // keep tab and line breaks, and turn line breaks into Enter.
    var clean: std.ArrayList(u8) = .empty;
    defer clean.deinit(t.gpa);
    var lines: usize = 1;
    var i: usize = 0;
    while (i < utf8.len) : (i += 1) {
        const c = utf8[i];
        if (c == '\r') {
            if (i + 1 < utf8.len and utf8[i + 1] == '\n') i += 1;
            clean.append(t.gpa, '\r') catch return;
            lines += 1;
        } else if (c == '\n') {
            clean.append(t.gpa, '\r') catch return;
            lines += 1;
        } else if (c == '\t' or c >= 0x20 and c != 0x7F) {
            clean.append(t.gpa, c) catch return;
        }
    }
    if (lines > 1) {
        // Every line would run immediately, so ask first (default No).
        var msg_buf: [160]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "This text has {d} lines. Each line will be sent to the shell and run. Paste it?", .{lines}) catch return;
        const msg16 = std.unicode.utf8ToUtf16LeAllocZ(t.gpa, msg) catch return;
        defer t.gpa.free(msg16);
        if (MessageBoxW(t.hwnd, msg16, L("WinLab Terminal"), MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2) != IDYES) return;
    }
    s.write(clean.items) catch {};
    t.view_top = null;
}

// ---- title and pumping -----------------------------------------------------

fn updateTitle(t: *Term) void {
    var buf: [768]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    w.print("WinLab Terminal - {s} (on this computer, as the current user)", .{t.shell_name}) catch {};
    if (t.lesson_title.len > 0) w.print(" - lesson: {s}", .{t.lesson_title}) catch {};
    const cwd = t.screen.cwd();
    if (cwd.len > 0) {
        w.print(" - {s}", .{cwd}) catch {};
    } else if (t.start_dir.len > 0) {
        w.print(" - started in {s}", .{t.start_dir}) catch {};
    }
    if (t.exited) {
        if (t.session) |*s| {
            if (s.exitCode()) |code| w.print(" - exited with code {d}", .{code}) catch {};
        }
    }
    const text = w.buffered();
    if (std.mem.eql(u8, text, t.last_title)) return;
    const copy = t.gpa.dupe(u8, text) catch return;
    t.gpa.free(t.last_title);
    t.last_title = copy;
    // Shell-supplied text is untrusted: drop control characters before showing it.
    for (copy) |*c| {
        if (c.* < 0x20) c.* = '?';
    }
    const w16 = std.unicode.utf8ToUtf16LeAllocZ(t.gpa, copy) catch return;
    defer t.gpa.free(w16);
    _ = SetWindowTextW(t.hwnd, w16);
}

fn pump(t: *Term) void {
    const s = &(t.session orelse return);
    var buf: [8192]u8 = undefined;
    var fed = false;
    var rounds: usize = 0;
    while (rounds < 16) : (rounds += 1) {
        const n = s.read(&buf);
        if (n == 0) break;
        t.screen.feed(buf[0..n]) catch break;
        fed = true;
    }
    if (fed) {
        if (t.screen.takeReplies()) |r| {
            defer t.gpa.free(r);
            if (r.len > 0 and !t.exited) s.write(r) catch {};
        } else |_| {}
    }
    if (!t.exited and !fed) {
        if (s.exitCode()) |code| {
            t.exited = true;
            var msg: [96]u8 = undefined;
            const text = std.fmt.bufPrint(&msg, "\r\n[Process exited with code {d}. Close this window when you are done.]\r\n", .{code}) catch "";
            t.screen.feed(text) catch {};
            fed = true;
        }
    }
    if (fed or t.screen.generation != t.shown_generation) {
        t.shown_generation = t.screen.generation;
        updateTitle(t);
        _ = InvalidateRect(t.hwnd, null, 0);
    }
}

// ---- input -----------------------------------------------------------------

fn sendKey(t: *Term, bytes: []const u8) void {
    const s = &(t.session orelse return);
    if (t.exited) return;
    t.view_top = null;
    t.sel_anchor = null;
    t.sel_end = null;
    s.write(bytes) catch {};
}

fn hit(t: *const Term, lparam: LPARAM) Pos {
    const l: usize = @bitCast(lparam);
    const x: i32 = @as(i16, @bitCast(@as(u16, @truncate(l & 0xFFFF))));
    const y: i32 = @as(i16, @bitCast(@as(u16, @truncate((l >> 16) & 0xFFFF))));
    const col: u16 = @intCast(std.math.clamp(@divTrunc(@max(x, 0), t.cw), 0, @as(i32, t.screen.cols) - 1));
    const row: usize = @intCast(std.math.clamp(@divTrunc(@max(y, 0), t.ch), 0, @as(i32, t.screen.rows) - 1));
    return .{ .line = topLine(t) + row, .col = col };
}

fn onKeyDown(t: *Term, vk: usize) bool {
    const shift = GetKeyState(VK_SHIFT) < 0;
    switch (vk) {
        VK_UP => sendKey(t, "\x1b[A"),
        VK_DOWN => sendKey(t, "\x1b[B"),
        VK_RIGHT => sendKey(t, "\x1b[C"),
        VK_LEFT => sendKey(t, "\x1b[D"),
        VK_HOME => sendKey(t, "\x1b[H"),
        VK_END => sendKey(t, "\x1b[F"),
        VK_INSERT => sendKey(t, "\x1b[2~"),
        VK_DELETE => sendKey(t, "\x1b[3~"),
        VK_PRIOR => if (shift) scrollView(t, -@as(isize, t.screen.rows) + 1) else sendKey(t, "\x1b[5~"),
        VK_NEXT => if (shift) scrollView(t, @as(isize, t.screen.rows) - 1) else sendKey(t, "\x1b[6~"),
        else => return false,
    }
    return true;
}

fn onChar(t: *Term, unit: u16) void {
    switch (unit) {
        0x16 => return paste(t), // Ctrl+V, Ctrl+Shift+V
        0x03 => if (selectionOrdered(t) != null) { // Ctrl+C copies when something is selected, else interrupts
            _ = copySelection(t, false);
            t.sel_anchor = null;
            t.sel_end = null;
            _ = InvalidateRect(t.hwnd, null, 0);
            return;
        },
        0x01 => if (GetKeyState(VK_SHIFT) < 0 and GetKeyState(VK_CONTROL) < 0) { // Ctrl+Shift+A: copy everything
            _ = copySelection(t, true);
            return;
        },
        else => {},
    }
    var utf16: [2]u16 = undefined;
    var n: usize = 0;
    if (unit >= 0xD800 and unit < 0xDC00) {
        t.high_surrogate = unit;
        return;
    } else if (unit >= 0xDC00 and unit < 0xE000) {
        if (t.high_surrogate == 0) return;
        utf16 = .{ t.high_surrogate, unit };
        t.high_surrogate = 0;
        n = 2;
    } else {
        utf16[0] = unit;
        n = 1;
    }
    if (n == 1 and unit == 0x08) return sendKey(t, "\x7f"); // Backspace
    var out: [8]u8 = undefined;
    const len = std.unicode.utf16LeToUtf8(&out, utf16[0..n]) catch return;
    sendKey(t, out[0..len]);
}

fn relayout(t: *Term) void {
    var rc: RECT = .{};
    _ = GetClientRect(t.hwnd, &rc);
    const cols: u16 = @intCast(std.math.clamp(@divTrunc(rc.right, t.cw), 1, 500));
    const rows: u16 = @intCast(std.math.clamp(@divTrunc(rc.bottom, t.ch), 1, 500));
    if (cols == t.screen.cols and rows == t.screen.rows) return;
    t.screen.resize(cols, rows) catch return;
    if (t.session) |*s| s.resize(cols, rows);
    _ = InvalidateRect(t.hwnd, null, 0);
}

fn wndProc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT {
    if (msg == WM_NCCREATE) {
        // lpCreateParams is the first field of CREATESTRUCTW.
        const params: *const usize = @ptrFromInt(@as(usize, @bitCast(lparam)));
        _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, @bitCast(params.*));
        return DefWindowProcW(hwnd, msg, wparam, lparam);
    }
    const t = termOf(hwnd) orelse return DefWindowProcW(hwnd, msg, wparam, lparam);
    switch (msg) {
        WM_ERASEBKGND => return 1,
        WM_PAINT => {
            var ps: PAINTSTRUCT = undefined;
            const hdc = BeginPaint(hwnd, &ps);
            var rc: RECT = .{};
            _ = GetClientRect(hwnd, &rc);
            paint(t, hdc, rc);
            _ = EndPaint(hwnd, &ps);
            return 0;
        },
        WM_SIZE => {
            if (t.font != null) relayout(t);
            return 0;
        },
        WM_TIMER => {
            pump(t);
            return 0;
        },
        WM_SETFOCUS => {
            t.focused = true;
            _ = InvalidateRect(hwnd, null, 0);
            return 0;
        },
        WM_KILLFOCUS => {
            t.focused = false;
            _ = InvalidateRect(hwnd, null, 0);
            return 0;
        },
        WM_KEYDOWN => {
            if (onKeyDown(t, wparam)) return 0;
            return DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        WM_CHAR => {
            onChar(t, @truncate(wparam));
            return 0;
        },
        WM_LBUTTONDOWN => {
            _ = SetFocus(hwnd);
            _ = SetCapture(hwnd);
            t.dragging = true;
            t.sel_anchor = hit(t, lparam);
            t.sel_end = t.sel_anchor;
            _ = InvalidateRect(hwnd, null, 0);
            return 0;
        },
        WM_MOUSEMOVE => {
            if (t.dragging) {
                t.sel_end = hit(t, lparam);
                _ = InvalidateRect(hwnd, null, 0);
            }
            return 0;
        },
        WM_LBUTTONUP => {
            if (t.dragging) {
                t.dragging = false;
                _ = ReleaseCapture();
                t.sel_end = hit(t, lparam);
                if (selectionOrdered(t) == null) {
                    t.sel_anchor = null;
                    t.sel_end = null;
                }
                _ = InvalidateRect(hwnd, null, 0);
            }
            return 0;
        },
        WM_MOUSEWHEEL => {
            const delta: i16 = @bitCast(@as(u16, @truncate(wparam >> 16)));
            scrollView(t, -@as(isize, @divTrunc(delta, 120)) * wheel_lines);
            return 0;
        },
        WM_DPICHANGED => {
            const r: *const RECT = @ptrFromInt(@as(usize, @bitCast(lparam)));
            _ = MoveWindow(hwnd, r.left, r.top, r.right - r.left, r.bottom - r.top, 1);
            makeFonts(t);
            relayout(t);
            return 0;
        },
        WM_CLOSE => {
            if (t.session != null and !t.exited) {
                if (MessageBoxW(hwnd, L("Closing this window ends the shell session. Close it?"), L("WinLab Terminal"), MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2) != IDYES) return 0;
            }
            _ = DestroyWindow(hwnd);
            return 0;
        },
        WM_DESTROY => {
            _ = KillTimer(hwnd, timer_id);
            if (standalone) PostQuitMessage(0);
            return 0;
        },
        WM_NCDESTROY => {
            _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
            const gpa = t.gpa;
            t.deinit();
            gpa.destroy(t);
            return DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        else => return DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

extern "user32" fn GetMessageW(*MSG, HWND, u32, u32) callconv(.winapi) BOOL;
extern "user32" fn TranslateMessage(*const MSG) callconv(.winapi) BOOL;
extern "user32" fn DispatchMessageW(*const MSG) callconv(.winapi) LRESULT;
extern "user32" fn PostQuitMessage(i32) callconv(.winapi) void;
const POINT = extern struct { x: i32, y: i32 };
const MSG = extern struct { hwnd: HWND, message: u32, wParam: WPARAM, lParam: LPARAM, time: u32, pt: POINT };

/// Opens one terminal as the only window and runs until it closes
/// (`winlab terminal <shell>`).
pub fn runStandalone(gpa: std.mem.Allocator, cfg: Config) Error!void {
    standalone = true;
    try open(gpa, null, cfg);
    var msg: MSG = undefined;
    while (GetMessageW(&msg, null, 0, 0) > 0) {
        _ = TranslateMessage(&msg);
        _ = DispatchMessageW(&msg);
    }
}

var standalone = false;
