//! Generates an `autounattend.xml` answer file for an unattended Windows install
//! (decision record 0006). Pure text generation, no I/O. The lab VM gets a LOCAL
//! account (no Microsoft account), the disk is wiped and partitioned for BIOS
//! boot, and nothing is activated.
//!
//! These files contain the lab account password in clear text; they are
//! generated per VM, kept on the host, and only ever describe a throwaway VM.
const std = @import("std");

pub const Kind = enum {
    /// Windows Server: sets the built-in Administrator's password.
    server,
    /// Windows client (10/11): creates a local administrator account and skips online-account screens.
    client,
};

pub const Options = struct {
    kind: Kind,
    /// Index of the edition inside install.wim (1-based). Check with DISM; for the
    /// Server 2022 evaluation ISO the Desktop Experience editions are the even-numbered ones.
    image_index: u32 = 2,
    computer_name: []const u8,
    /// Local account created (client) or used for AutoLogon label (server uses Administrator).
    account_name: []const u8 = "labadmin",
    password: []const u8,
    time_zone: []const u8 = "UTC",
    /// Windows 11 only: skips the TPM / Secure Boot / RAM checks that a plain VM fails.
    bypass_hardware_checks: bool = false,
    /// Log the account on automatically once so first-boot work can run.
    autologon: bool = true,
    /// Run `winlab_firstlogon.ps1` from the answer drive at first logon (enables OpenSSH for lab control).
    first_logon_script: bool = false,
};

pub const Error = error{ InvalidComputerName, InvalidAccountName, InvalidPassword } || std.Io.Writer.Error;

fn validName(s: []const u8, max: usize) bool {
    if (s.len == 0 or s.len > max) return false;
    for (s) |c| switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '_' => {},
        else => return false,
    };
    return true;
}

fn xmlEscape(w: *std.Io.Writer, s: []const u8) std.Io.Writer.Error!void {
    for (s) |c| switch (c) {
        '&' => try w.writeAll("&amp;"),
        '<' => try w.writeAll("&lt;"),
        '>' => try w.writeAll("&gt;"),
        '"' => try w.writeAll("&quot;"),
        '\'' => try w.writeAll("&apos;"),
        else => try w.writeByte(c),
    };
}

fn tag(w: *std.Io.Writer, indent: usize, name: []const u8, value: []const u8) std.Io.Writer.Error!void {
    for (0..indent) |_| try w.writeAll("  ");
    try w.print("<{s}>", .{name});
    try xmlEscape(w, value);
    try w.print("</{s}>\n", .{name});
}

pub fn write(o: Options, w: *std.Io.Writer) Error!void {
    if (!validName(o.computer_name, 15)) return error.InvalidComputerName;
    if (!validName(o.account_name, 20)) return error.InvalidAccountName;
    if (o.password.len < 8 or o.password.len > 127) return error.InvalidPassword;
    for (o.password) |c| if (c < 0x20 or c == 0x7F) return error.InvalidPassword;

    try w.writeAll(
        \\<?xml version="1.0" encoding="utf-8"?>
        \\<unattend xmlns="urn:schemas-microsoft-com:unattend">
        \\  <settings pass="windowsPE">
        \\    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
        \\      <SetupUILanguage><UILanguage>en-US</UILanguage></SetupUILanguage>
        \\      <InputLocale>en-US</InputLocale>
        \\      <SystemLocale>en-US</SystemLocale>
        \\      <UILanguage>en-US</UILanguage>
        \\      <UserLocale>en-US</UserLocale>
        \\    </component>
        \\    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
        \\
    );
    if (o.bypass_hardware_checks) {
        try w.writeAll(
            \\      <RunSynchronous>
            \\        <RunSynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"><Order>1</Order><Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
            \\        <RunSynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"><Order>2</Order><Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
            \\        <RunSynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"><Order>3</Order><Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
            \\      </RunSynchronous>
            \\
        );
    }
    try w.writeAll(
        \\      <DiskConfiguration xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
        \\        <Disk wcm:action="add">
        \\          <DiskID>0</DiskID>
        \\          <WillWipeDisk>true</WillWipeDisk>
        \\          <CreatePartitions>
        \\            <CreatePartition wcm:action="add"><Order>1</Order><Type>Primary</Type><Size>100</Size></CreatePartition>
        \\            <CreatePartition wcm:action="add"><Order>2</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
        \\          </CreatePartitions>
        \\          <ModifyPartitions>
        \\            <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Label>System</Label><Format>NTFS</Format><Active>true</Active></ModifyPartition>
        \\            <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID><Label>Windows</Label><Letter>C</Letter><Format>NTFS</Format></ModifyPartition>
        \\          </ModifyPartitions>
        \\        </Disk>
        \\      </DiskConfiguration>
        \\      <ImageInstall>
        \\        <OSImage>
        \\          <InstallFrom><MetaData xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" wcm:action="add"><Key>/IMAGE/INDEX</Key>
        \\
    );
    try w.print("            <Value>{d}</Value></MetaData></InstallFrom>\n", .{o.image_index});
    try w.writeAll(
        \\          <InstallTo><DiskID>0</DiskID><PartitionID>2</PartitionID></InstallTo>
        \\        </OSImage>
        \\      </ImageInstall>
        \\      <UserData><AcceptEula>true</AcceptEula></UserData>
        \\    </component>
        \\  </settings>
        \\  <settings pass="specialize">
        \\    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
        \\
    );
    try tag(w, 3, "ComputerName", o.computer_name);
    try tag(w, 3, "TimeZone", o.time_zone);
    try w.writeAll(
        \\    </component>
        \\  </settings>
        \\  <settings pass="oobeSystem">
        \\    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
        \\      <InputLocale>en-US</InputLocale><SystemLocale>en-US</SystemLocale><UILanguage>en-US</UILanguage><UserLocale>en-US</UserLocale>
        \\    </component>
        \\    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
        \\      <OOBE>
        \\        <HideEULAPage>true</HideEULAPage>
        \\        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        \\        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        \\        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        \\        <ProtectYourPC>3</ProtectYourPC>
        \\        <SkipMachineOOBE>true</SkipMachineOOBE>
        \\        <SkipUserOOBE>true</SkipUserOOBE>
        \\      </OOBE>
        \\      <UserAccounts>
        \\
    );
    switch (o.kind) {
        .server => {
            try w.writeAll("        <AdministratorPassword>\n");
            try tag(w, 5, "Value", o.password);
            try w.writeAll("          <PlainText>true</PlainText>\n        </AdministratorPassword>\n");
        },
        .client => {
            try w.writeAll("        <LocalAccounts>\n          <LocalAccount xmlns:wcm=\"http://schemas.microsoft.com/WMIConfig/2002/State\" wcm:action=\"add\">\n");
            try tag(w, 6, "Name", o.account_name);
            try tag(w, 6, "DisplayName", o.account_name);
            try w.writeAll("            <Group>Administrators</Group>\n            <Password>\n");
            try tag(w, 8, "Value", o.password);
            try w.writeAll("              <PlainText>true</PlainText>\n            </Password>\n          </LocalAccount>\n        </LocalAccounts>\n");
        },
    }
    try w.writeAll("      </UserAccounts>\n");
    if (o.autologon) {
        try w.writeAll("      <AutoLogon>\n        <Enabled>true</Enabled>\n        <LogonCount>1</LogonCount>\n");
        try tag(w, 4, "Username", if (o.kind == .server) "Administrator" else o.account_name);
        try w.writeAll("        <Password>\n");
        try tag(w, 5, "Value", o.password);
        try w.writeAll("          <PlainText>true</PlainText>\n        </Password>\n      </AutoLogon>\n");
    }
    if (o.first_logon_script) {
        // The script lives on the removable answer drive; its letter is not fixed, so look for it.
        try w.writeAll(
            \\      <FirstLogonCommands>
            \\        <SynchronousCommand xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" wcm:action="add">
            \\          <Order>1</Order>
            \\          <Description>WinLab guest setup (OpenSSH for lab control)</Description>
            \\          <CommandLine>cmd /c "for %d in (D E F G H I J) do if exist %d:\winlab_firstlogon.ps1 powershell -NoProfile -ExecutionPolicy Bypass -File %d:\winlab_firstlogon.ps1"</CommandLine>
            \\        </SynchronousCommand>
            \\      </FirstLogonCommands>
            \\
        );
    }
    try w.writeAll("    </component>\n  </settings>\n</unattend>\n");
}

test "server answer file" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try write(.{ .kind = .server, .image_index = 2, .computer_name = "WINLAB-SRV", .password = "p&ss<word>1" }, &out.writer);
    const x = out.written();
    try std.testing.expect(std.mem.indexOf(u8, x, "<AdministratorPassword>") != null);
    try std.testing.expect(std.mem.indexOf(u8, x, "<Value>p&amp;ss&lt;word&gt;1</Value>") != null);
    try std.testing.expect(std.mem.indexOf(u8, x, "<Key>/IMAGE/INDEX</Key>") != null);
    try std.testing.expect(std.mem.indexOf(u8, x, "<Value>2</Value></MetaData>") != null);
    try std.testing.expect(std.mem.indexOf(u8, x, "<LocalAccounts>") == null);
    try std.testing.expect(std.mem.indexOf(u8, x, "BypassTPMCheck") == null);
}

test "client answer file has a local account and online-account screens hidden" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try write(.{ .kind = .client, .computer_name = "WINLAB-W11", .password = "S3cret-pass!", .bypass_hardware_checks = true }, &out.writer);
    const x = out.written();
    try std.testing.expect(std.mem.indexOf(u8, x, "<LocalAccounts>") != null);
    try std.testing.expect(std.mem.indexOf(u8, x, "<HideOnlineAccountScreens>true</HideOnlineAccountScreens>") != null);
    try std.testing.expect(std.mem.indexOf(u8, x, "BypassTPMCheck") != null);
    try std.testing.expect(std.mem.indexOf(u8, x, "<Username>labadmin</Username>") != null);
}

test "bad names and passwords are refused" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try std.testing.expectError(error.InvalidComputerName, write(.{ .kind = .server, .computer_name = "bad name", .password = "longenough1" }, &out.writer));
    try std.testing.expectError(error.InvalidComputerName, write(.{ .kind = .server, .computer_name = "THISNAMEISWAYTOOLONG", .password = "longenough1" }, &out.writer));
    try std.testing.expectError(error.InvalidAccountName, write(.{ .kind = .client, .computer_name = "OK", .account_name = "a;b", .password = "longenough1" }, &out.writer));
    try std.testing.expectError(error.InvalidPassword, write(.{ .kind = .server, .computer_name = "OK", .password = "short" }, &out.writer));
}

/// PowerShell run inside the guest at first logon: installs and starts OpenSSH Server,
/// makes PowerShell its shell, and authorises ONE key (the host's per-VM key), whose public half
/// sits next to the script on the answer drive. Needs the guest to reach Windows Update once
/// (the OpenSSH feature is downloaded); the log is kept at C:\winlab-firstlogon.log.
pub const first_logon_script =
    \\$ErrorActionPreference = 'Stop'
    \\Start-Transcript -Path 'C:\winlab-firstlogon.log' -Force | Out-Null
    \\Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null
    \\Set-Service -Name sshd -StartupType Automatic
    \\Start-Service sshd
    \\New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null
    \\$keyFile = 'C:\ProgramData\ssh\administrators_authorized_keys'
    \\Set-Content -Path $keyFile -Value (Get-Content (Join-Path $PSScriptRoot 'authorized_key.pub') -Raw) -Encoding ascii
    \\icacls.exe $keyFile /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null
    \\Write-Output 'WINLAB-SSH-READY'
    \\Stop-Transcript | Out-Null
    \\
;

test "first logon commands are emitted only when asked" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try write(.{ .kind = .server, .computer_name = "S", .password = "longenough1", .first_logon_script = true }, &out.writer);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "winlab_firstlogon.ps1") != null);
    out.clearRetainingCapacity();
    try write(.{ .kind = .server, .computer_name = "S", .password = "longenough1" }, &out.writer);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "FirstLogonCommands") == null);
}
