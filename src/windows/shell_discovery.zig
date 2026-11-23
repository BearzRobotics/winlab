//! Shell discovery: which real shells are available on this host.
//! WinLab never reimplements shells (AGENTS.md rule 6); it only locates them.
const std = @import("std");
const platform = @import("../platform.zig");

pub const Shell = enum {
    cmd,
    windows_powershell, // powershell.exe, Windows PowerShell 5.1
    powershell_7, // pwsh, optional install (Windows and Linux)
    bash, // the Linux login shell

    pub fn executable(self: Shell) []const u8 {
        return switch (self) {
            .cmd => "cmd.exe",
            .windows_powershell => "powershell.exe",
            .powershell_7 => "pwsh" ++ platform.exe_suffix,
            .bash => "bash",
        };
    }

    /// Command line used to start an interactive session. Only -NoLogo is added;
    /// profiles, execution policy and elevation are left exactly as the system has them.
    pub fn commandLine(self: Shell) []const u8 {
        return switch (self) {
            .cmd => "cmd.exe",
            .windows_powershell => "powershell.exe -NoLogo",
            .powershell_7 => "pwsh" ++ platform.exe_suffix ++ " -NoLogo",
            .bash => "bash",
        };
    }

    pub fn displayName(self: Shell) []const u8 {
        return switch (self) {
            .cmd => "Command Prompt (cmd.exe)",
            .windows_powershell => "Windows PowerShell 5.1",
            .powershell_7 => "PowerShell 7 (optional)",
            .bash => "Bash",
        };
    }

    /// Only Windows PowerShell 5.1 ships with Windows; pwsh is an optional prerequisite. On Linux bash is expected
    /// and pwsh is the optional one.
    pub fn isOptional(self: Shell) bool {
        return self == .powershell_7;
    }
};

/// The shells that exist on this operating system at all.
pub const here: []const Shell = if (platform.is_windows)
    &.{ .cmd, .windows_powershell, .powershell_7 }
else
    &.{ .bash, .powershell_7 };

/// Returns true if `exe` exists as a regular file inside any directory of the PATH-style list `path_list`.
pub fn findOnPath(io: std.Io, path_list: []const u8, exe: []const u8) bool {
    var it = std.mem.tokenizeScalar(u8, path_list, platform.path_sep);
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    while (it.next()) |dir| {
        const full = std.fmt.bufPrint(&buf, "{s}{c}{s}", .{ std.mem.trimEnd(u8, dir, "\\/"), platform.dir_sep, exe }) catch continue;
        const stat = std.Io.Dir.cwd().statFile(io, full, .{}) catch continue;
        if (stat.kind == .file) return true;
    }
    return false;
}

test "executable names" {
    try std.testing.expect(Shell.powershell_7.isOptional());
    try std.testing.expect(!Shell.cmd.isOptional());
    try std.testing.expectEqualStrings(if (platform.is_windows) "pwsh.exe" else "pwsh", Shell.powershell_7.executable());
    try std.testing.expect(here.len >= 2);
}
