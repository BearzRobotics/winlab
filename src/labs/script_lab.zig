//! Scripting labs: the learner writes a script (CMD, PowerShell or bash) in the lab VM and Check runs it.
//! This module only generates text: the guest scripts that create the starter file, install the
//! reference solution (used by `lab verify`), and the test harness that runs the learner's script.
//!
//! Anti-hard-coding: every test's `setup` regenerates its fixtures (usually with random values)
//! each time Check runs, and `expect` computes the expected output from those fixtures BEFORE the
//! learner's script runs, so a script that prints a memorised answer fails. A test can also check the
//! exit code and the state the script leaves on disk (`check` must print OK). The harness never reads
//! the learner's script for keywords (the spec forbids pretending keyword matching proves competence).
const std = @import("std");

pub const Language = enum {
    cmd,
    powershell,
    bash,

    /// Windows labs use the PowerShell harness; Linux labs use the bash harness.
    pub fn isLinux(self: Language) bool {
        return self == .bash;
    }
};

pub const Test = struct {
    /// Snippet (PowerShell on Windows, bash on Linux) that (re)creates the fixtures. May use random values.
    setup: []const u8,
    /// Snippet that prints the output a correct script produces for those fixtures. Empty: stdout is not compared.
    expect: []const u8 = "",
    /// Arguments passed to the script (separated by single spaces; no quoting).
    args: []const u8 = "",
    /// If set, the script must exit with this code.
    expect_exit: ?u32 = null,
    /// Snippet run AFTER the script that must print exactly OK when the state it left is right.
    check: []const u8 = "",
};

pub const Spec = struct {
    language: Language,
    /// Absolute guest path the learner saves the script to (C:\Labs\x.ps1, /home/labadmin/labs/x.sh).
    script_path: []const u8,
    /// Starting content of that file (ASCII).
    starter: []const u8,
    /// A complete working script (ASCII), used by `lab verify` only.
    solution: []const u8,
    tests: []const Test,
};

pub const Error = error{ InvalidPath, WrongExtension, NotAscii, UnsafeText, NoTests, EmptyTest, TooLong, OutOfMemory };

pub const max_guest_script = 14000;
pub const linux_user = "labadmin";

fn validWindowsPath(p: []const u8) bool {
    if (p.len < 6 or p.len > 120) return false;
    if (!(std.ascii.isAlphabetic(p[0]) and p[1] == ':' and p[2] == '\\')) return false;
    for (p[2..]) |c| switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9', '\\', '.', '_', '-' => {},
        else => return false,
    };
    return std.mem.indexOf(u8, p, "..") == null;
}

fn validLinuxPath(p: []const u8) bool {
    const prefix = "/home/" ++ linux_user ++ "/labs/";
    if (!std.mem.startsWith(u8, p, prefix) or p.len > 120) return false;
    for (p[prefix.len..]) |c| switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9', '.', '_', '-' => {},
        else => return false,
    };
    return p.len > prefix.len and std.mem.indexOf(u8, p, "..") == null;
}

/// Text that goes inside a here-string/here-document: ASCII only, and no line may start a terminator.
fn hereSafe(s: []const u8) Error!void {
    for (s) |c| if (c >= 0x80 or (c < 0x20 and c != '\n' and c != '\r' and c != '\t')) return error.NotAscii;
    var lines = std.mem.splitScalar(u8, s, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (std.mem.startsWith(u8, line, "'@") or std.mem.eql(u8, line, "WINLAB_EOF")) return error.UnsafeText;
    }
}

pub fn check(spec: Spec) Error!void {
    const path_ok = if (spec.language.isLinux()) validLinuxPath(spec.script_path) else validWindowsPath(spec.script_path);
    if (!path_ok) return error.InvalidPath;
    const ext_ok = switch (spec.language) {
        .cmd => std.ascii.endsWithIgnoreCase(spec.script_path, ".cmd") or std.ascii.endsWithIgnoreCase(spec.script_path, ".bat"),
        .powershell => std.ascii.endsWithIgnoreCase(spec.script_path, ".ps1"),
        .bash => std.mem.endsWith(u8, spec.script_path, ".sh"),
    };
    if (!ext_ok) return error.WrongExtension;
    if (spec.tests.len == 0) return error.NoTests;
    try hereSafe(spec.starter);
    try hereSafe(spec.solution);
    for (spec.tests) |t| {
        try hereSafe(t.setup);
        try hereSafe(t.expect);
        try hereSafe(t.check);
        if (t.expect.len == 0 and t.expect_exit == null and t.check.len == 0) return error.EmptyTest;
        for (t.args) |c| if (!(std.ascii.isAlphanumeric(c) or c == ' ' or c == '.' or c == '_' or c == '-' or c == '=' or c == ',' or c == ':' or c == '\\' or c == '/')) return error.UnsafeText;
    }
}

/// A script that writes `content` to `path` (PowerShell for Windows, bash for Linux).
pub fn writeFileScript(arena: std.mem.Allocator, spec_language: Language, path: []const u8, content: []const u8) Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    const w = &out.writer;
    if (spec_language.isLinux()) {
        w.print("install -d -o {s} -g {s} /home/{s}/labs\ncat > '{s}' <<'WINLAB_EOF'\n{s}\nWINLAB_EOF\nchown {s}:{s} '{s}'\nchmod 755 '{s}'\n", .{ linux_user, linux_user, linux_user, path, content, linux_user, linux_user, path, path }) catch return error.OutOfMemory;
    } else {
        w.print("$p = '{s}'\nNew-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null\n$c = @'\n{s}\n'@\nSet-Content -Path $p -Value $c -Encoding ASCII\n", .{ path, content }) catch return error.OutOfMemory;
    }
    if (out.written().len > max_guest_script) return error.TooLong;
    return out.toOwnedSlice() catch error.OutOfMemory;
}

/// The Check script: runs the learner's script against every test's fresh fixtures and prints
/// failures plus a final `RESULT: n/N tests passed` line.
pub fn harness(arena: std.mem.Allocator, spec: Spec) Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    if (spec.language.isLinux()) try bashHarness(&out.writer, spec) else try powershellHarness(&out.writer, spec);
    if (out.written().len > max_guest_script) return error.TooLong;
    return out.toOwnedSlice() catch error.OutOfMemory;
}

fn powershellHarness(w: *std.Io.Writer, spec: Spec) Error!void {
    w.print("$ErrorActionPreference = 'Continue'\n$path = '{s}'\n$lang = '{s}'\n", .{ spec.script_path, @tagName(spec.language) }) catch return error.OutOfMemory;
    w.print("if (-not (Test-Path -LiteralPath $path)) {{ \"MISSING: no script was found at $path\"; \"RESULT: 0/{d} tests passed\"; exit 0 }}\n$pass = 0\n$tests = @(\n", .{spec.tests.len}) catch return error.OutOfMemory;
    for (spec.tests) |t| {
        w.print("@{{ args = '{s}'; exitCode = ", .{t.args}) catch return error.OutOfMemory;
        if (t.expect_exit) |c| w.print("{d}", .{c}) catch return error.OutOfMemory else w.writeAll("$null") catch return error.OutOfMemory;
        w.print("; hasExpect = ${s}; setup = @'\n{s}\n'@; expect = @'\n{s}\n'@; check = @'\n{s}\n'@ }}\n", .{ if (t.expect.len > 0) "true" else "false", t.setup, t.expect, t.check }) catch return error.OutOfMemory;
    }
    w.print(
        \\)
        \\$i = 0
        \\foreach ($t in $tests) {{
        \\  $i++
        \\  try {{
        \\    & ([scriptblock]::Create($t.setup)) | Out-Null
        \\    $expected = ''
        \\    if ($t.hasExpect) {{ $expected = ((& ([scriptblock]::Create($t.expect)) | Out-String).Trim() -replace "`r`n", "`n") }}
        \\    $job = Start-Job -ScriptBlock {{ param($p, $l, $a) $ProgressPreference = 'SilentlyContinue'; $arr = @($a -split ' ' | Where-Object {{ $_ }}); if ($l -eq 'cmd') {{ $o = & cmd.exe /c $p @arr 2>&1 }} else {{ $o = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p @arr 2>&1 }}; [pscustomobject]@{{ Out = ($o | Out-String); Code = $LASTEXITCODE }} }} -ArgumentList $path, $lang, $t.args
        \\    if (-not (Wait-Job $job -Timeout 30)) {{ Stop-Job $job; Remove-Job $job -Force; "test ${{i}}: the script did not finish within 30 seconds"; continue }}
        \\    $r = Receive-Job $job
        \\    Remove-Job $job -Force
        \\    $actual = ($r.Out.Trim() -replace "`r`n", "`n")
        \\    $problems = @()
        \\    if ($t.hasExpect -and $actual -cne $expected) {{ $problems += "the output is not what was expected`n    expected: $expected`n    got:      $actual" }}
        \\    if ($t.exitCode -ne $null -and $r.Code -ne $t.exitCode) {{ $problems += "the exit code was $($r.Code), expected $($t.exitCode)" }}
        \\    if ($t.check.Trim()) {{ $c = ((& ([scriptblock]::Create($t.check)) | Out-String).Trim()); if ($c -ne 'OK') {{ $problems += "the result the script left behind is wrong: $c" }} }}
        \\    if ($problems.Count -eq 0) {{ $pass++ }} else {{ "test ${{i}}: " + ($problems -join "`n  ") }}
        \\  }} catch {{ "test ${{i}}: could not run: $($_.Exception.Message)" }}
        \\}}
        \\"RESULT: $pass/{d} tests passed"
        \\
    , .{spec.tests.len}) catch return error.OutOfMemory;
}

fn bashHarness(w: *std.Io.Writer, spec: Spec) Error!void {
    w.print("path='{s}'\nif [ ! -f \"$path\" ]; then echo \"MISSING: no script was found at $path\"; echo \"RESULT: 0/{d} tests passed\"; exit 0; fi\npass=0\n", .{ spec.script_path, spec.tests.len }) catch return error.OutOfMemory;
    for (spec.tests, 0..) |t, i| {
        w.print("t{d}_setup() {{\n{s}\n:\n}}\nt{d}_expect() {{\n{s}\n:\n}}\nt{d}_check() {{\n{s}\n:\n}}\n", .{ i + 1, t.setup, i + 1, t.expect, i + 1, t.check }) catch return error.OutOfMemory;
    }
    for (spec.tests, 0..) |t, i| {
        const n = i + 1;
        w.print("# test {d}\n(\n  t{d}_setup >/dev/null 2>&1\n  chown -R {s}:{s} /home/{s}/labdata 2>/dev/null\n", .{ n, n, linux_user, linux_user, linux_user }) catch return error.OutOfMemory;
        if (t.expect.len > 0) w.print("  expected=$(t{d}_expect 2>&1)\n", .{n}) catch return error.OutOfMemory else w.writeAll("  expected=\n") catch return error.OutOfMemory;
        w.print("  actual=$(runuser -u {s} -- timeout 30 bash \"$path\" {s} 2>&1)\n  code=$?\n  problems=\n", .{ linux_user, t.args }) catch return error.OutOfMemory;
        if (t.expect.len > 0) w.writeAll("  if [ \"$actual\" != \"$expected\" ]; then problems=\"${problems}the output is not what was expected\\n    expected: $expected\\n    got:      $actual\\n\"; fi\n") catch return error.OutOfMemory;
        w.writeAll("  if [ \"$code\" = 124 ]; then problems=\"${problems}the script did not finish within 30 seconds\\n\"; fi\n") catch return error.OutOfMemory;
        if (t.expect_exit) |c| w.print("  if [ \"$code\" != \"{d}\" ] && [ \"$code\" != 124 ]; then problems=\"${{problems}}the exit code was $code, expected {d}\\n\"; fi\n", .{ c, c }) catch return error.OutOfMemory;
        if (t.check.len > 0) w.print("  chk=$(t{d}_check 2>&1)\n  if [ \"$chk\" != OK ]; then problems=\"${{problems}}the result the script left behind is wrong: $chk\\n\"; fi\n", .{n}) catch return error.OutOfMemory;
        w.print("  if [ -z \"$problems\" ]; then exit 0; else printf 'test {d}: %b' \"$problems\"; exit 1; fi\n)\nif [ $? -eq 0 ]; then pass=$((pass+1)); fi\n", .{n}) catch return error.OutOfMemory;
    }
    w.print("echo \"RESULT: $pass/{d} tests passed\"\n", .{spec.tests.len}) catch return error.OutOfMemory;
}

pub fn passLine(arena: std.mem.Allocator, n: usize) ![]u8 {
    return std.fmt.allocPrint(arena, "RESULT: {d}/{d} tests passed", .{ n, n });
}

const sample: Spec = .{
    .language = .powershell,
    .script_path = "C:\\Labs\\count.ps1",
    .starter = "# write your script here",
    .solution = "Write-Output 1",
    .tests = &.{.{ .setup = "$x = 1", .expect = "1" }},
};

test "valid spec passes and the PowerShell harness mentions every piece" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try check(sample);
    const h = try harness(arena.allocator(), sample);
    try std.testing.expect(std.mem.indexOf(u8, h, "$path = 'C:\\Labs\\count.ps1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, h, "RESULT: $pass/1 tests passed") != null);
    try std.testing.expect(std.mem.indexOf(u8, h, "setup = @'\n$x = 1\n'@") != null);
    const w = try writeFileScript(arena.allocator(), .powershell, sample.script_path, sample.starter);
    try std.testing.expect(std.mem.indexOf(u8, w, "# write your script here") != null);
}

test "bash harness runs as the lab user and checks output, exit code and state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const spec: Spec = .{
        .language = .bash,
        .script_path = "/home/labadmin/labs/hi.sh",
        .starter = "#!/bin/bash",
        .solution = "echo hi",
        .tests = &.{.{ .setup = "mkdir -p /home/labadmin/labdata", .expect = "echo hi", .args = "a b", .expect_exit = 0, .check = "echo OK" }},
    };
    try check(spec);
    const h = try harness(arena.allocator(), spec);
    try std.testing.expect(std.mem.indexOf(u8, h, "runuser -u labadmin -- timeout 30 bash \"$path\" a b") != null);
    try std.testing.expect(std.mem.indexOf(u8, h, "t1_check()") != null);
    try std.testing.expect(std.mem.indexOf(u8, h, "RESULT: $pass/1 tests passed") != null);
    const w = try writeFileScript(arena.allocator(), .bash, spec.script_path, spec.starter);
    try std.testing.expect(std.mem.indexOf(u8, w, "cat > '/home/labadmin/labs/hi.sh' <<'WINLAB_EOF'") != null);
}

test "bad specs are refused" {
    var s = sample;
    s.script_path = "relative.ps1";
    try std.testing.expectError(error.InvalidPath, check(s));
    s = sample;
    s.script_path = "C:\\Labs\\a.cmd";
    try std.testing.expectError(error.WrongExtension, check(s));
    s = sample;
    s.language = .bash;
    s.script_path = "/etc/evil.sh";
    try std.testing.expectError(error.InvalidPath, check(s));
    s = sample;
    s.starter = "x\n'@\ny";
    try std.testing.expectError(error.UnsafeText, check(s));
    s = sample;
    s.solution = "caf\xc3\xa9";
    try std.testing.expectError(error.NotAscii, check(s));
    s = sample;
    s.tests = &.{};
    try std.testing.expectError(error.NoTests, check(s));
    s = sample;
    s.tests = &.{.{ .setup = "x" }};
    try std.testing.expectError(error.EmptyTest, check(s));
    s = sample;
    s.tests = &.{.{ .setup = "x", .expect = "y", .args = "a;rm" }};
    try std.testing.expectError(error.UnsafeText, check(s));
}
