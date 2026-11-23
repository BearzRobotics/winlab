//! Opens a real shell for the learner to type lesson commands into.
//!
//! Windows: WinLab's own terminal window on a pseudo console (`terminal_win.zig`).
//! Linux: the learner's terminal emulator, started with the shell. WinLab does not draw a terminal there; every
//! Linux desktop already has a good one, and it carries the learner's own fonts, colours and shortcuts.
const std = @import("std");
const builtin = @import("builtin");
const platform = @import("winlab").platform;

pub const Config = struct {
    /// Command line, for example "powershell.exe -NoLogo" or "bash".
    command: []const u8,
    /// Human name for the title, for example "Bash".
    shell_name: []const u8,
    /// The lesson the terminal was opened from (title only).
    lesson_title: []const u8 = "",
    /// Starting directory; null uses the process's own.
    start_dir: ?[]const u8 = null,
    text_scale: u32 = 100,
    dark: bool = false,
};

pub const Error = error{ WindowClass, CreateWindow, OutOfMemory, NoTerminal };

const win = if (platform.is_windows) @import("terminal_win.zig") else struct {};

/// `owner` is the parent window handle on Windows and ignored elsewhere.
pub fn open(gpa: std.mem.Allocator, owner: anytype, cfg: Config) Error!void {
    if (platform.is_windows) {
        return win.open(gpa, owner, .{
            .command = cfg.command,
            .shell_name = cfg.shell_name,
            .lesson_title = cfg.lesson_title,
            .start_dir = cfg.start_dir,
            .text_scale = cfg.text_scale,
            .dark = cfg.dark,
        }) catch |e| return switch (e) {
            error.WindowClass => error.WindowClass,
            error.CreateWindow => error.CreateWindow,
            error.OutOfMemory => error.OutOfMemory,
        };
    }
    try launchExternal(gpa, cfg, false);
}

/// `winlab terminal <shell>`: one shell, and return when it ends.
pub fn runStandalone(gpa: std.mem.Allocator, cfg: Config) Error!void {
    if (platform.is_windows) {
        return win.runStandalone(gpa, .{
            .command = cfg.command,
            .shell_name = cfg.shell_name,
            .lesson_title = cfg.lesson_title,
            .start_dir = cfg.start_dir,
            .text_scale = cfg.text_scale,
            .dark = cfg.dark,
        }) catch |e| return switch (e) {
            error.WindowClass => error.WindowClass,
            error.CreateWindow => error.CreateWindow,
            error.OutOfMemory => error.OutOfMemory,
        };
    }
    try launchExternal(gpa, cfg, true);
}

/// Terminal emulators tried in order, with the arguments that precede the command to run. Most take `-e`;
/// gnome-terminal and kgx (GNOME Console) take `--`.
const emulators = [_]struct { exe: []const u8, flag: []const u8 }{
    .{ .exe = "x-terminal-emulator", .flag = "-e" },
    .{ .exe = "gnome-terminal", .flag = "--" },
    .{ .exe = "kgx", .flag = "--" },
    .{ .exe = "konsole", .flag = "-e" },
    .{ .exe = "xfce4-terminal", .flag = "-x" },
    .{ .exe = "kitty", .flag = "--" },
    .{ .exe = "alacritty", .flag = "-e" },
    .{ .exe = "foot", .flag = "--" },
    .{ .exe = "xterm", .flag = "-e" },
};

/// The argument list for starting `cfg.command` in `emulator`. Pure, so it is tested.
fn emulatorArgv(arena: std.mem.Allocator, exe_path: []const u8, flag: []const u8, cfg: Config) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    try list.append(arena, exe_path);
    try list.append(arena, flag);
    var it = std.mem.tokenizeScalar(u8, cfg.command, ' ');
    while (it.next()) |w| try list.append(arena, w);
    return list.items;
}

fn launchExternal(gpa: std.mem.Allocator, cfg: Config, wait: bool) Error!void {
    if (platform.is_windows) unreachable;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = std.Io.Threaded.global_single_threaded.io();
    const path_list = if (std.c.getenv("PATH")) |p| std.mem.span(p) else "/usr/bin:/bin";
    for (emulators) |em| {
        const full = (platform.findInPath(arena, io, path_list, em.exe) catch null) orelse continue;
        const argv = emulatorArgv(arena, full, em.flag, cfg) catch return error.OutOfMemory;
        var child = std.process.spawn(io, .{ .argv = argv, .cwd = if (cfg.start_dir) |d| .{ .path = d } else .inherit, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore }) catch continue;
        if (wait) _ = child.wait(io) catch {};
        return;
    }
    return error.NoTerminal;
}

test "emulator command line puts the shell after the flag" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const argv = try emulatorArgv(arena_state.allocator(), "/usr/bin/xterm", "-e", .{ .command = "pwsh -NoLogo", .shell_name = "PowerShell" });
    try std.testing.expectEqual(@as(usize, 4), argv.len);
    try std.testing.expectEqualStrings("-e", argv[1]);
    try std.testing.expectEqualStrings("pwsh", argv[2]);
    try std.testing.expectEqualStrings("-NoLogo", argv[3]);
}
