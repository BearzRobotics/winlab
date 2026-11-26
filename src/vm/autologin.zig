//! The lab VM's own login: reading it from `credentials.txt`, and the guest script that makes the VM's
//! screen log in by itself. Lab VMs are throwaway, so keeping the password in clear text is intended.
const std = @import("std");
const guest = @import("guest.zig");

pub const Login = struct {
    user: []const u8,
    password: []const u8,
};

/// Reads the `User:` and `Password:` (Windows) or `Console password:` (Linux) lines that `vm install` writes.
/// A user line may carry a note in brackets. Null if either is missing. Slices point into `text`.
pub fn parseCredentials(text: []const u8) ?Login {
    var user: []const u8 = "";
    var password: []const u8 = "";
    var lines = std.mem.tokenizeAny(u8, text, "\r\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "User: ")) {
            var words = std.mem.tokenizeScalar(u8, line["User: ".len..], ' ');
            user = words.next() orelse "";
        } else for ([_][]const u8{ "Password: ", "Console password: " }) |key| {
            if (std.mem.startsWith(u8, line, key)) password = std.mem.trim(u8, line[key.len..], " \t");
        }
    }
    if (user.len == 0 or password.len == 0) return null;
    return .{ .user = user, .password = password };
}

pub const Error = error{ Unsupported, UnsafeLogin, OutOfMemory };

/// The script (run as administrator or root) that turns on automatic logon at the VM's screen.
/// Windows also stops asking for Ctrl+Alt+Delete, which a host PC keeps for itself. It takes effect at the
/// guest's next boot. Chimera Linux (dinit) is not supported.
pub fn script(arena: std.mem.Allocator, shell: guest.Shell, distro: []const u8, login: Login) Error![]const u8 {
    // Both values are pasted into a script, so only plain characters are accepted (WinLab generates such ones).
    for ([_][]const u8{ login.user, login.password }) |value| {
        if (value.len == 0 or value.len > 100) return error.UnsafeLogin;
        for (value) |c| if (!(std.ascii.isAlphanumeric(c) or c == '-' or c == '_')) return error.UnsafeLogin;
    }
    return switch (shell) {
        .powershell => std.fmt.allocPrint(arena,
            \\$ErrorActionPreference = 'Stop'
            \\$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
            \\Set-ItemProperty -Path $winlogon -Name AutoAdminLogon -Value '1'
            \\Set-ItemProperty -Path $winlogon -Name DefaultUserName -Value '{s}'
            \\Set-ItemProperty -Path $winlogon -Name DefaultPassword -Value '{s}'
            \\Set-ItemProperty -Path $winlogon -Name DefaultDomainName -Value '.'
            \\Remove-ItemProperty -Path $winlogon -Name AutoLogonCount -ErrorAction SilentlyContinue
            \\Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name DisableCAD -Value 1 -Type DWord
            \\exit 0
        , .{ login.user, login.password }),
        .bash => if (std.mem.eql(u8, distro, "ubuntu") or std.mem.eql(u8, distro, "almalinux"))
            std.fmt.allocPrint(arena,
                \\set -e
                \\mkdir -p /etc/systemd/system/getty@tty1.service.d
                \\printf '%s\n' '[Service]' 'ExecStart=' 'ExecStart=-/sbin/agetty --autologin {s} --noclear %I $TERM' > /etc/systemd/system/getty@tty1.service.d/winlab-autologin.conf
                \\systemctl daemon-reload
            , .{login.user})
        else
            error.Unsupported,
    };
}

test "credentials as each installer writes them" {
    const windows = parseCredentials("Throwaway lab VM 'w'.\nUser: Administrator\nPassword: Abc123\nThis file holds a clear-text password.\n").?;
    try std.testing.expectEqualStrings("Administrator", windows.user);
    try std.testing.expectEqualStrings("Abc123", windows.password);
    const chimera = parseCredentials("User: labadmin (administrator through doas). root has the same password.\r\nConsole password: Xy9\r\nSSH uses a key; password logins over SSH are off.\r\n").?;
    try std.testing.expectEqualStrings("labadmin", chimera.user);
    try std.testing.expectEqualStrings("Xy9", chimera.password);
    try std.testing.expect(parseCredentials("User: x\n") == null);
}

test "auto-login scripts: Windows, systemd Linux, and what is refused" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const login: Login = .{ .user = "labadmin", .password = "Abc123" };

    const windows = try script(arena, .powershell, "", login);
    for ([_][]const u8{ "AutoAdminLogon", "'Abc123'", "AutoLogonCount", "DisableCAD" }) |want|
        try std.testing.expect(std.mem.indexOf(u8, windows, want) != null);
    try std.testing.expect(windows.len < guest.max_script_bytes);

    const linux = try script(arena, .bash, "ubuntu", login);
    try std.testing.expect(std.mem.indexOf(u8, linux, "--autologin labadmin --noclear %I $TERM") != null);
    try std.testing.expectError(error.Unsupported, script(arena, .bash, "chimera", login));
    try std.testing.expectError(error.UnsafeLogin, script(arena, .powershell, "", .{ .user = "a", .password = "x'; calc" }));
}
