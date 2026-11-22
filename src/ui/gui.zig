//! The WinLab window, drawn with DVUI on its Direct3D 11 backend (decision record 0002).
//!
//! One window: a lesson list with search beside the reader, a notes box and progress buttons
//! under it, a Practice menu that opens real shells (the separate native terminal window) and
//! lab scenarios (a floating panel; each step runs on a worker thread, so the window never
//! freezes). Lesson text is rendered by `md_view.zig` straight from the Markdown tree.
//!
//! Everything here runs on the UI thread except `labWorker`, which only calls the `LabEngine`
//! and then wakes the loop.
const std = @import("std");
const winlab = @import("winlab");
const dvui = @import("dvui");
const Dx11 = @import("dx11-backend");
const win32 = Dx11.win32;
const md_view = @import("md_view.zig");
const terminal_win = @import("terminal_win.zig");

// ---------------------------------------------------------------------------------------------
// Types shared with main.zig
// ---------------------------------------------------------------------------------------------

/// One selectable lesson. All memory is borrowed and must outlive `run`.
pub const Page = struct {
    /// Stable lesson id (key for progress); empty for ad-hoc files.
    id: []const u8 = "",
    title: []const u8,
    /// Searched along with the title; may be empty.
    summary: []const u8 = "",
    /// Raw Markdown, searched too.
    body: []const u8 = "",
    root: *winlab.md.Node,
    /// The parsed document, for the plain-text view and "copy as text". Null when not kept.
    doc: ?*const winlab.md.Document = null,
    /// Difficulty 1 to 5 (0 unknown) and estimated minutes, shown in the header and the list.
    level: u8 = 0,
    minutes: u32 = 0,
    /// Lesson ids this lesson recommends first. Advice, never a gate.
    prerequisites: []const []const u8 = &.{},
};

/// One stage of a learning path: lessons as indices into the page list.
pub const PathStage = struct {
    title: []const u8,
    entry_hint: []const u8 = "",
    pages: []const usize,
    /// Worth doing on this path but not needed to finish it.
    optional: []const usize = &.{},
    /// Lab ids that practise this stage (looked up in `Options.labs`).
    labs: []const []const u8 = &.{},
};

/// A learning path for the window (docs/learning-paths.md). Memory is borrowed like `Page`.
pub const PathView = struct {
    id: []const u8,
    title: []const u8,
    goal: []const u8,
    audience: []const u8 = "",
    stages: []const PathStage,
    minutes: u32 = 0,
    level_min: u8 = 0,
    level_max: u8 = 0,
};

/// Progress tracking hooks. `save` persists `progress` and returns false on failure.
pub const Tracking = struct {
    progress: *winlab.progress.Progress,
    save_ctx: ?*anyopaque,
    save: *const fn (ctx: ?*anyopaque, p: *const winlab.progress.Progress) bool,
};

/// One line of the setup window: something WinLab or the labs use, and whether it was found.
pub const SetupItem = struct {
    name: []const u8,
    ok: bool,
    /// Missing is fine (the lessons still work); the line says what it would unlock.
    optional: bool,
    detail: []const u8,
};
pub const setup_max_items = 10;

/// Implemented by main.zig. `check` fills `out` and returns how many lines it wrote; the strings stay valid
/// until the next call. `finish` records that the setup window has been seen (so it does not open by itself again).
pub const Setup = struct {
    ctx: *anyopaque,
    check: *const fn (ctx: *anyopaque, out: *[setup_max_items]SetupItem) usize,
    finish: *const fn (ctx: *anyopaque) void,
    /// Open the window at start (first run).
    show_first: bool = false,
    /// Where the settings file lives, shown so a learner can set qemu-path by hand.
    settings_path: []const u8 = "",
};

pub const qemu_winget_command = "winget install --id SoftwareFreedomConservancy.QEMU --exact";
pub const qemu_download_url = "https://www.qemu.org/download/#windows";

/// A shell the learner can open from a lesson.
pub const ShellChoice = struct {
    /// Menu and title text, for example "Command Prompt".
    name: []const u8,
    /// Command line, for example "cmd.exe" or "powershell.exe -NoLogo".
    command: []const u8,
};

pub const Op = enum { start, check, reset, end };

/// What one lab step reported. Fixed buffer: it crosses a thread boundary without allocation.
pub const Outcome = struct {
    ok: bool,
    /// For `check`: the machine is in the expected state.
    passed: bool = false,
    message: [240]u8 = undefined,
    len: usize = 0,

    pub fn make(ok: bool, passed: bool, msg: []const u8) Outcome {
        var o: Outcome = .{ .ok = ok, .passed = passed };
        o.len = @min(msg.len, o.message.len);
        @memcpy(o.message[0..o.len], msg[0..o.len]);
        return o;
    }
    pub fn text(self: *const Outcome) []const u8 {
        return self.message[0..self.len];
    }
};

/// Implemented by main.zig. `run` blocks and is called on a worker thread; `fixed` is called on the
/// UI thread after a passing check (to record it in the learner's progress).
pub const LabEngine = struct {
    ctx: *anyopaque,
    run: *const fn (ctx: *anyopaque, lab_index: usize, op: Op) Outcome,
    fixed: *const fn (ctx: *anyopaque, lab_index: usize) void,
};

pub const Lab = struct {
    /// Id of the lesson this lab belongs to.
    lesson: []const u8,
    id: []const u8,
    title: []const u8,
    symptom: []const u8,
    hints: []const []const u8,
    /// A scripting lab: the text is a task, and the learner writes a script at `script_path`.
    task: bool = false,
    script_path: []const u8 = "",
};

pub const Options = struct {
    io: std.Io,
    /// Labs offered by the Practice menu (each belongs to a lesson).
    labs: []const Lab = &.{},
    lab_engine: ?LabEngine = null,
    /// Quizzes (one per lesson at most); each attempt draws a subset of its bank.
    quizzes: []const winlab.quiz.Quiz = &.{},
    /// Learning paths (goal-based lesson lists); empty hides the path picker.
    paths: []const PathView = &.{},
    /// If set and no lab can run, shown when a lab is requested (for example "no training VM registered").
    lab_note: []const u8 = "",
    /// Shells offered by the Practice menu; empty hides the entry.
    shells: []const ShellChoice = &.{},
    /// Directory new shells start in (for example the user profile).
    start_dir: ?[]const u8 = null,
    /// Percent, 100..300 (validated by settings).
    text_scale: u32 = 100,
    /// When set, the window shows lesson status, a progress summary and a notes box.
    tracking: ?Tracking = null,
    /// First-run setup and requirements window; null hides it.
    setup: ?Setup = null,
    dark: bool = false,
    /// Where Segoe UI and Consolas live (`%SystemRoot%\Fonts`). Empty: DVUI's bundled font.
    fonts_dir: []const u8 = "",
};

/// True when `theme` resolves to dark. `.system` follows the user's app-mode setting.
pub fn isDark(theme: winlab.settings.Theme) bool {
    return switch (theme) {
        .light => false,
        .dark => true,
        .system => (Dx11.preferredColorScheme(undefined) orelse .light) == .dark,
    };
}

// ---------------------------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------------------------

const search_max = 200;
const class_name = win32.L("WinLabWindow");
const reader_width: f32 = 820;
const debug_waits = false;

const LabUi = struct {
    open: bool = false,
    index: usize = 0,
    hints_shown: usize = 0,
    running: bool = false,
    busy: std.atomic.Value(bool) = .init(false),
    done: std.atomic.Value(bool) = .init(false),
    /// Worker -> UI: valid once `done` is set.
    op: Op = .start,
    outcome: Outcome = Outcome.make(false, false, ""),
    status: [200]u8 = undefined,
    status_len: usize = 0,
    log: std.ArrayList(u8) = .empty,
    scroll: dvui.ScrollInfo = .{},
    scroll_to_end: bool = false,
    /// The learner asked to close while the VM runs; ask whether to stop it.
    confirm_close: bool = false,
    close_after: bool = false,
    /// The close request was for the lab panel only, not the whole app.
    close_lab_only: bool = false,
};

const App = struct {
    gpa: std.mem.Allocator,
    win: *dvui.Window,
    hwnd: ?win32.HWND,
    o: Options,
    pages: []const Page,
    docs: []winlab.search.Doc,
    fonts: []const dvui.Font.Source,
    dark: bool,

    current: usize = 0,
    /// Show the lesson as one block of plain text, so a selection can span paragraphs.
    text_view: bool = false,
    plain: ?[]u8 = null,
    plain_page: usize = std.math.maxInt(usize),
    visible: std.ArrayList(usize) = .empty,
    search_buf: [search_max + 1]u8 = @splat(0),
    last_query: [search_max + 1]u8 = @splat(0),
    focus_search: bool = false,
    /// Row to move keyboard focus to on the next frame (after Up/Down in the list).
    focus_row: ?usize = null,

    reader_scroll: dvui.ScrollInfo = .{},
    view: md_view.View = .{},

    notes_buf: [winlab.progress.max_notes_bytes + 1]u8 = @splat(0),
    notes_for: usize = std.math.maxInt(usize),
    notes_focused: bool = false,

    pending_url: ?[]const u8 = null,
    show_about: bool = false,
    show_keys: bool = false,
    quit: bool = false,
    split: f32 = 0.27,
    notes_split: f32 = 0.8,
    groups: [max_groups]GroupInfo = undefined,
    group_count: usize = 0,
    collapsed: [max_groups]bool = @splat(false),
    /// The learning path being followed (index into `o.paths`); null shows all lessons by area.
    path: ?usize = null,
    show_picker: bool = false,
    show_setup: bool = false,
    setup_items: [setup_max_items]SetupItem = undefined,
    setup_n: usize = 0,
    lab: LabUi = .{},
    qz: QuizUi = .{},
    /// Frame-local message for a modal that needs only text.
    info: ?[]const u8 = null,
};

var app_storage: App = undefined;

// ---------------------------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------------------------

pub const Error = error{ WindowClass, OutOfMemory } || dvui.Backend.GenericError || std.Io.File.OpenError;

/// Shows `pages` and runs the message loop until the window closes.
pub fn run(gpa: std.mem.Allocator, title: [:0]const u8, pages: []const Page, o: Options) !void {
    std.debug.assert(pages.len > 0);
    dvui.io = o.io;
    freeOwnConsole();

    var fonts: std.ArrayList(dvui.Font.Source) = .empty;
    defer fonts.deinit(gpa);
    loadWindowsFonts(gpa, o, &fonts);

    Dx11.RegisterClass(class_name, .{}) catch return error.WindowClass;
    var window_state: Dx11.WindowState = undefined;
    const backend = try Dx11.initWindow(&window_state, .{
        .registered_class = class_name,
        .dvui_gpa = gpa,
        .allocator = gpa,
        .size = .{ .w = 1280, .h = 820 },
        .min_size = .{ .w = 640, .h = 420 },
        .vsync = true,
        .title = title,
        .dvui_window_init_options = .{
            .theme = makeTheme(o.dark, fonts.items),
            // Ctrl+= / Ctrl+- / Ctrl+0 scale the whole UI.
            .keybinds_zoom = true,
        },
    });
    defer backend.deinit();
    const win = backend.getWindow();
    win.content_scale = @as(f32, @floatFromInt(o.text_scale)) / 100.0;

    const docs = try gpa.alloc(winlab.search.Doc, pages.len);
    defer gpa.free(docs);
    for (pages, docs) |p, *d| d.* = .{ .title = p.title, .summary = p.summary, .body = p.body };

    const a = &app_storage;
    a.* = .{ .gpa = gpa, .win = win, .hwnd = Dx11.hwndFromContext(backend), .o = o, .pages = pages, .docs = docs, .fonts = fonts.items, .dark = o.dark };
    defer a.visible.deinit(gpa);
    defer if (a.plain) |p| gpa.free(p);
    defer a.lab.log.deinit(gpa);
    buildGroups(a);
    rebuildList(a);
    // Open on the first lesson in the list, not the first in directory order.
    if (a.visible.items.len > 0) a.current = a.visible.items[0];
    loadNotes(a);
    restorePath(a);
    if (o.setup) |s| {
        runSetupCheck(a);
        if (s.show_first) a.show_setup = true;
    }

    while (!a.quit) switch (Dx11.serviceMessageQueue()) {
        .queue_empty => {
            const nstime = win.beginWait(backend.hasEvent());
            try win.begin(nstime);

            frame(a);

            // Window close button. A lab step in flight, or a running lab VM, needs an answer first.
            for (dvui.events()) |*e| {
                if (!dvui.eventMatchSimple(e, win.data())) continue;
                if ((e.evt == .window and e.evt.window.action == .close) or (e.evt == .app and e.evt.app.action == .quit)) {
                    e.handle(@src(), win.data());
                    requestQuit(a);
                }
            }

            const end_micros = try win.end(.{});
            backend.setCursor(win.cursorRequested());

            // Sleep until an event arrives or DVUI needs another frame, instead of redrawing at vsync forever.
            const wait = win.waitTime(end_micros);
            if (debug_waits) std.debug.print("wait {?d} -> {d} win {d}x{d} px {d}x{d}\n", .{ end_micros, wait, win.data().rect.w, win.data().rect.h, backend.pixelSize().w, backend.pixelSize().h });
            if (wait > 0) {
                const ms: u32 = if (wait == std.math.maxInt(u32)) win32.INFINITE else @max(1, wait / 1000);
                _ = win32.MsgWaitForMultipleObjects(0, null, win32.FALSE, ms, win32.QS_ALLINPUT);
            }
        },
        .quit => break,
    };
    commitNotes(a);
}

/// Started by double-click, the console window would sit behind the GUI; drop it when we own it.
fn freeOwnConsole() void {
    var pids: [2]u32 = undefined;
    if (win32.GetConsoleProcessList(&pids, pids.len) == 1) _ = win32.FreeConsole();
}

fn requestQuit(a: *App) void {
    if (a.lab.busy.load(.acquire)) {
        a.info = "A lab step is still running. Wait for it to finish, then close WinLab.";
        return;
    }
    if (a.lab.running) {
        a.lab.confirm_close = true;
        a.lab.close_after = false;
        return;
    }
    a.quit = true;
}

// ---------------------------------------------------------------------------------------------
// Theme and fonts
// ---------------------------------------------------------------------------------------------

fn readFont(gpa: std.mem.Allocator, o: Options, file: []const u8) ?[]const u8 {
    const path = std.fs.path.join(gpa, &.{ o.fonts_dir, file }) catch return null;
    defer gpa.free(path);
    return std.Io.Dir.cwd().readFileAlloc(o.io, path, gpa, .limited(32 * 1024 * 1024)) catch null;
}

/// Segoe UI and Consolas ship with Windows. Loading them (instead of DVUI's bundled Vera) makes
/// text look like the rest of the system and covers more characters. Any missing file just falls
/// back to the bundled font.
fn loadWindowsFonts(gpa: std.mem.Allocator, o: Options, out: *std.ArrayList(dvui.Font.Source)) void {
    if (o.fonts_dir.len == 0) return;
    const Spec = struct { family: []const u8, file: []const u8, weight: dvui.Font.Weight, style: dvui.Font.Style };
    const specs = [_]Spec{
        .{ .family = "Segoe UI", .file = "segoeui.ttf", .weight = .normal, .style = .normal },
        .{ .family = "Segoe UI", .file = "segoeuib.ttf", .weight = .bold, .style = .normal },
        .{ .family = "Segoe UI", .file = "segoeuii.ttf", .weight = .normal, .style = .italic },
        .{ .family = "Segoe UI", .file = "segoeuiz.ttf", .weight = .bold, .style = .italic },
        .{ .family = "Consolas", .file = "consola.ttf", .weight = .normal, .style = .normal },
        .{ .family = "Consolas", .file = "consolab.ttf", .weight = .bold, .style = .normal },
        .{ .family = "Consolas", .file = "consolai.ttf", .weight = .normal, .style = .italic },
        .{ .family = "Consolas", .file = "consolaz.ttf", .weight = .bold, .style = .italic },
    };
    // Both families or neither: a half-loaded set would mix fonts.
    var loaded: std.ArrayList(dvui.Font.Source) = .empty;
    defer loaded.deinit(gpa);
    for (specs) |s| {
        const bytes = readFont(gpa, o, s.file) orelse {
            for (loaded.items) |l| gpa.free(l.bytes);
            return;
        };
        loaded.append(gpa, .{ .family = dvui.Font.array(s.family), .weight = s.weight, .style = s.style, .bytes = bytes, .allocator = gpa }) catch {
            gpa.free(bytes);
            return;
        };
    }
    out.appendSlice(gpa, loaded.items) catch {};
}

fn makeTheme(dark: bool, fonts: []const dvui.Font.Source) dvui.Theme {
    var t = if (dark) dvui.Theme.builtin.adwaita_dark else dvui.Theme.builtin.adwaita_light;
    if (fonts.len > 0) {
        const size: f32 = 10.5;
        t.font_body = dvui.Font.find(.{ .family = "Segoe UI", .size = size, .line_height_factor = 1.3 });
        t.font_heading = dvui.Font.find(.{ .family = "Segoe UI", .size = size, .weight = .bold });
        t.font_title = dvui.Font.find(.{ .family = "Segoe UI", .size = size * 1.4, .weight = .bold });
        t.font_mono = dvui.Font.find(.{ .family = "Consolas", .size = size, .line_height_factor = 1.25 });
        t.embedded_fonts = fonts;
    }
    return t;
}

fn setTheme(a: *App, dark: bool) void {
    a.dark = dark;
    a.win.themeSet(makeTheme(dark, a.fonts));
}

// ---------------------------------------------------------------------------------------------
// Lessons: list, search, selection
// ---------------------------------------------------------------------------------------------

fn searchText(a: *const App) []const u8 {
    return std.mem.sliceTo(&a.search_buf, 0);
}

/// Rebuilds the visible lesson list. With a search: matching lessons, best first (flat). Without:
/// every lesson grouped by area in course order, leaving out the areas the learner collapsed.
fn rebuildList(a: *App) void {
    @memcpy(&a.last_query, &a.search_buf);
    if (searchText(a).len > 0) {
        winlab.search.search(a.gpa, a.docs, searchText(a), &a.visible) catch return;
        return;
    }
    a.visible.clearRetainingCapacity();
    if (a.path) |pi| {
        // A path: its lessons in stage order, each lesson once (required, then optional, per stage).
        for (a.o.paths[pi].stages) |st| {
            for (st.pages) |p| appendUnique(a, p);
            for (st.optional) |p| appendUnique(a, p);
        }
        return;
    }
    for (0..a.group_count) |g| {
        if (!a.collapsed[g]) appendGroup(a, g);
    }
}

fn appendUnique(a: *App, page: usize) void {
    for (a.visible.items) |v| if (v == page) return;
    a.visible.append(a.gpa, page) catch {};
}

fn statusOf(a: *const App, i: usize) winlab.progress.Status {
    const t = a.o.tracking orelse return .not_started;
    return t.progress.get(a.pages[i].id).status;
}

fn selectPage(a: *App, index: usize) void {
    if (index >= a.pages.len or index == a.current) return;
    commitNotes(a);
    a.current = index;
    a.reader_scroll.scrollToOffset(.vertical, 0);
    loadNotes(a);
    rememberPosition(a);
    dvui.refresh(null, @src(), null);
}

/// Stores the open lesson as the last position on the active path, so the next start resumes there.
fn rememberPosition(a: *App) void {
    const pi = a.path orelse return;
    const t = a.o.tracking orelse return;
    const id = a.pages[a.current].id;
    if (std.mem.eql(u8, t.progress.lastOnPath(a.o.paths[pi].id), id)) return;
    t.progress.setLastOnPath(a.o.paths[pi].id, id) catch return;
    _ = t.save(t.save_ctx, t.progress);
}

/// Index of the page with this lesson id, or null.
fn pageById(a: *const App, id: []const u8) ?usize {
    for (a.pages, 0..) |p, i| if (std.mem.eql(u8, p.id, id)) return i;
    return null;
}

/// The special stored value for "I chose to see every lesson", so the first-run picker does not return.
const all_lessons_key = "all";

/// Follows path `pi` (null: all lessons by area), remembers the choice, and opens the learner's place:
/// the last lesson they had open on that path, else the first lesson not yet done.
fn choosePath(a: *App, pi: ?usize) void {
    a.path = pi;
    a.search_buf = @splat(0);
    rebuildList(a);
    if (a.o.tracking) |t| {
        t.progress.setActivePath(if (pi) |i| a.o.paths[i].id else all_lessons_key) catch {};
        _ = t.save(t.save_ctx, t.progress);
    }
    if (a.visible.items.len == 0) return;
    var target = a.visible.items[0];
    if (pi) |i| if (a.o.tracking) |t| {
        const last = t.progress.lastOnPath(a.o.paths[i].id);
        if (pageById(a, last)) |lp| {
            target = lp;
        } else for (a.visible.items) |p| {
            if (!statusOf(a, p).isDone() and statusOf(a, p) != .skipped) {
                target = p;
                break;
            }
        }
    };
    a.current = a.pages.len; // force the switch even when the lesson is already open
    selectPage(a, target);
}

/// Restores the path from the last session (or, on a first run with no progress, offers the picker).
fn restorePath(a: *App) void {
    if (a.o.paths.len == 0) return;
    const t = a.o.tracking orelse return;
    const id = t.progress.active_path;
    if (id.len == 0) {
        if (t.progress.map.count() == 0) a.show_picker = true;
        return;
    }
    for (a.o.paths, 0..) |p, i| if (std.mem.eql(u8, p.id, id)) {
        choosePath(a, i);
        return;
    };
}

fn nextStatus(s: winlab.progress.Status) winlab.progress.Status {
    return switch (s) {
        .not_started => .in_progress,
        .in_progress => .completed,
        .completed, .known, .skipped => .not_started,
    };
}

fn setStatus(a: *App, status: winlab.progress.Status) void {
    const t = a.o.tracking orelse return;
    const id = a.pages[a.current].id;
    t.progress.setStatus(id, status) catch {
        a.info = "The status could not be stored.";
        return;
    };
    if (!t.save(t.save_ctx, t.progress)) a.info = "Your progress could not be saved to disk.";
}

fn loadNotes(a: *App) void {
    a.notes_for = a.current;
    @memset(&a.notes_buf, 0);
    const t = a.o.tracking orelse return;
    const notes = t.progress.get(a.pages[a.current].id).notes;
    const n = @min(notes.len, a.notes_buf.len - 1);
    @memcpy(a.notes_buf[0..n], notes[0..n]);
}

/// Stores the notes box into the progress and saves if anything changed.
fn commitNotes(a: *App) void {
    const t = a.o.tracking orelse return;
    if (a.notes_for >= a.pages.len) return;
    const id = a.pages[a.notes_for].id;
    const text = std.mem.sliceTo(&a.notes_buf, 0);
    if (std.mem.eql(u8, text, t.progress.get(id).notes)) return;
    t.progress.setNotes(id, text) catch {
        a.info = "Your notes could not be stored.";
        return;
    };
    if (!t.save(t.save_ctx, t.progress)) a.info = "Your notes could not be saved to disk.";
}

// ---------------------------------------------------------------------------------------------
// Frame
// ---------------------------------------------------------------------------------------------

fn frame(a: *App) void {
    pollLab(a);

    var root = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both, .background = true, .style = .window });
    defer root.deinit();

    menuBar(a);

    if (a.pages.len == 1) {
        content(a); // a single file (winlab view): no lesson list
    } else {
        var paned = dvui.paned(@src(), .{ .direction = .horizontal, .collapsed_size = 560, .split_ratio = &a.split, .handle_size = 6 }, .{ .expand = .both });
        defer paned.deinit();
        if (paned.showFirst()) sidebar(a);
        if (paned.showSecond()) content(a);
    }

    dialogs(a);
    globalKeys(a);
}

fn menuBar(a: *App) void {
    var m = dvui.menu(@src(), .horizontal, .{ .expand = .horizontal, .background = true, .style = .window });
    defer m.deinit();

    if (dvui.menuItemLabel(@src(), "Lesson", .{ .submenu = true }, .{})) |r| {
        var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
        defer fw.deinit();
        if (a.o.tracking != null) {
            for ([_]winlab.progress.Status{ .not_started, .in_progress, .completed, .known, .skipped }, 0..) |s, i| {
                var buf: [64]u8 = undefined;
                const label = std.fmt.bufPrint(&buf, "Mark as {s}", .{s.label()}) catch "Mark";
                if (dvui.menuItemLabel(@src(), label, .{}, .{ .expand = .horizontal, .id_extra = i }) != null) {
                    setStatus(a, s);
                    m.close();
                }
            }
            _ = dvui.separator(@src(), .{ .expand = .horizontal });
        }
        if (dvui.menuItemLabel(@src(), "Previous lesson     Ctrl+PgUp", .{}, .{ .expand = .horizontal }) != null) {
            stepLesson(a, -1);
            m.close();
        }
        if (dvui.menuItemLabel(@src(), "Next lesson     Ctrl+PgDn", .{}, .{ .expand = .horizontal }) != null) {
            stepLesson(a, 1);
            m.close();
        }
        if (dvui.menuItemLabel(@src(), "Copy whole lesson (plain text)", .{}, .{ .expand = .horizontal }) != null) {
            if (plainText(a)) |t| dvui.clipboardTextSet(t);
            m.close();
        }
        if (dvui.menuItemLabel(@src(), "Copy whole lesson (Markdown)", .{}, .{ .expand = .horizontal }) != null) {
            dvui.clipboardTextSet(a.pages[a.current].body);
            m.close();
        }
        if (dvui.menuItemLabel(@src(), "Search lessons     Ctrl+F", .{}, .{ .expand = .horizontal }) != null) {
            a.focus_search = true;
            m.close();
        }
        _ = dvui.separator(@src(), .{ .expand = .horizontal });
        if (dvui.menuItemLabel(@src(), "Exit", .{}, .{ .expand = .horizontal }) != null) {
            m.close();
            requestQuit(a);
        }
    }

    if (a.o.paths.len > 0) pathsMenu(a, m);
    if (a.o.shells.len > 0 or a.o.labs.len > 0 or a.o.lab_note.len > 0) practiceMenu(a, m);

    if (dvui.menuItemLabel(@src(), "View", .{ .submenu = true }, .{})) |r| {
        var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
        defer fw.deinit();
        if (dvui.menuItemLabel(@src(), "Larger text     Ctrl+=", .{}, .{ .expand = .horizontal }) != null) a.win.content_scale += 0.1;
        if (dvui.menuItemLabel(@src(), "Smaller text     Ctrl+-", .{}, .{ .expand = .horizontal }) != null) a.win.content_scale = @max(0.5, a.win.content_scale - 0.1);
        if (dvui.menuItemLabel(@src(), "Reset text size", .{}, .{ .expand = .horizontal }) != null) a.win.content_scale = @as(f32, @floatFromInt(a.o.text_scale)) / 100.0;
        if (dvui.menuItemLabel(@src(), if (a.text_view) "Formatted view" else "Plain-text view (select across paragraphs)", .{}, .{ .expand = .horizontal }) != null) {
            a.text_view = !a.text_view;
            m.close();
        }
        _ = dvui.separator(@src(), .{ .expand = .horizontal });
        if (dvui.menuItemLabel(@src(), if (a.dark) "Light theme" else "Dark theme", .{}, .{ .expand = .horizontal }) != null) {
            setTheme(a, !a.dark);
            m.close();
        }
    }

    if (dvui.menuItemLabel(@src(), "Help", .{ .submenu = true }, .{})) |r| {
        var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
        defer fw.deinit();
        if (a.o.setup != null and dvui.menuItemLabel(@src(), "Setup and requirements...", .{}, .{ .expand = .horizontal }) != null) {
            runSetupCheck(a);
            a.show_setup = true;
            m.close();
        }
        if (dvui.menuItemLabel(@src(), "Keyboard shortcuts", .{}, .{ .expand = .horizontal }) != null) {
            a.show_keys = true;
            m.close();
        }
        if (dvui.menuItemLabel(@src(), "About WinLab", .{}, .{ .expand = .horizontal }) != null) {
            a.show_about = true;
            m.close();
        }
    }
}

/// Switching between learning paths and the all-lessons view.
fn pathsMenu(a: *App, m: *dvui.MenuWidget) void {
    const r = dvui.menuItemLabel(@src(), "Paths", .{ .submenu = true }, .{}) orelse return;
    var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
    defer fw.deinit();
    if (dvui.menuItemLabel(@src(), "Choose a learning path...", .{}, .{ .expand = .horizontal }) != null) {
        a.show_picker = true;
        m.close();
    }
    _ = dvui.separator(@src(), .{ .expand = .horizontal });
    if (dvui.menuItemLabel(@src(), if (a.path == null) "All lessons (by area)   (current)" else "All lessons (by area)", .{}, .{ .expand = .horizontal }) != null) {
        choosePath(a, null);
        m.close();
    }
    for (a.o.paths, 0..) |p, i| {
        var buf: [200]u8 = undefined;
        const current = a.path != null and a.path.? == i;
        const label = std.fmt.bufPrint(&buf, "{s}{s}", .{ p.title, if (current) "   (current)" else "" }) catch p.title;
        if (dvui.menuItemLabel(@src(), label, .{}, .{ .expand = .horizontal, .id_extra = i }) != null) {
            choosePath(a, i);
            m.close();
        }
    }
}


// ---------------------------------------------------------------------------------------------
// Setup and requirements
// ---------------------------------------------------------------------------------------------

/// A starting rectangle for a floating window: the wanted size, centred, but never larger than the app window.
/// (A fixed rectangle ran off the right edge at 200% text size.) The learner can still move and resize it.
fn fitRect(want_w: f32, want_h: f32) dvui.Rect {
    const wr = dvui.windowRect();
    const w = @min(want_w, @max(320, wr.w - 24));
    const h = @min(want_h, @max(240, wr.h - 24));
    return .{ .x = @max(8, (wr.w - w) / 2), .y = @max(8, (wr.h - h) / 4), .w = w, .h = h };
}

fn runSetupCheck(a: *App) void {
    const s = a.o.setup orelse return;
    a.setup_n = s.check(s.ctx, &a.setup_items);
}

fn closeSetup(a: *App) void {
    if (a.o.setup) |s| s.finish(s.ctx);
    a.show_setup = false;
}

/// What is installed and what is not, with the choices for anything missing. WinLab never installs software:
/// it shows the command, copies it, or opens the download page, and the learner decides.
fn setupWindow(a: *App) void {
    var open = true;
    var fw = dvui.floatingWindow(@src(), .{ .modal = true, .open_flag = &open }, .{ .rect = fitRect(760, 620), .min_size_content = .{ .w = 520, .h = 360 } });
    defer fw.deinit();
    _ = dvui.windowHeader(.{ .title = "Set up WinLab", .open_flag = &open });

    var body = dvui.box(@src(), .{}, .{ .expand = .both, .padding = .all(14) });
    defer body.deinit();
    const dim: dvui.Color = dvui.themeGet().text.opacity(0.7);
    {
        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(0), .margin = .{ .h = 8 } });
        tl.addText("The lessons need nothing else: read, search, take quizzes and track your progress right away. The hands-on labs run in a virtual machine and need QEMU. WinLab never installs anything by itself; below you see what it found and your choices for what is missing. You can open this window again from the Help menu.", .{});
        tl.deinit();
    }

    var qemu_missing = false;
    for (a.setup_items[0..a.setup_n]) |it| {
        if (!it.ok and std.mem.eql(u8, it.name, "QEMU")) qemu_missing = true;
    }
    {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .h = 8 }, .gravity_x = 1.0 });
        defer row.deinit();
        if (dvui.button(@src(), "Check again", .{}, .{})) runSetupCheck(a);
        if (dvui.button(@src(), if (qemu_missing) "Continue without labs" else "Continue", .{}, .{ .margin = .{ .x = 8 }, .style = .highlight })) open = false;
    }
    if (!open or escapePressed()) closeSetup(a);

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false });
    defer scroll.deinit();

    for (a.setup_items[0..a.setup_n], 0..) |it, i| {
        var row = dvui.box(@src(), .{}, .{ .expand = .horizontal, .background = true, .style = .window, .corners = .all(6), .padding = .all(8), .margin = .{ .y = 3, .h = 3 }, .id_extra = i });
        defer row.deinit();
        const mark = if (it.ok) "Found" else if (it.optional) "Not found (optional)" else "NOT FOUND";
        var head: [160]u8 = undefined;
        const line = std.fmt.bufPrint(&head, "{s}: {s}", .{ it.name, mark }) catch it.name;
        dvui.labelNoFmt(@src(), line, .{}, .{ .font = dvui.Font.theme(.heading), .id_extra = i });
        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(0), .id_extra = i });
        tl.addText(it.detail, .{ .color_text = .{ .color = dim } });
        tl.deinit();
    }

    if (qemu_missing) {
        var card = dvui.box(@src(), .{}, .{ .expand = .horizontal, .background = true, .style = .window, .corners = .all(6), .padding = .all(10), .margin = .{ .y = 8 } });
        defer card.deinit();
        dvui.labelNoFmt(@src(), "To use the labs, choose one:", .{}, .{ .font = dvui.Font.theme(.heading) });
        {
            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(0), .margin = .{ .y = 4 } });
            tl.addText("1. Install with winget (Windows 10 version 1809 or newer, and Windows 11). Run this in a terminal:", .{});
            tl.deinit();
        }
        {
            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = true, .style = .window, .padding = .all(6), .font = dvui.Font.theme(.mono) });
            tl.addText(qemu_winget_command, .{});
            tl.deinit();
        }
        if (dvui.button(@src(), "Copy the command", .{}, .{ .margin = .{ .y = 4 } })) dvui.clipboardTextSet(qemu_winget_command);
        {
            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(0), .margin = .{ .y = 8 } });
            tl.addText("2. Or download the installer from the QEMU website and run it:", .{});
            tl.deinit();
        }
        if (dvui.button(@src(), "Open the QEMU download page", .{}, .{ .margin = .{ .y = 4 } })) a.pending_url = qemu_download_url;
        {
            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(0), .margin = .{ .y = 8 } });
            tl.addText("3. Already installed somewhere else? Set qemu-path (the folder that holds qemu-system-x86_64.exe) in your settings file, then choose Check again:", .{});
            tl.deinit();
        }
        if (a.o.setup.?.settings_path.len > 0) {
            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = true, .style = .window, .padding = .all(6), .font = dvui.Font.theme(.mono) });
            tl.addText(a.o.setup.?.settings_path, .{});
            tl.deinit();
        }
        {
            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(0), .margin = .{ .y = 8 } });
            tl.addText("4. Or skip the labs for now. Everything else works without QEMU.", .{});
            tl.deinit();
        }
    }

}
/// The track picker: each goal with its size, levels and your progress.
fn pickerWindow(a: *App) void {
    var open = true;
    var fw = dvui.floatingWindow(@src(), .{ .modal = true, .open_flag = &open }, .{ .rect = fitRect(820, 640), .min_size_content = .{ .w = 520, .h = 360 } });
    defer fw.deinit();
    _ = dvui.windowHeader(.{ .title = "Choose a learning path", .open_flag = &open });

    var body = dvui.box(@src(), .{}, .{ .expand = .both, .padding = .all(14) });
    defer body.deinit();
    const dim: dvui.Color = dvui.themeGet().text.opacity(0.7);
    {
        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(0), .margin = .{ .h = 8 } });
        tl.addText("Pick the goal you want to reach. A path is advice, not a lock: start anywhere on it, take a lesson's quiz to skip what you already know, and switch paths whenever you like. Your progress belongs to each lesson, so it counts on every path.", .{});
        tl.deinit();
    }
    if (dvui.button(@src(), if (a.path == null) "Show all lessons by area (current)" else "Show all lessons by area", .{}, .{ .margin = .{ .h = 8 } })) {
        choosePath(a, null);
        a.show_picker = false;
    }
    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false });
    defer scroll.deinit();
    for (a.o.paths, 0..) |p, i| {
        var card = dvui.box(@src(), .{}, .{ .expand = .horizontal, .background = true, .style = .window, .corners = .all(6), .padding = .all(10), .margin = .{ .y = 4, .h = 4 }, .id_extra = i });
        defer card.deinit();
        const following = a.path != null and a.path.? == i;
        dvui.labelNoFmt(@src(), p.title, .{}, .{ .font = dvui.Font.theme(.heading), .id_extra = i });
        {
            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(0), .margin = .{ .y = 2, .h = 2 }, .id_extra = i });
            tl.addText(p.goal, .{});
            tl.deinit();
        }
        if (p.audience.len > 0) {
            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(0), .id_extra = i });
            tl.addText(p.audience, .{ .font = dvui.Font.theme(.body).withStyle(.italic), .color_text = .{ .color = dim } });
            tl.deinit();
        }
        var lessons: usize = 0;
        for (p.stages) |st| lessons += st.pages.len;
        const c = pathCounts(a, i);
        var line: [160]u8 = undefined;
        const hours = std.fmt.bufPrint(&line, "{d} lessons, about {d}.{d} h, level {d}-{d}, {d} stage(s)", .{ lessons, p.minutes / 60, (p.minutes % 60) * 10 / 60, p.level_min, p.level_max, p.stages.len }) catch "";
        dvui.labelNoFmt(@src(), hours, .{}, .{ .color_text = .{ .color = dim }, .margin = .{ .y = 4 }, .id_extra = i });
        if (a.o.tracking != null) {
            dvui.label(@src(), "{d} of {d} done", .{ c.done, c.total }, .{ .color_text = .{ .color = dim }, .id_extra = i });
            dvui.progress(@src(), .{ .percent = if (c.total == 0) 0 else @as(f32, @floatFromInt(c.done)) / @as(f32, @floatFromInt(c.total)) }, .{ .expand = .horizontal, .margin = .{ .y = 4, .h = 4 }, .id_extra = i });
        }
        if (dvui.button(@src(), if (following) "Following this path" else "Follow this path", .{}, .{ .style = if (following) null else .highlight, .id_extra = i })) {
            choosePath(a, i);
            a.show_picker = false;
        }
    }
    if (!open or escapePressed()) {
        // Closing without a choice still counts as an answer on a first run, so the picker does not return.
        if (a.path == null) if (a.o.tracking) |t| if (t.progress.active_path.len == 0) {
            t.progress.setActivePath(all_lessons_key) catch {};
            _ = t.save(t.save_ctx, t.progress);
        };
        a.show_picker = false;
    }
}

/// Real shells and the labs of the current lesson.
fn practiceMenu(a: *App, m: *dvui.MenuWidget) void {
    const r = dvui.menuItemLabel(@src(), "Practice", .{ .submenu = true }, .{}) orelse return;
    var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
    defer fw.deinit();

    for (a.o.shells, 0..) |sh, i| {
        var buf: [96]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "Open {s}", .{sh.name}) catch sh.name;
        if (dvui.menuItemLabel(@src(), label, .{}, .{ .expand = .horizontal, .id_extra = i }) != null) {
            openShell(a, sh);
            m.close();
        }
    }
    if (a.o.shells.len > 0) _ = dvui.separator(@src(), .{ .expand = .horizontal });

    var any = false;
    const lesson = a.pages[a.current].id;
    for (a.o.labs, 0..) |l, i| {
        if (!std.mem.eql(u8, l.lesson, lesson)) continue;
        any = true;
        var buf: [300]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "Lab: {s}", .{l.title}) catch l.title;
        if (dvui.menuItemLabel(@src(), label, .{}, .{ .expand = .horizontal, .id_extra = 1000 + i }) != null) {
            openLab(a, i);
            m.close();
        }
    }
    if (!any) {
        dvui.labelNoFmt(@src(), "No lab for this lesson yet", .{}, .{ .padding = .{ .x = 8, .y = 4, .w = 8, .h = 4 }, .color_text = .{ .color = dvui.themeGet().text.opacity(0.6) } });
    }
}

fn stepLesson(a: *App, delta: isize) void {
    // Move within the visible (searched) list when the current lesson is in it, else within all lessons.
    const vis = a.visible.items;
    for (vis, 0..) |p, row| {
        if (p != a.current) continue;
        const target: isize = @as(isize, @intCast(row)) + delta;
        if (target < 0 or target >= vis.len) return;
        selectPage(a, vis[@intCast(target)]);
        a.focus_row = null;
        return;
    }
    const target: isize = @as(isize, @intCast(a.current)) + delta;
    if (target < 0 or target >= a.pages.len) return;
    selectPage(a, @intCast(target));
}

fn openShell(a: *App, sh: ShellChoice) void {
    terminal_win.open(a.gpa, a.hwnd, .{
        .command = sh.command,
        .shell_name = sh.name,
        .lesson_title = a.pages[a.current].title,
        .start_dir = a.o.start_dir,
        .text_scale = @intFromFloat(@round(a.win.content_scale * 100.0)),
        .dark = a.dark,
    }) catch {
        a.info = "The terminal window could not be opened.";
    };
}

// ---------------------------------------------------------------------------------------------
// Sidebar
// ---------------------------------------------------------------------------------------------

fn sidebar(a: *App) void {
    var col = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window, .padding = .{ .x = 10, .y = 10, .w = 6, .h = 6 } });
    defer col.deinit();

    {
        // The button shares the title row so it can never be squeezed out by a long path name.
        var tb = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer tb.deinit();
        dvui.labelNoFmt(@src(), "WinLab", .{}, .{ .font = dvui.Font.theme(.title), .expand = .horizontal, .gravity_y = 0.5 });
        if (a.o.paths.len > 0) {
            if (dvui.button(@src(), "Paths...", .{}, .{ .gravity_y = 0.5 })) a.show_picker = true;
        }
    }
    if (a.o.paths.len > 0) {
        const name: []const u8 = if (a.path) |pi| a.o.paths[pi].title else "All lessons";
        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(0), .margin = .{ .y = 2, .h = 2 } });
        tl.addText(name, .{ .font = dvui.Font.theme(.heading) });
        tl.deinit();
    }
    if (a.o.tracking != null) {
        var done: usize = 0;
        var total: usize = a.pages.len;
        if (a.path) |pi| {
            const c = pathCounts(a, pi);
            done = c.done;
            total = c.total;
        } else for (a.pages, 0..) |_, i| {
            if (statusOf(a, i).isDone()) done += 1;
        }
        dvui.label(@src(), "{d} of {d} lessons done", .{ done, total }, .{ .color_text = .{ .color = dvui.themeGet().text.opacity(0.7) } });
        dvui.progress(@src(), .{ .percent = if (total == 0) 0 else @as(f32, @floatFromInt(done)) / @as(f32, @floatFromInt(total)) }, .{ .expand = .horizontal, .margin = .{ .y = 4, .h = 8 } });
    } else {
        _ = dvui.spacer(@src(), .{ .min_size_content = .{ .h = 8 } });
    }

    if (a.pages.len > 1) {
        var te = dvui.textEntry(@src(), .{ .text = .{ .buffer = &a.search_buf }, .placeholder = "Search lessons (Ctrl+F)" }, .{ .expand = .horizontal, .margin = .{ .h = 8 } });
        if (a.focus_search) {
            a.focus_search = false;
            dvui.focusWidget(te.data().id, null, null);
            te.textLayout.selection.selectAll();
        }
        const focused = te.data().id == dvui.focusedWidgetId();
        te.deinit();
        if (!std.mem.eql(u8, &a.last_query, &a.search_buf)) rebuildList(a);
        // Escape in the search box clears it (and the list).
        if (focused) for (dvui.events()) |*e| {
            if (e.handled or e.evt != .key) continue;
            if (e.evt.key.action == .down and e.evt.key.code == .escape and a.search_buf[0] != 0) {
                @memset(&a.search_buf, 0);
                rebuildList(a);
                e.handle(@src(), te.data());
            }
        };
    }

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false });
    defer scroll.deinit();

    if (a.visible.items.len == 0) {
        dvui.labelNoFmt(@src(), "No matching lessons", .{}, .{ .padding = .all(8), .color_text = .{ .color = dvui.themeGet().text.opacity(0.7) } });
    }
    if (searchText(a).len > 0) {
        dvui.label(@src(), "{d} matching", .{a.visible.items.len}, .{ .padding = .{ .x = 4, .h = 4 }, .color_text = .{ .color = dvui.themeGet().text.opacity(0.7) } });
        for (a.visible.items, 0..) |page_index, row| lessonRow(a, page_index, row);
        return;
    }
    if (a.path) |pi| {
        pathBody(a, pi);
        return;
    }
    // Grouped by area. A collapsed area has a header and no rows (rebuildList left them out).
    var row: usize = 0;
    for (0..a.group_count) |g| {
        groupHeader(a, g);
        if (a.collapsed[g]) continue;
        for (a.visible.items) |page_index| {
            if (groupOf(a, page_index) != g) continue;
            lessonRow(a, page_index, row);
            row += 1;
        }
    }
}

const Counts = struct { done: usize = 0, total: usize = 0 };

/// Required lessons of a path and how many are done (studied or Known). Skipped ones count as neither.
fn pathCounts(a: *const App, pi: usize) Counts {
    var c: Counts = .{};
    for (a.o.paths[pi].stages) |st| for (st.pages) |p| {
        c.total += 1;
        if (statusOf(a, p).isDone()) c.done += 1;
    };
    return c;
}

/// The sidebar body in path mode: each stage with its hint, then its lessons in order.
fn pathBody(a: *App, pi: usize) void {
    const dim: dvui.Color = dvui.themeGet().text.opacity(0.7);
    var row: usize = 0;
    for (a.o.paths[pi].stages, 0..) |st, si| {
        var done: usize = 0;
        for (st.pages) |p| if (statusOf(a, p).isDone()) {
            done += 1;
        };
        {
            var hb = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .id_extra = si, .padding = .{ .x = 4, .y = 10, .w = 4, .h = 2 } });
            defer hb.deinit();
            dvui.label(@src(), "{d}. {s}", .{ si + 1, st.title }, .{ .font = dvui.Font.theme(.heading), .expand = .horizontal, .gravity_y = 0.5, .id_extra = si });
            if (a.o.tracking != null) dvui.label(@src(), "{d}/{d}", .{ done, st.pages.len }, .{ .gravity_y = 0.5, .color_text = .{ .color = dim }, .id_extra = si });
        }
        if (st.entry_hint.len > 0) {
            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .{ .x = 4, .w = 6, .h = 4 }, .id_extra = si });
            tl.addText(st.entry_hint, .{ .font = dvui.Font.theme(.body).withStyle(.italic), .color_text = .{ .color = dim } });
            tl.deinit();
        }
        for (st.pages) |p| {
            lessonRow(a, p, row);
            row += 1;
        }
        for (st.optional) |p| {
            if (pageAlreadyListed(a, pi, si, p)) continue;
            lessonRow(a, p, row);
            row += 1;
        }
        stageLabs(a, st, si);
    }
}

/// The labs of a stage as small buttons under its lessons (only labs the course really has).
fn stageLabs(a: *App, st: PathStage, si: usize) void {
    var shown = false;
    for (st.labs, 0..) |lab_id, li| {
        var found: ?usize = null;
        for (a.o.labs, 0..) |l, i| if (std.mem.eql(u8, l.id, lab_id)) {
            found = i;
        };
        const idx = found orelse continue;
        if (!shown) {
            dvui.labelNoFmt(@src(), "Practice", .{}, .{ .padding = .{ .x = 4, .y = 4, .h = 2 }, .color_text = .{ .color = dvui.themeGet().text.opacity(0.7) }, .id_extra = si });
            shown = true;
        }
        var buf: [200]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "Lab: {s}", .{a.o.labs[idx].title}) catch a.o.labs[idx].title;
        if (dvui.button(@src(), label, .{}, .{ .expand = .horizontal, .margin = .{ .x = 4, .y = 1, .w = 8, .h = 1 }, .id_extra = si * 1000 + li })) openLab(a, idx);
    }
}

/// True when an optional lesson was already shown earlier on the path (so its row would repeat).
fn pageAlreadyListed(a: *const App, pi: usize, stage: usize, page: usize) bool {
    for (a.o.paths[pi].stages, 0..) |st, si| {
        if (si > stage) break;
        for (st.pages) |p| if (p == page) return true;
        if (si < stage) for (st.optional) |p| if (p == page) return true;
    }
    return false;
}

fn groupHeader(a: *App, g: usize) void {
    var total: usize = 0;
    var done: usize = 0;
    for (a.pages, 0..) |_, i| {
        if (groupOf(a, i) != g) continue;
        total += 1;
        if (statusOf(a, i).isDone()) done += 1;
    }
    var bw: dvui.ButtonWidget = undefined;
    bw.init(@src(), .{}, .{ .expand = .horizontal, .id_extra = g, .background = false, .padding = .{ .x = 4, .y = 8, .w = 4, .h = 4 }, .margin = .{ .w = 6 } });
    bw.processEvents();
    bw.drawBackground();
    const clicked = bw.clicked();
    {
        var hb = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .id_extra = g });
        defer hb.deinit();
        dvui.icon(@src(), "area", if (a.collapsed[g]) dvui.entypo.triangle_right else dvui.entypo.triangle_down, .{}, .{ .min_size_content = .{ .w = 12, .h = 12 }, .gravity_y = 0.5, .margin = .{ .w = 6 }, .id_extra = g });
        dvui.labelNoFmt(@src(), a.groups[g].title, .{}, .{ .font = dvui.Font.theme(.heading), .expand = .horizontal, .gravity_y = 0.5, .id_extra = g });
        if (a.o.tracking != null) {
            dvui.label(@src(), "{d}/{d}", .{ done, total }, .{ .gravity_y = 0.5, .color_text = .{ .color = dvui.themeGet().text.opacity(0.7) }, .id_extra = g });
        } else {
            dvui.label(@src(), "{d}", .{total}, .{ .gravity_y = 0.5, .color_text = .{ .color = dvui.themeGet().text.opacity(0.7) }, .id_extra = g });
        }
    }
    bw.drawFocus();
    bw.deinit();
    if (clicked) {
        a.collapsed[g] = !a.collapsed[g];
        rebuildList(a);
    }
}

fn lessonRow(a: *App, page_index: usize, row: usize) void {
    const selected = page_index == a.current;
    const theme = dvui.themeGet();
    var bw: dvui.ButtonWidget = undefined;
    bw.init(@src(), .{}, .{
        .expand = .horizontal,
        .id_extra = page_index,
        .background = true,
        .style = if (selected) .highlight else .window,
        .corners = .all(5),
        .margin = .{ .y = 1, .h = 1, .w = 6 },
        .padding = .{ .x = 10, .y = 6, .w = 10, .h = 6 },
    });
    bw.processEvents();
    bw.drawBackground();
    const clicked = bw.clicked();
    if (a.focus_row) |fr| if (fr == page_index) {
        dvui.focusWidget(bw.data().id, null, null);
        a.focus_row = null;
    };
    {
        var vb = dvui.box(@src(), .{}, .{ .expand = .horizontal, .id_extra = page_index });
        defer vb.deinit();
        const text_style = bw.style();
        dvui.labelNoFmt(@src(), a.pages[page_index].title, .{}, text_style.strip().override(.{ .expand = .horizontal, .id_extra = page_index, .font = dvui.Font.theme(.body).withWeight(if (selected) .bold else .normal) }));
        const status = statusOf(a, page_index);
        const small = dvui.Font.theme(.body).withSize(dvui.Font.theme(.body).size * 0.85);
        const p = a.pages[page_index];
        if (status != .not_started) {
            // Words, not just colour, so the state reads without seeing it.
            const tint: dvui.Color = if (selected) theme.highlight.text orelse theme.text else if (status.isDone()) .{ .r = 0x2e, .g = 0x9e, .b = 0x5b } else if (status == .skipped) theme.text.opacity(0.6) else theme.focus;
            dvui.labelNoFmt(@src(), status.label(), .{}, .{ .font = small, .color_text = .{ .color = tint }, .id_extra = page_index });
        } else if (p.level != 0 or p.minutes != 0) {
            const dim: dvui.Color = if (selected) theme.highlight.text orelse theme.text else theme.text.opacity(0.6);
            if (p.level != 0) {
                dvui.label(@src(), "Level {d}  -  {d} min", .{ p.level, p.minutes }, .{ .font = small, .color_text = .{ .color = dim }, .id_extra = page_index });
            } else {
                dvui.label(@src(), "{d} min", .{p.minutes}, .{ .font = small, .color_text = .{ .color = dim }, .id_extra = page_index });
            }
        }
    }
    bw.drawFocus();
    const focused = bw.focused();
    if (focused) {
        // Up/Down walk the list like a native list box; selection follows focus.
        for (dvui.events()) |*e| {
            if (e.handled or e.evt != .key or e.evt.key.action == .up) continue;
            const code = e.evt.key.code;
            const target: ?usize = switch (code) {
                .down => if (row + 1 < a.visible.items.len) a.visible.items[row + 1] else null,
                .up => if (row > 0) a.visible.items[row - 1] else null,
                else => continue,
            };
            e.handle(@src(), bw.data());
            if (target) |t| {
                a.focus_row = t;
                selectPage(a, t);
            }
        }
    }
    bw.deinit();
    if (clicked) selectPage(a, page_index);
}

// ---------------------------------------------------------------------------------------------
// Content: header, reader, notes
// ---------------------------------------------------------------------------------------------

fn content(a: *App) void {
    var col = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .content });
    defer col.deinit();

    header(a);
    prerequisiteNotice(a);
    if (a.o.tracking == null) {
        reader(a);
        return;
    }
    // The divider is draggable, so the notes box can be as tall as the learner wants.
    var split = dvui.paned(@src(), .{ .direction = .vertical, .collapsed_size = 0, .split_ratio = &a.notes_split, .handle_size = 6 }, .{ .expand = .both });
    defer split.deinit();
    if (split.showFirst()) reader(a);
    if (split.showSecond()) notesPane(a);
}

/// A soft warning under the header: lessons this one recommends first that are not done yet, each with a
/// button to open it. Never blocks anything. Prerequisites outside the loaded course are ignored.
fn prerequisiteNotice(a: *App) void {
    if (a.o.tracking == null) return;
    var missing: [8]usize = undefined;
    var n: usize = 0;
    for (a.pages[a.current].prerequisites) |pre| {
        const pi = pageById(a, pre) orelse continue;
        const st = statusOf(a, pi);
        if (st.isDone() or st == .skipped) continue;
        if (n < missing.len) {
            missing[n] = pi;
            n += 1;
        }
    }
    if (n == 0) return;
    var bar = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .background = true, .style = .control, .padding = .{ .x = 16, .y = 4, .w = 12, .h = 4 } });
    defer bar.deinit();
    dvui.labelNoFmt(@src(), "Recommended first (not required):", .{}, .{ .gravity_y = 0.5, .margin = .{ .w = 8 } });
    for (missing[0..n], 0..) |pi, i| {
        if (dvui.button(@src(), a.pages[pi].title, .{}, .{ .gravity_y = 0.5, .id_extra = i, .margin = .{ .w = 6 }, .style = .highlight })) selectPage(a, pi);
    }
}

fn header(a: *App) void {
    var bar = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .horizontal, .background = true, .style = .window, .padding = .{ .x = 16, .y = 8, .w = 12, .h = 8 } });
    defer bar.deinit();

    {
        // Title with the level and time on a second line.
        var tcol = dvui.box(@src(), .{}, .{ .expand = .horizontal });
        defer tcol.deinit();
        dvui.labelNoFmt(@src(), a.pages[a.current].title, .{}, .{ .font = dvui.Font.theme(.heading).withSize(dvui.Font.theme(.body).size * 1.15), .expand = .horizontal });
        const cur = a.pages[a.current];
        if (cur.level != 0) {
            dvui.label(@src(), "Level {d}  -  {d} min", .{ cur.level, cur.minutes }, .{ .color_text = .{ .color = dvui.themeGet().text.opacity(0.7) } });
        }
    }

    // The buttons get their own row, so a long title can never push them off the window.
    var btns = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .y = 4 } });
    defer btns.deinit();

    if (a.o.tracking != null) {
        var buf: [96]u8 = undefined;
        const s = statusOf(a, a.current);
        const label = std.fmt.bufPrint(&buf, "Status: {s}", .{s.label()}) catch "Status";
        if (dvui.button(@src(), label, .{}, .{ .gravity_y = 0.5, .margin = .{ .w = 8 } })) setStatus(a, nextStatus(s));
    }
    // A quiz button only for a lesson that has a quiz; it shows the best score so far.
    if (quizFor(a, a.pages[a.current].id)) |qi| {
        var qbuf: [96]u8 = undefined;
        const best = if (a.o.tracking) |t| t.progress.get(a.pages[a.current].id) else winlab.progress.Entry{};
        const st = statusOf(a, a.current);
        // Not started: the quiz doubles as a placement test (80% or more marks the lesson Known).
        const placement = a.o.tracking != null and (st == .not_started or st == .skipped);
        const label = if (placement)
            "I already know this (quiz)"
        else if (best.quiz_attempts > 0)
            (std.fmt.bufPrint(&qbuf, "Quiz (best {d}%)", .{best.quiz_best}) catch "Quiz")
        else
            "Take the quiz";
        if (dvui.button(@src(), label, .{}, .{ .gravity_y = 0.5, .margin = .{ .w = 8 } })) startQuiz(a, qi);
    }
    // A lab button only for a lesson that has labs.
    const lesson = a.pages[a.current].id;
    var first_lab: ?usize = null;
    var lab_count: usize = 0;
    for (a.o.labs, 0..) |l, i| {
        if (!std.mem.eql(u8, l.lesson, lesson)) continue;
        if (first_lab == null) first_lab = i;
        lab_count += 1;
    }
    if (first_lab) |fl| {
        if (lab_count == 1) {
            if (dvui.button(@src(), "Open lab", .{}, .{ .gravity_y = 0.5, .style = .highlight })) openLab(a, fl);
        } else {
            dvui.labelNoFmt(@src(), "Labs: see the Practice menu", .{}, .{ .gravity_y = 0.5, .color_text = .{ .color = dvui.themeGet().text.opacity(0.7) } });
        }
    }
}

fn reader(a: *App) void {
    var scroll = dvui.scrollArea(@src(), .{ .scroll_info = &a.reader_scroll }, .{ .expand = .both, .background = false });
    defer scroll.deinit();

    var col = dvui.box(@src(), .{}, .{
        .expand = .horizontal,
        .gravity_x = 0.5,
        .max_size_content = .{ .w = reader_width, .h = std.math.floatMax(f32) },
        .padding = .{ .x = 28, .y = 14, .w = 28, .h = 28 },
    });
    defer col.deinit();

    a.view.clicked = null;
    a.view.page = a.current;
    if (a.text_view and plainText(a) != null) {
        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(0), .font = dvui.Font.theme(.mono) });
        defer tl.deinit();
        tl.addText(plainText(a).?, .{});
    } else {
        md_view.render(a.pages[a.current].root, &a.view);
    }
    if (a.view.clicked) |url| a.pending_url = url;

    // Reading order: a clear way to the next lesson at the end of the page (the next on the path, if any).
    if (nextPage(a)) |next| {
        _ = dvui.separator(@src(), .{ .expand = .horizontal, .margin = .{ .y = 16, .h = 12 } });
        var buf: [300]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "Next: {s}", .{a.pages[next].title}) catch "Next lesson";
        if (dvui.button(@src(), label, .{}, .{ .gravity_x = 1.0 })) selectPage(a, next);
    }
}

/// The lesson after the open one: on a path, the next on that path; otherwise the next in course order.
fn nextPage(a: *const App) ?usize {
    if (a.path != null) {
        for (a.visible.items, 0..) |p, row| {
            if (p == a.current) return if (row + 1 < a.visible.items.len) a.visible.items[row + 1] else null;
        }
        return null;
    }
    return if (a.current + 1 < a.pages.len) a.current + 1 else null;
}

fn notesPane(a: *App) void {
    if (a.notes_for != a.current) loadNotes(a);
    var box = dvui.box(@src(), .{}, .{ .expand = .horizontal, .background = true, .style = .window, .padding = .{ .x = 16, .y = 8, .w = 16, .h = 10 } });
    defer box.deinit();
    dvui.labelNoFmt(@src(), "Notes (saved with your progress)", .{}, .{ .font = dvui.Font.theme(.heading), .margin = .{ .h = 4 } });
    var te = dvui.textEntry(@src(), .{ .text = .{ .buffer = &a.notes_buf }, .multiline = true, .break_lines = true, .placeholder = "Your notes for this lesson..." }, .{ .expand = .horizontal, .min_size_content = .{ .h = 72 }, .max_size_content = .{ .w = std.math.floatMax(f32), .h = 110 } });
    const focused = te.data().id == dvui.focusedWidgetId();
    te.deinit();
    // Save when the box loses focus (the page change and quit paths save too).
    if (a.notes_focused and !focused) commitNotes(a);
    a.notes_focused = focused;
}

// ---------------------------------------------------------------------------------------------
// Keys that no widget took
// ---------------------------------------------------------------------------------------------

fn globalKeys(a: *App) void {
    for (dvui.events()) |*e| {
        if (e.handled or e.evt != .key) continue;
        const k = e.evt.key;
        if (k.action == .up) continue;
        const ctrl = k.mod.control();
        if (ctrl and k.code == .f and k.action == .down) {
            a.focus_search = true;
            e.handle(@src(), a.win.data());
        } else if (ctrl and k.code == .page_down and k.action == .down) {
            stepLesson(a, 1);
            e.handle(@src(), a.win.data());
        } else if (ctrl and k.code == .page_up and k.action == .down) {
            stepLesson(a, -1);
            e.handle(@src(), a.win.data());
        } else if (!ctrl) switch (k.code) {
            // Nothing focused wants these, so they scroll the lesson.
            .down => scrollReader(a, .line, 1),
            .up => scrollReader(a, .line, -1),
            .page_down => scrollReader(a, .page, 1),
            .page_up => scrollReader(a, .page, -1),
            .home => a.reader_scroll.scrollToOffset(.vertical, 0),
            .end => a.reader_scroll.scrollToFraction(.vertical, 1.0),
            else => continue,
        } else continue;
        e.handle(@src(), a.win.data());
        dvui.refresh(null, @src(), null);
    }
}

fn scrollReader(a: *App, unit: enum { line, page }, dir: f32) void {
    switch (unit) {
        .line => a.reader_scroll.scrollByOffset(.vertical, dir * 60),
        .page => a.reader_scroll.scrollPage(.vertical, dir < 0),
    }
}

// ---------------------------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------------------------

fn dialogs(a: *App) void {
    if (a.show_setup) setupWindow(a); // first, so the link dialog it can open sits above it
    if (a.pending_url) |url| linkDialog(a, url);
    if (a.info) |msg| infoDialog(a, msg);
    if (a.show_about) aboutDialog(a);
    if (a.show_keys) keysDialog(a);
    if (a.show_picker and !a.show_setup) pickerWindow(a);
    if (a.lab.open) labWindow(a);
    if (a.qz.open) quizWindow(a);
    if (a.lab.confirm_close) closeLabDialog(a);
}

fn escapePressed() bool {
    for (dvui.events()) |*e| {
        if (e.handled or e.evt != .key) continue;
        if (e.evt.key.action == .down and e.evt.key.code == .escape) {
            e.handle(@src(), dvui.currentWindow().data());
            return true;
        }
    }
    return false;
}

fn linkDialog(a: *App, url: []const u8) void {
    var open = true;
    var fw = dvui.floatingWindow(@src(), .{ .modal = true, .open_flag = &open }, .{ .min_size_content = .{ .w = 460 }, .max_size_content = .{ .w = 640, .h = 400 } });
    defer fw.deinit();
    _ = dvui.windowHeader(.{ .title = "Open this link?", .open_flag = &open });

    var body = dvui.box(@src(), .{}, .{ .expand = .horizontal, .padding = .all(14) });
    defer body.deinit();
    const ok = winlab.links.isLaunchable(url);
    if (ok) {
        dvui.labelNoFmt(@src(), "WinLab will open this address in your web browser:", .{}, .{ .margin = .{ .h = 8 } });
    } else {
        dvui.labelNoFmt(@src(), "This link type is not opened from lessons:", .{}, .{ .margin = .{ .h = 8 } });
    }
    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = true, .style = .window, .padding = .all(8), .font = dvui.Font.theme(.mono) });
    tl.addText(url, .{});
    tl.deinit();

    var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .y = 12 }, .gravity_x = 1.0 });
    defer row.deinit();
    // The safe choice comes first and holds focus, so Enter cancels.
    if (dvui.button(@src(), if (ok) "Cancel" else "Close", .{}, .{})) open = false;
    if (dvui.firstFrame(fw.data().id)) dvui.focusWidget(dvui.lastFocusedIdInFrame(), null, null);
    if (ok and dvui.button(@src(), "Open in browser", .{}, .{ .margin = .{ .x = 8 }, .style = .highlight })) {
        _ = dvui.openURL(.{ .url = url });
        open = false;
    }
    if (escapePressed()) open = false;
    if (!open) a.pending_url = null;
}

fn infoDialog(a: *App, msg: []const u8) void {
    var open = true;
    var fw = dvui.floatingWindow(@src(), .{ .modal = true, .open_flag = &open }, .{ .min_size_content = .{ .w = 380 }, .max_size_content = .{ .w = 560, .h = 400 } });
    defer fw.deinit();
    _ = dvui.windowHeader(.{ .title = "WinLab", .open_flag = &open });
    var body = dvui.box(@src(), .{}, .{ .expand = .horizontal, .padding = .all(14) });
    defer body.deinit();
    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false });
    tl.addText(msg, .{});
    tl.deinit();
    if (dvui.button(@src(), "OK", .{}, .{ .gravity_x = 1.0, .margin = .{ .y = 12 } }) or escapePressed()) open = false;
    if (!open) a.info = null;
}

fn aboutDialog(a: *App) void {
    var open = true;
    var fw = dvui.floatingWindow(@src(), .{ .modal = true, .open_flag = &open }, .{ .min_size_content = .{ .w = 380 } });
    defer fw.deinit();
    _ = dvui.windowHeader(.{ .title = "About WinLab", .open_flag = &open });
    var body = dvui.box(@src(), .{}, .{ .expand = .horizontal, .padding = .all(16) });
    defer body.deinit();
    dvui.labelNoFmt(@src(), winlab.version.app_name, .{}, .{ .font = dvui.Font.theme(.title) });
    dvui.label(@src(), "Version {s}", .{winlab.version.app_version}, .{});
    dvui.labelNoFmt(@src(), "An offline Windows administration course with hands-on labs.", .{}, .{ .margin = .{ .y = 8, .h = 4 } });
    dvui.label(@src(), "Built with Zig {s} and DVUI.", .{winlab.version.pinned_zig}, .{ .color_text = .{ .color = dvui.themeGet().text.opacity(0.7) } });
    if (dvui.button(@src(), "Close", .{}, .{ .gravity_x = 1.0, .margin = .{ .y = 12 } }) or escapePressed()) open = false;
    if (!open) a.show_about = false;
}

fn keysDialog(a: *App) void {
    var open = true;
    var fw = dvui.floatingWindow(@src(), .{ .modal = true, .open_flag = &open }, .{ .min_size_content = .{ .w = 420 } });
    defer fw.deinit();
    _ = dvui.windowHeader(.{ .title = "Keyboard shortcuts", .open_flag = &open });
    var body = dvui.box(@src(), .{}, .{ .expand = .horizontal, .padding = .all(16) });
    defer body.deinit();
    const rows = [_][2][]const u8{
        .{ "Ctrl+F", "Search lessons" },
        .{ "Esc (in search)", "Clear the search" },
        .{ "Up / Down (in list)", "Previous / next lesson" },
        .{ "Ctrl+PgUp / Ctrl+PgDn", "Previous / next lesson" },
        .{ "Up Down PgUp PgDn Home End", "Scroll the lesson" },
        .{ "Tab / Shift+Tab", "Move between controls" },
        .{ "Ctrl+= / Ctrl+- / Ctrl+0", "Larger / smaller / reset text" },
    };
    for (rows, 0..) |r, i| {
        var line = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .id_extra = i });
        defer line.deinit();
        dvui.labelNoFmt(@src(), r[0], .{}, .{ .min_size_content = .{ .w = 210 }, .font = dvui.Font.theme(.heading), .id_extra = i });
        dvui.labelNoFmt(@src(), r[1], .{}, .{ .id_extra = i });
    }
    if (dvui.button(@src(), "Close", .{}, .{ .gravity_x = 1.0, .margin = .{ .y = 12 } }) or escapePressed()) open = false;
    if (!open) a.show_keys = false;
}

// ---------------------------------------------------------------------------------------------
// Labs
// ---------------------------------------------------------------------------------------------

fn setLabStatus(l: *LabUi, text: []const u8) void {
    l.status_len = @min(text.len, l.status.len);
    @memcpy(l.status[0..l.status_len], text[0..l.status_len]);
}

fn labLog(a: *App, line: []const u8) void {
    a.lab.log.appendSlice(a.gpa, line) catch return;
    a.lab.log.append(a.gpa, '\n') catch return;
    a.lab.scroll_to_end = true;
}

fn openLab(a: *App, index: usize) void {
    if (a.o.lab_engine == null) {
        a.info = if (a.o.lab_note.len > 0) a.o.lab_note else "No labs are available.";
        return;
    }
    // Reopening the lab that is already in progress keeps its state.
    if (a.lab.open and a.lab.index == index) return;
    if (a.lab.running or a.lab.busy.load(.acquire)) {
        a.info = "Another lab is in progress. Stop its VM first.";
        return;
    }
    const lab = a.o.labs[index];
    a.lab.open = true;
    a.lab.index = index;
    a.lab.hints_shown = 0;
    a.lab.log.clearRetainingCapacity();
    setLabStatus(&a.lab, "Not started. Press Start to boot the lab VM.");
    labLog(a, if (lab.task) "Press Start. The VM window opens; write your script in it (Notepad is fine), save it where the task says, then press Check." else "Press Start. The VM window opens; fix the problem inside it, then press Check.");
}

fn labWorker(a: *App, index: usize, op: Op) void {
    const eng = a.o.lab_engine.?;
    const out = eng.run(eng.ctx, index, op);
    a.lab.outcome = out;
    a.lab.op = op;
    a.lab.done.store(true, .release);
    dvui.refresh(a.win, @src(), null);
}

fn labBegin(a: *App, op: Op) void {
    if (a.lab.busy.swap(true, .acquire)) return;
    setLabStatus(&a.lab, switch (op) {
        .start => "Starting... restoring the broken machine and booting it (this can take a minute or two).",
        .check => "Checking...",
        .reset => "Resetting to the starting problem...",
        .end => "Stopping the VM...",
    });
    const t = std.Thread.spawn(.{}, labWorker, .{ a, a.lab.index, op }) catch {
        a.lab.busy.store(false, .release);
        setLabStatus(&a.lab, "Could not start a background task.");
        return;
    };
    t.detach();
}

/// UI thread: take a finished step's result.
fn pollLab(a: *App) void {
    const l = &a.lab;
    if (!l.done.load(.acquire)) return;
    l.done.store(false, .release);
    const out = &l.outcome;
    const lab = a.o.labs[l.index];
    switch (l.op) {
        .start => {
            l.running = out.ok;
            setLabStatus(l, if (!out.ok) "Could not start." else if (lab.task) "Running. Write your script in the VM window, then press Check." else "Running. Fix the problem in the VM window, then press Check.");
        },
        .check => {
            if (out.ok and out.passed) {
                setLabStatus(l, "Fixed.");
                a.o.lab_engine.?.fixed(a.o.lab_engine.?.ctx, l.index);
            } else if (out.ok) setLabStatus(l, "Not fixed yet.") else setLabStatus(l, "The check could not run.");
        },
        .reset => {
            l.running = false;
            setLabStatus(l, if (out.ok) "Reset. The VM is stopped at the starting problem. Press Start." else "Reset failed.");
        },
        .end => {
            if (out.ok) l.running = false;
            setLabStatus(l, if (out.ok) "The VM is stopped." else "Could not stop the VM.");
        },
    }
    if (out.len > 0) labLog(a, out.text());
    l.busy.store(false, .release);
    if (l.close_after and l.op == .end and out.ok) {
        l.close_after = false;
        a.quit = true;
    }
}

fn labWindow(a: *App) void {
    const l = &a.lab;
    const lab = a.o.labs[l.index];
    const busy = l.busy.load(.acquire);
    var open = true;
    var fw = dvui.floatingWindow(@src(), .{ .open_flag = &open }, .{ .rect = fitRect(720, 620), .min_size_content = .{ .w = 480, .h = 380 } });
    defer fw.deinit();
    _ = dvui.windowHeader(.{ .title = lab.title, .open_flag = &open });

    var body = dvui.box(@src(), .{}, .{ .expand = .both, .padding = .all(14) });
    defer body.deinit();

    dvui.labelNoFmt(@src(), if (lab.task) "Task" else "Reported problem", .{}, .{ .font = dvui.Font.theme(.heading) });
    {
        var sc = dvui.scrollArea(@src(), .{}, .{ .expand = .horizontal, .min_size_content = .{ .h = 90 }, .max_size_content = .{ .w = std.math.floatMax(f32), .h = 170 }, .background = true, .style = .window, .margin = .{ .y = 4, .h = 10 }, .border = .all(1) });
        defer sc.deinit();
        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(8) });
        tl.addText(lab.symptom, .{});
        tl.deinit();
    }

    var status_buf: [260]u8 = undefined;
    const status = std.fmt.bufPrint(&status_buf, "Status: {s}", .{l.status[0..l.status_len]}) catch "Status";
    {
        var srow = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer srow.deinit();
        if (busy) dvui.spinner(@src(), .{ .min_size_content = .{ .w = 22, .h = 22 }, .gravity_y = 0.5, .margin = .{ .w = 8 } });
        dvui.labelNoFmt(@src(), status, .{}, .{ .font = dvui.Font.theme(.heading), .gravity_y = 0.5 });
    }

    {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .y = 10, .h = 10 } });
        defer row.deinit();
        if (labButton(@src(), "Start", !busy and !l.running, .highlight)) labBegin(a, .start);
        if (labButton(@src(), "Check", !busy and l.running, null)) labBegin(a, .check);
        if (labButton(@src(), "Hint", l.hints_shown < lab.hints.len, null)) {
            var buf: [400]u8 = undefined;
            if (std.fmt.bufPrint(&buf, "Hint {d} of {d}: {s}", .{ l.hints_shown + 1, lab.hints.len, lab.hints[l.hints_shown] })) |s| labLog(a, s) else |_| {}
            l.hints_shown += 1;
        }
        if (labButton(@src(), "Reset", !busy, null)) labBegin(a, .reset);
        if (labButton(@src(), "Stop VM", !busy and l.running, null)) labBegin(a, .end);
    }

    dvui.labelNoFmt(@src(), "Progress and hints", .{}, .{ .font = dvui.Font.theme(.heading) });
    var sc = dvui.scrollArea(@src(), .{ .scroll_info = &l.scroll }, .{ .expand = .both, .background = true, .style = .window, .border = .all(1), .margin = .{ .y = 4 } });
    defer sc.deinit();
    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(8) });
    tl.addText(l.log.items, .{});
    tl.deinit();
    if (l.scroll_to_end) {
        l.scroll_to_end = false;
        l.scroll.scrollToFraction(.vertical, 1.0);
        dvui.refresh(null, @src(), null);
    }

    if (!open or escapePressed()) {
        if (busy) {
            a.info = "A step is still running. Wait for it to finish, then close this window.";
        } else if (l.running) {
            l.confirm_close = true;
            l.close_after = false;
            l.close_lab_only = true;
        } else {
            l.open = false;
        }
    }
}

fn labButton(src: std.builtin.SourceLocation, label: []const u8, enabled: bool, style: ?dvui.Theme.Style.Name) bool {
    const opts: dvui.Options = .{ .margin = .{ .w = 8 }, .style = style, .id_extra = @intFromPtr(label.ptr) };
    if (!enabled) {
        // A disabled button is drawn grayed and ignores clicks.
        var bw: dvui.ButtonWidget = undefined;
        bw.init(src, .{ .grayed = true }, opts);
        bw.drawBackground();
        dvui.labelNoFmt(@src(), label, .{ .align_x = 0.5, .align_y = 0.5 }, opts.strip().override(bw.style()).override(.{ .gravity_x = 0.5, .gravity_y = 0.5, .color_text = .{ .color = dvui.themeGet().text.opacity(0.4) } }));
        bw.deinit();
        return false;
    }
    return dvui.button(src, label, .{}, opts);
}

/// Closing while the lab VM runs: stop it too, leave it running, or keep working.
fn closeLabDialog(a: *App) void {
    const l = &a.lab;
    var open = true;
    var fw = dvui.floatingWindow(@src(), .{ .modal = true, .open_flag = &open }, .{ .min_size_content = .{ .w = 420 } });
    defer fw.deinit();
    _ = dvui.windowHeader(.{ .title = "The lab VM is still running", .open_flag = &open });
    var body = dvui.box(@src(), .{}, .{ .expand = .horizontal, .padding = .all(14) });
    defer body.deinit();
    dvui.labelNoFmt(@src(), if (l.close_lab_only) "Stop the VM when you close the lab?" else "Stop the VM when you close WinLab?", .{}, .{ .margin = .{ .h = 12 } });
    var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .gravity_x = 1.0 });
    defer row.deinit();
    if (dvui.button(@src(), "Keep working", .{}, .{ .margin = .{ .w = 8 } })) open = false;
    if (dvui.button(@src(), "Leave it running", .{}, .{ .margin = .{ .w = 8 } })) {
        l.confirm_close = false;
        if (l.close_lab_only) {
            l.open = false;
            l.running = false;
        } else {
            a.quit = true;
        }
        l.close_lab_only = false;
        return;
    }
    if (dvui.button(@src(), "Stop VM", .{}, .{ .style = .highlight })) {
        l.confirm_close = false;
        if (l.close_lab_only) {
            l.open = false;
            l.close_lab_only = false;
            labBegin(a, .end);
        } else {
            l.close_after = true;
            labBegin(a, .end);
        }
        return;
    }
    if (!open or escapePressed()) {
        l.confirm_close = false;
        l.close_lab_only = false;
    }
}

// ---------------------------------------------------------------------------------------------
// Areas (groups of lessons)
// ---------------------------------------------------------------------------------------------

const max_groups = 16;
const GroupInfo = struct { key: []const u8, title: []const u8 };
/// Display order and names of the course areas; an unknown area follows these under its own id.
const known_groups = [_]GroupInfo{
    .{ .key = "foundations", .title = "Foundations" },
    .{ .key = "windows-admin", .title = "Windows administration" },
    .{ .key = "endpoints", .title = "Endpoints and devices" },
    .{ .key = "linux", .title = "Linux" },
    .{ .key = "networking", .title = "Networking" },
    .{ .key = "security", .title = "Security" },
    .{ .key = "operations", .title = "Operations" },
    .{ .key = "hardware", .title = "Hardware" },
};

/// A lesson's area is the part of its id before the first dot (the course folder it lives in).
fn areaKey(id: []const u8) []const u8 {
    return if (std.mem.indexOfScalar(u8, id, '.')) |i| id[0..i] else "";
}

/// Fills `page_group` / `groups` from the lesson ids, known areas first in course order.
fn buildGroups(a: *App) void {
    a.group_count = 0;
    for (known_groups) |kg| {
        for (a.pages) |p| {
            if (std.mem.eql(u8, areaKey(p.id), kg.key)) {
                a.groups[a.group_count] = kg;
                a.group_count += 1;
                break;
            }
        }
    }
    for (a.pages) |p| {
        const key = areaKey(p.id);
        var seen = false;
        for (a.groups[0..a.group_count]) |g| {
            if (std.mem.eql(u8, g.key, key)) seen = true;
        }
        if (seen or a.group_count == max_groups) continue;
        a.groups[a.group_count] = .{ .key = key, .title = if (key.len == 0) "Lessons" else key };
        a.group_count += 1;
    }
}

fn groupOf(a: *const App, page_index: usize) usize {
    const key = areaKey(a.pages[page_index].id);
    for (a.groups[0..a.group_count], 0..) |g, i| {
        if (std.mem.eql(u8, g.key, key)) return i;
    }
    return a.group_count -| 1;
}

/// Adds the lessons of group `g`, in course order.
fn appendGroup(a: *App, g: usize) void {
    for (a.pages, 0..) |_, i| {
        if (groupOf(a, i) == g) a.visible.append(a.gpa, i) catch return;
    }
}

// ---------------------------------------------------------------------------------------------
// Quizzes
// ---------------------------------------------------------------------------------------------

const quiz_lib = winlab.quiz;

const QuizPhase = enum { answering, feedback, done };

const QuizUi = struct {
    open: bool = false,
    /// Index into `Options.quizzes`.
    quiz: usize = 0,
    /// Bank indices of this attempt's questions, in the order asked.
    order: [quiz_lib.max_questions]usize = undefined,
    count: usize = 0,
    pos: usize = 0,
    phase: QuizPhase = .answering,
    /// Display order of the current question's choices (shuffled each time it is shown).
    perm: [quiz_lib.max_choices]u8 = undefined,
    picked: [quiz_lib.max_choices]bool = @splat(false),
    typed: [160]u8 = @splat(0),
    was_correct: bool = false,
    correct: usize = 0,
    missed: [quiz_lib.max_questions]usize = undefined,
    missed_n: usize = 0,
    prng: std.Random.DefaultPrng = std.Random.DefaultPrng.init(0),
    focus_entry: bool = false,
    /// This attempt passed the placement threshold and marked the lesson Known.
    marked_known: bool = false,
};

fn quizFor(a: *const App, lesson_id: []const u8) ?usize {
    for (a.o.quizzes, 0..) |q, i| {
        if (std.mem.eql(u8, q.lesson, lesson_id)) return i;
    }
    return null;
}

fn startQuiz(a: *App, qi: usize) void {
    const z = &a.qz;
    const quiz = &a.o.quizzes[qi];
    z.quiz = qi;
    z.open = true;
    // A fresh draw every attempt; seeded from the frame clock.
    z.prng = std.Random.DefaultPrng.init(@truncate(@as(u128, @bitCast(a.win.frame_time_ns))));
    const missed: []const u8 = if (a.o.tracking) |t| t.progress.get(quiz.lesson).quiz_missed else "";
    z.count = quiz_lib.pick(quiz, missed, z.prng.random(), &z.order);
    z.pos = 0;
    z.correct = 0;
    z.missed_n = 0;
    z.marked_known = false;
    z.phase = .answering;
    startQuestion(a);
}

fn currentQuestion(a: *const App) quiz_lib.Question {
    return a.o.quizzes[a.qz.quiz].questions[a.qz.order[a.qz.pos]];
}

fn startQuestion(a: *App) void {
    const z = &a.qz;
    const q = currentQuestion(a);
    for (0..q.choices.len) |i| z.perm[i] = @intCast(i);
    z.prng.random().shuffle(u8, z.perm[0..q.choices.len]);
    z.picked = @splat(false);
    @memset(&z.typed, 0);
    z.phase = .answering;
    z.focus_entry = q.kind == .short;
}

fn quizReady(a: *const App) bool {
    const q = currentQuestion(a);
    if (q.kind == .short) return std.mem.sliceTo(&a.qz.typed, 0).len > 0;
    for (a.qz.picked[0..q.choices.len]) |p| if (p) return true;
    return false;
}

fn quizSubmit(a: *App) void {
    const z = &a.qz;
    const q = currentQuestion(a);
    if (!quizReady(a)) return;
    if (q.kind == .short) {
        z.was_correct = quiz_lib.gradeShort(q, std.mem.sliceTo(&z.typed, 0));
    } else {
        var texts: [quiz_lib.max_choices][]const u8 = undefined;
        var n: usize = 0;
        for (z.perm[0..q.choices.len], 0..) |orig, slot| {
            if (z.picked[slot]) {
                texts[n] = q.choices[orig];
                n += 1;
            }
        }
        z.was_correct = quiz_lib.gradeChoices(q, texts[0..n]);
    }
    if (z.was_correct) {
        z.correct += 1;
    } else {
        z.missed[z.missed_n] = z.order[z.pos];
        z.missed_n += 1;
    }
    z.phase = .feedback;
}

fn quizNext(a: *App) void {
    const z = &a.qz;
    z.pos += 1;
    if (z.pos < z.count) {
        startQuestion(a);
        return;
    }
    z.phase = .done;
    // Save the result against the lesson, with the ids to bring back next time.
    const quiz = &a.o.quizzes[z.quiz];
    const t = a.o.tracking orelse return;
    var ids: [winlab.progress.max_missed_bytes]u8 = undefined;
    var len: usize = 0;
    for (z.missed[0..z.missed_n]) |bi| {
        const id = quiz.questions[bi].id;
        if (len + id.len + 1 > ids.len) break;
        if (len > 0) {
            ids[len] = ' ';
            len += 1;
        }
        @memcpy(ids[len..][0..id.len], id);
        len += id.len;
    }
    const pct = quiz_lib.percent(z.correct, z.count);
    t.progress.setQuizResult(quiz.lesson, pct, ids[0..len]) catch {
        a.info = "Your quiz result could not be stored.";
        return;
    };
    // Placement: a good score on a lesson not started yet marks it Known.
    z.marked_known = t.progress.markKnownIfPassed(quiz.lesson, pct) catch false;
    if (!t.save(t.save_ctx, t.progress)) a.info = "Your quiz result could not be saved to disk.";
}

fn quizPick(z: *QuizUi, q: quiz_lib.Question, slot: usize) void {
    if (q.kind == .multi) {
        z.picked[slot] = !z.picked[slot];
    } else {
        z.picked = @splat(false);
        z.picked[slot] = true;
    }
}

/// Enter, and the number keys 1 to 8 for the answer in that position, when no widget wants them.
fn quizKeys(a: *App) void {
    const z = &a.qz;
    for (dvui.events()) |*e| {
        if (e.handled or e.evt != .key or e.evt.key.action != .down) continue;
        const code = e.evt.key.code;
        switch (z.phase) {
            .answering => {
                const q = currentQuestion(a);
                if (code == .enter or code == .kp_enter) {
                    if (quizReady(a)) {
                        e.handle(@src(), a.win.data());
                        quizSubmit(a);
                    }
                } else if (q.kind != .short) {
                    const slot: ?usize = switch (code) {
                        .one, .kp_1 => 0,
                        .two, .kp_2 => 1,
                        .three, .kp_3 => 2,
                        .four, .kp_4 => 3,
                        .five, .kp_5 => 4,
                        .six, .kp_6 => 5,
                        .seven, .kp_7 => 6,
                        .eight, .kp_8 => 7,
                        else => null,
                    };
                    if (slot) |s| {
                        if (s < q.choices.len) {
                            e.handle(@src(), a.win.data());
                            quizPick(z, q, s);
                        }
                    }
                }
            },
            .feedback => if (code == .enter or code == .kp_enter) {
                e.handle(@src(), a.win.data());
                quizNext(a);
            },
            .done => {},
        }
    }
}

fn quizTitle(a: *const App, lesson_id: []const u8) []const u8 {
    for (a.pages) |p| if (std.mem.eql(u8, p.id, lesson_id)) return p.title;
    return lesson_id;
}

fn quizWindow(a: *App) void {
    const z = &a.qz;
    const quiz = &a.o.quizzes[z.quiz];
    var open = true;
    var fw = dvui.floatingWindow(@src(), .{ .modal = true, .open_flag = &open }, .{ .rect = fitRect(760, 600), .min_size_content = .{ .w = 520, .h = 400 } });
    defer fw.deinit();
    var title_buf: [200]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buf, "Quiz: {s}", .{quizTitle(a, quiz.lesson)}) catch "Quiz";
    _ = dvui.windowHeader(.{ .title = title, .open_flag = &open });

    var body = dvui.box(@src(), .{}, .{ .expand = .both, .padding = .all(16) });
    defer body.deinit();

    if (z.phase == .done) {
        quizResults(a);
    } else {
        quizQuestion(a);
        quizKeys(a);
    }
    if (!open or escapePressed()) z.open = false;
}

fn quizQuestion(a: *App) void {
    const z = &a.qz;
    const q = currentQuestion(a);
    dvui.label(@src(), "Question {d} of {d}", .{ z.pos + 1, z.count }, .{ .font = dvui.Font.theme(.heading) });
    dvui.progress(@src(), .{ .percent = @as(f32, @floatFromInt(z.pos)) / @as(f32, @floatFromInt(z.count)) }, .{ .expand = .horizontal, .margin = .{ .y = 4, .h = 12 } });

    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(0), .margin = .{ .h = 10 } });
    tl.addText(q.prompt, .{ .font = dvui.Font.theme(.body).withWeight(.bold) });
    tl.deinit();

    const locked = z.phase == .feedback;
    {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false });
        defer scroll.deinit();
        quizAnswers(a, q, locked);
    }

    // The action row sits under the scroll area so it never scrolls away.
    var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .y = 8 } });
    defer row.deinit();
    dvui.labelNoFmt(@src(), "Enter checks and continues. 1 to 8 pick an answer. Esc closes.", .{}, .{ .expand = .horizontal, .gravity_y = 0.5, .color_text = .{ .color = dvui.themeGet().text.opacity(0.6) } });
    if (locked) {
        if (dvui.button(@src(), if (z.pos + 1 < z.count) "Next question" else "See results", .{}, .{ .style = .highlight })) quizNext(a);
    } else if (quizReady(a)) {
        if (dvui.button(@src(), "Check answer", .{}, .{ .style = .highlight })) quizSubmit(a);
    } else {
        dvui.labelNoFmt(@src(), "Choose an answer", .{}, .{ .color_text = .{ .color = dvui.themeGet().text.opacity(0.6) }, .gravity_y = 0.5 });
    }
}

fn quizAnswers(a: *App, q: quiz_lib.Question, locked: bool) void {
    const z = &a.qz;
    switch (q.kind) {
        .short => {
            if (locked) {
                // Checked: show what was typed as plain text so Enter moves on instead of editing.
                dvui.label(@src(), "Your answer: {s}", .{std.mem.sliceTo(&z.typed, 0)}, .{ .font = dvui.Font.theme(.mono) });
            } else {
                var te = dvui.textEntry(@src(), .{ .text = .{ .buffer = &z.typed }, .placeholder = "Type your answer, then press Enter" }, .{ .expand = .horizontal });
                if (z.focus_entry) {
                    z.focus_entry = false;
                    dvui.focusWidget(te.data().id, null, null);
                }
                // The text box takes the Enter key itself, so submit from its own signal.
                const submit = te.enter_pressed;
                te.deinit();
                if (submit and quizReady(a)) quizSubmit(a);
            }
        },
        .choice, .multi => {
            if (q.kind == .multi) dvui.labelNoFmt(@src(), "Select all that apply.", .{}, .{ .color_text = .{ .color = dvui.themeGet().text.opacity(0.7) }, .margin = .{ .h = 6 } });
            for (z.perm[0..q.choices.len], 0..) |orig, slot| {
                const text = q.choices[orig];
                var buf: [400]u8 = undefined;
                const label = std.fmt.bufPrint(&buf, "{d}.  {s}", .{ slot + 1, text }) catch text;
                // After checking, the right answers are marked, and a wrong pick is marked as such.
                var is_answer = false;
                for (q.answers) |ans| {
                    if (std.mem.eql(u8, ans, text)) is_answer = true;
                }
                const style: ?dvui.Theme.Style.Name = if (locked and is_answer) .highlight else if (locked and z.picked[slot]) .err else if (z.picked[slot]) .highlight else null;
                if (dvui.button(@src(), label, .{}, .{ .expand = .horizontal, .style = style, .id_extra = slot, .margin = .{ .y = 2, .h = 2 } }) and !locked) quizPick(z, q, slot);
            }
        },
    }

    if (!locked) return;
    _ = dvui.separator(@src(), .{ .expand = .horizontal, .margin = .{ .y = 10, .h = 8 } });
    const good: dvui.Color = .{ .r = 0x2e, .g = 0x9e, .b = 0x5b };
    const bad: dvui.Color = .{ .r = 0xd9, .g = 0x4a, .b = 0x3d };
    dvui.labelNoFmt(@src(), if (z.was_correct) "Correct" else "Not quite", .{}, .{ .font = dvui.Font.theme(.heading).withSize(dvui.Font.theme(.body).size * 1.2), .color_text = .{ .color = if (z.was_correct) good else bad } });
    if (!z.was_correct) {
        var ans_buf: [512]u8 = undefined;
        var n: usize = 0;
        for (q.answers, 0..) |ans, i| {
            const part = std.fmt.bufPrint(ans_buf[n..], "{s}{s}", .{ if (i > 0) "; " else "", ans }) catch break;
            n += part.len;
        }
        dvui.label(@src(), "{s}: {s}", .{ if (q.kind == .short) "Accepted answer" else "Right answer", ans_buf[0..n] }, .{ .margin = .{ .y = 4 } });
    }
    var ex = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(0), .margin = .{ .y = 6 } });
    ex.addText(q.explanation, .{});
    ex.deinit();
    if (q.review.len > 0) dvui.label(@src(), "Review in the lesson: {s}", .{q.review}, .{ .color_text = .{ .color = dvui.themeGet().text.opacity(0.7) }, .margin = .{ .y = 4 } });
}

fn quizResults(a: *App) void {
    const z = &a.qz;
    const quiz = &a.o.quizzes[z.quiz];
    const pct = quiz_lib.percent(z.correct, z.count);
    // Score on the left, the buttons on the right, both at the top so they can never be squeezed out.
    {
        var top = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer top.deinit();
        {
            var left = dvui.box(@src(), .{}, .{ .expand = .horizontal });
            defer left.deinit();
            dvui.label(@src(), "{d}%", .{pct}, .{ .font = dvui.Font.theme(.title).withSize(dvui.Font.theme(.body).size * 3) });
            dvui.label(@src(), "{d} of {d} correct", .{ z.correct, z.count }, .{ .font = dvui.Font.theme(.heading) });
        }
        var btns = dvui.box(@src(), .{ .dir = .horizontal }, .{ .gravity_y = 0.5 });
        defer btns.deinit();
        if (dvui.button(@src(), "Try another set", .{}, .{ .margin = .{ .w = 8 }, .style = .highlight })) startQuiz(a, z.quiz);
        if (dvui.button(@src(), "Close", .{}, .{})) z.open = false;
    }
    if (a.o.tracking) |t| {
        const e = t.progress.get(quiz.lesson);
        dvui.label(@src(), "Best score {d}%, attempts {d}. The bank has {d} questions; each attempt draws {d}.", .{ e.quiz_best, e.quiz_attempts, quiz.questions.len, quiz.draw }, .{ .color_text = .{ .color = dvui.themeGet().text.opacity(0.7) }, .margin = .{ .y = 4 } });
    }
    if (z.marked_known) {
        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false, .padding = .all(0), .margin = .{ .y = 8 } });
        tl.addText("You passed the placement threshold: this lesson is now marked Known and counts as done. You can still read it any time.", .{ .font = dvui.Font.theme(.heading), .color_text = .{ .color = .{ .r = 0x2e, .g = 0x9e, .b = 0x5b } } });
        tl.deinit();
    }
    if (z.missed_n > 0) {
        dvui.labelNoFmt(@src(), "To review (these come back first next time):", .{}, .{ .font = dvui.Font.theme(.heading), .margin = .{ .y = 12, .h = 4 } });
    } else {
        dvui.labelNoFmt(@src(), "Nothing missed. A new attempt draws different questions.", .{}, .{ .margin = .{ .y = 12 } });
    }
    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false });
    defer scroll.deinit();
    for (z.missed[0..z.missed_n], 0..) |bi, i| {
        const q = quiz.questions[bi];
        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = true, .style = .window, .padding = .all(8), .margin = .{ .h = 6 }, .id_extra = i });
        tl.addText(q.prompt, .{ .font = dvui.Font.theme(.body).withWeight(.bold) });
        tl.addText("\n", .{});
        tl.addText(q.explanation, .{});
        if (q.review.len > 0) {
            tl.addText("\nReview: ", .{ .font = dvui.Font.theme(.body).withStyle(.italic) });
            tl.addText(q.review, .{ .font = dvui.Font.theme(.body).withStyle(.italic) });
        }
        tl.deinit();
    }
}
/// The current lesson as plain text (md-zig's terminal renderer: wrapped, aligned tables, ASCII rules),
/// cached per page. Null when the page has no parsed document or rendering failed.
fn plainText(a: *App) ?[]const u8 {
    if (a.plain_page == a.current) return a.plain;
    if (a.plain) |p| a.gpa.free(p);
    a.plain = null;
    a.plain_page = a.current;
    const doc = a.pages[a.current].doc orelse return null;
    a.plain = doc.toTextAlloc(a.gpa, .{ .width = 96, .color = false, .unicode = false, .show_urls = true }) catch null;
    return a.plain;
}
