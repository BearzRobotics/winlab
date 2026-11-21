//! Shell discovery: which real shells are available on this host.
//! WinLab never reimplements shells (AGENTS.md rule 6); it only locates them.
const std = @import("std");

pub const Shell = enum {
    cmd,
    windows_powershell, // powershell.exe, Windows PowerShell 5.1
    powershell_7, // pwsh.exe, optional install

    pub fn executable(self: Shell) []const u8 {
        return switch (self) {
            .cmd => "cmd.exe",
            .windows_powershell => "powershell.exe",
            .powershell_7 => "pwsh.exe",
        };
    }

    /// Command line used to start an interactive session. Only -NoLogo is added;
    /// profiles, execution policy and elevation are left exactly as the system has them.
    pub fn commandLine(self: Shell) []const u8 {
        return switch (self) {
            .cmd => "cmd.exe",
            .windows_powershell => "powershell.exe -NoLogo",
            .powershell_7 => "pwsh.exe -NoLogo",
        };
    }

    pub fn displayName(self: Shell) []const u8 {
        return switch (self) {
            .cmd => "Command Prompt (cmd.exe)",
            .windows_powershell => "Windows PowerShell 5.1",
            .powershell_7 => "PowerShell 7 (optional)",
        };
    }

    /// Only Windows PowerShell 5.1 ships with Windows; pwsh is an optional prerequisite.
    pub fn isOptional(self: Shell) bool {
        return self == .powershell_7;
    }
};

/// Returns true if `exe` exists as a regular file inside any `;`-separated directory of `path_list`.
pub fn findOnPath(io: std.Io, path_list: []const u8, exe: []const u8) bool {
    var it = std.mem.tokenizeScalar(u8, path_list, ';');
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    while (it.next()) |dir| {
        const full = std.fmt.bufPrint(&buf, "{s}\\{s}", .{ std.mem.trimEnd(u8, dir, "\\"), exe }) catch continue;
        const stat = std.Io.Dir.cwd().statFile(io, full, .{}) catch continue;
        if (stat.kind == .file) return true;
    }
    return false;
}

test "executable names" {
    try std.testing.expectEqualStrings("pwsh.exe", Shell.powershell_7.executable());
    try std.testing.expect(Shell.powershell_7.isOptional());
    try std.testing.expect(!Shell.cmd.isOptional());
}
