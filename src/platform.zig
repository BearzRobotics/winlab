//! Everything that differs between the operating systems WinLab runs on (Windows and Linux), in one place:
//! where settings and VMs live, how PATH is split, and where the helper programs (ssh, curl, ...) are.
//! The rest of the code asks this module instead of reading APPDATA or SystemRoot itself.
const std = @import("std");
const builtin = @import("builtin");

pub const is_windows = builtin.os.tag == .windows;

/// Separator between directories in PATH.
pub const path_sep: u8 = if (is_windows) ';' else ':';
/// Separator this OS uses inside a path.
pub const dir_sep: u8 = if (is_windows) '\\' else '/';
/// ".exe" on Windows, nothing elsewhere.
pub const exe_suffix = if (is_windows) ".exe" else "";

/// The folder that holds the learner's own settings and progress (`APPDATA` on Windows,
/// `$XDG_CONFIG_HOME` or `~/.config` on Linux). WinLab keeps a `WinLab` folder inside it.
pub fn configBase(arena: std.mem.Allocator, env: *const std.process.Environ.Map) ?[]const u8 {
    if (is_windows) return env.get("APPDATA");
    if (nonEmpty(env.get("XDG_CONFIG_HOME"))) |x| return x;
    const home = nonEmpty(env.get("HOME")) orelse return null;
    return std.fs.path.join(arena, &.{ home, ".config" }) catch null;
}

/// The folder for large, machine-local data: lab VMs and downloaded images (`LOCALAPPDATA` on Windows,
/// `$XDG_DATA_HOME` or `~/.local/share` on Linux).
pub fn dataBase(arena: std.mem.Allocator, env: *const std.process.Environ.Map) ?[]const u8 {
    if (is_windows) return env.get("LOCALAPPDATA");
    if (nonEmpty(env.get("XDG_DATA_HOME"))) |x| return x;
    const home = nonEmpty(env.get("HOME")) orelse return null;
    return std.fs.path.join(arena, &.{ home, ".local", "share" }) catch null;
}

/// The learner's home folder, where a terminal starts.
pub fn homeDir(env: *const std.process.Environ.Map) ?[]const u8 {
    return nonEmpty(env.get(if (is_windows) "USERPROFILE" else "HOME"));
}

/// Name for messages: where settings live.
pub const config_dir_label = if (is_windows) "%APPDATA%\\WinLab" else "~/.config/WinLab";
pub const data_dir_label = if (is_windows) "%LOCALAPPDATA%\\WinLab" else "~/.local/share/WinLab";

pub const Tool = enum {
    ssh,
    ssh_keygen,
    curl,
    /// Reads a Linux live ISO (Windows: the bundled bsdtar; Linux: bsdtar from libarchive).
    tar,
};

/// Full path of a helper program. Windows has them under System32; elsewhere they are looked up on PATH and the
/// bare name is returned when they are not found (the caller's spawn then fails with a clear error).
pub fn tool(arena: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, which: Tool) ![]const u8 {
    if (is_windows) {
        const root = env.get("SystemRoot") orelse "C:\\Windows";
        return switch (which) {
            .ssh => std.fs.path.join(arena, &.{ root, "System32", "OpenSSH", "ssh.exe" }),
            .ssh_keygen => std.fs.path.join(arena, &.{ root, "System32", "OpenSSH", "ssh-keygen.exe" }),
            .curl => std.fs.path.join(arena, &.{ root, "System32", "curl.exe" }),
            .tar => std.fs.path.join(arena, &.{ root, "System32", "tar.exe" }),
        };
    }
    const name = switch (which) {
        .ssh => "ssh",
        .ssh_keygen => "ssh-keygen",
        .curl => "curl",
        .tar => "bsdtar",
    };
    return (try findInPath(arena, io, env.get("PATH") orelse "", name)) orelse name;
}

/// The first regular file called `name` in a PATH-style list, as a full path.
pub fn findInPath(arena: std.mem.Allocator, io: std.Io, path_list: []const u8, name: []const u8) !?[]const u8 {
    var it = std.mem.tokenizeScalar(u8, path_list, path_sep);
    while (it.next()) |dir| {
        const full = try std.fs.path.join(arena, &.{ dir, name });
        const st = std.Io.Dir.cwd().statFile(io, full, .{}) catch continue;
        if (st.kind == .file) return full;
    }
    return null;
}

fn nonEmpty(s: ?[]const u8) ?[]const u8 {
    const v = s orelse return null;
    return if (v.len == 0) null else v;
}

test "config and data folders follow the platform's convention" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    if (is_windows) {
        try env.put("APPDATA", "C:\\Users\\a\\AppData\\Roaming");
        try env.put("LOCALAPPDATA", "C:\\Users\\a\\AppData\\Local");
        try std.testing.expectEqualStrings("C:\\Users\\a\\AppData\\Roaming", configBase(arena, &env).?);
        try std.testing.expectEqualStrings("C:\\Users\\a\\AppData\\Local", dataBase(arena, &env).?);
    } else {
        try env.put("HOME", "/home/a");
        try std.testing.expectEqualStrings("/home/a/.config", configBase(arena, &env).?);
        try std.testing.expectEqualStrings("/home/a/.local/share", dataBase(arena, &env).?);
        try env.put("XDG_CONFIG_HOME", "/x/cfg");
        try env.put("XDG_DATA_HOME", "/x/data");
        try std.testing.expectEqualStrings("/x/cfg", configBase(arena, &env).?);
        try std.testing.expectEqualStrings("/x/data", dataBase(arena, &env).?);
        try std.testing.expectEqualStrings("/home/a", homeDir(&env).?);
    }
}
