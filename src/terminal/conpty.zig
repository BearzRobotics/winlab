//! A real shell attached to a Windows pseudo console (ConPTY). WinLab never
//! interprets or rewrites what the learner types; it only moves bytes between
//! the window and the shell (AGENTS.md rule 6). The shell runs as the current
//! user with the current token: there is no elevation here.
//!
//! No threads: the owner polls `read` (non-blocking, PeekNamedPipe) from a UI
//! timer, which keeps the design free of locking.
const std = @import("std");

const HANDLE = ?*anyopaque;
const BOOL = i32;
const HPCON = ?*anyopaque;
const COORD = extern struct { x: i16, y: i16 };

const STARTUPINFOW = extern struct {
    cb: u32 = @sizeOf(STARTUPINFOW),
    lpReserved: ?[*:0]u16 = null,
    lpDesktop: ?[*:0]u16 = null,
    lpTitle: ?[*:0]u16 = null,
    dwX: u32 = 0,
    dwY: u32 = 0,
    dwXSize: u32 = 0,
    dwYSize: u32 = 0,
    dwXCountChars: u32 = 0,
    dwYCountChars: u32 = 0,
    dwFillAttribute: u32 = 0,
    dwFlags: u32 = 0,
    wShowWindow: u16 = 0,
    cbReserved2: u16 = 0,
    lpReserved2: ?*u8 = null,
    hStdInput: HANDLE = null,
    hStdOutput: HANDLE = null,
    hStdError: HANDLE = null,
};
const STARTUPINFOEXW = extern struct {
    StartupInfo: STARTUPINFOW = .{ .cb = @sizeOf(STARTUPINFOEXW) },
    lpAttributeList: ?*anyopaque = null,
};
const PROCESS_INFORMATION = extern struct { hProcess: HANDLE = null, hThread: HANDLE = null, dwProcessId: u32 = 0, dwThreadId: u32 = 0 };

extern "kernel32" fn CreatePipe(*HANDLE, *HANDLE, ?*anyopaque, u32) callconv(.winapi) BOOL;
extern "kernel32" fn CreatePseudoConsole(COORD, HANDLE, HANDLE, u32, *HPCON) callconv(.winapi) i32;
extern "kernel32" fn ResizePseudoConsole(HPCON, COORD) callconv(.winapi) i32;
extern "kernel32" fn ClosePseudoConsole(HPCON) callconv(.winapi) void;
extern "kernel32" fn InitializeProcThreadAttributeList(?*anyopaque, u32, u32, *usize) callconv(.winapi) BOOL;
extern "kernel32" fn UpdateProcThreadAttribute(?*anyopaque, u32, usize, ?*anyopaque, usize, ?*anyopaque, ?*usize) callconv(.winapi) BOOL;
extern "kernel32" fn DeleteProcThreadAttributeList(?*anyopaque) callconv(.winapi) void;
extern "kernel32" fn CreateProcessW(?[*:0]const u16, ?[*:0]u16, ?*anyopaque, ?*anyopaque, BOOL, u32, ?*anyopaque, ?[*:0]const u16, *STARTUPINFOEXW, *PROCESS_INFORMATION) callconv(.winapi) BOOL;
extern "kernel32" fn PeekNamedPipe(HANDLE, ?*anyopaque, u32, ?*u32, ?*u32, ?*u32) callconv(.winapi) BOOL;
extern "kernel32" fn ReadFile(HANDLE, [*]u8, u32, *u32, ?*anyopaque) callconv(.winapi) BOOL;
extern "kernel32" fn WriteFile(HANDLE, [*]const u8, u32, *u32, ?*anyopaque) callconv(.winapi) BOOL;
extern "kernel32" fn GetExitCodeProcess(HANDLE, *u32) callconv(.winapi) BOOL;
extern "kernel32" fn TerminateProcess(HANDLE, u32) callconv(.winapi) BOOL;
extern "kernel32" fn CloseHandle(HANDLE) callconv(.winapi) BOOL;
extern "kernel32" fn Sleep(u32) callconv(.winapi) void;

const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: usize = 0x00020016;
const EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
const CREATE_UNICODE_ENVIRONMENT = 0x00000400;
const STILL_ACTIVE = 259;

pub const Error = error{ PipeFailed, PseudoConsoleFailed, SpawnFailed, WriteFailed, OutOfMemory };

pub const Session = struct {
    pty: HPCON,
    input: HANDLE, // we write what the learner types here
    output: HANDLE, // we read the shell's VT output here
    process: HANDLE,
    thread: HANDLE,
    exit_code: ?u32 = null,

    /// Starts `command_line` (for example `cmd.exe` or `powershell.exe -NoLogo`) in a new
    /// pseudo console of `cols` x `rows`, optionally in `cwd`.
    pub fn start(gpa: std.mem.Allocator, command_line: []const u8, cwd: ?[]const u8, cols: u16, rows: u16) Error!Session {
        var in_r: HANDLE = null;
        var in_w: HANDLE = null;
        var out_r: HANDLE = null;
        var out_w: HANDLE = null;
        if (CreatePipe(&in_r, &in_w, null, 0) == 0) return error.PipeFailed;
        errdefer {
            _ = CloseHandle(in_w);
            if (in_r != null) _ = CloseHandle(in_r);
        }
        if (CreatePipe(&out_r, &out_w, null, 0) == 0) {
            _ = CloseHandle(in_r);
            in_r = null;
            return error.PipeFailed;
        }
        errdefer {
            _ = CloseHandle(out_r);
            if (out_w != null) _ = CloseHandle(out_w);
        }

        var pty: HPCON = null;
        if (CreatePseudoConsole(.{ .x = @intCast(cols), .y = @intCast(rows) }, in_r, out_w, 0, &pty) < 0) {
            _ = CloseHandle(in_r);
            in_r = null;
            _ = CloseHandle(out_w);
            out_w = null;
            return error.PseudoConsoleFailed;
        }
        errdefer ClosePseudoConsole(pty);
        // The pseudo console owns these ends now.
        _ = CloseHandle(in_r);
        in_r = null;
        _ = CloseHandle(out_w);
        out_w = null;

        var attr_size: usize = 0;
        _ = InitializeProcThreadAttributeList(null, 1, 0, &attr_size);
        const attr_mem = gpa.alignedAlloc(u8, .of(usize), attr_size) catch return error.OutOfMemory;
        defer gpa.free(attr_mem);
        if (InitializeProcThreadAttributeList(attr_mem.ptr, 1, 0, &attr_size) == 0) return error.SpawnFailed;
        defer DeleteProcThreadAttributeList(attr_mem.ptr);
        if (UpdateProcThreadAttribute(attr_mem.ptr, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, pty, @sizeOf(HPCON), null, null) == 0) return error.SpawnFailed;

        const cmd16 = std.unicode.utf8ToUtf16LeAllocZ(gpa, command_line) catch return error.OutOfMemory;
        defer gpa.free(cmd16);
        const cwd16: ?[:0]u16 = if (cwd) |c| (std.unicode.utf8ToUtf16LeAllocZ(gpa, c) catch return error.OutOfMemory) else null;
        defer if (cwd16) |c| gpa.free(c);

        comptime std.debug.assert(@sizeOf(STARTUPINFOW) == 104 and @sizeOf(STARTUPINFOEXW) == 112);
        var si: STARTUPINFOEXW = .{ .lpAttributeList = attr_mem.ptr };
        si.StartupInfo.cb = @sizeOf(STARTUPINFOEXW);
        // Without this the child inherits OUR redirected stdio instead of the pseudo console.
        si.StartupInfo.dwFlags = 0x100; // STARTF_USESTDHANDLES, handles left null
        var pi: PROCESS_INFORMATION = .{};
        // Inherit our token and environment: no elevation, no altered environment.
        if (CreateProcessW(null, cmd16.ptr, null, null, 0, EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT, null, if (cwd16) |c| c.ptr else null, &si, &pi) == 0) return error.SpawnFailed;

        return .{ .pty = pty, .input = in_w, .output = out_r, .process = pi.hProcess, .thread = pi.hThread };
    }

    /// Copies available shell output into `buf` without blocking. Returns 0 when
    /// nothing is waiting (or the shell has closed its output).
    pub fn read(self: *Session, buf: []u8) usize {
        var avail: u32 = 0;
        if (PeekNamedPipe(self.output, null, 0, null, &avail, null) == 0 or avail == 0) return 0;
        var got: u32 = 0;
        const want: u32 = @intCast(@min(buf.len, avail));
        if (ReadFile(self.output, buf.ptr, want, &got, null) == 0) return 0;
        return got;
    }

    /// Sends bytes to the shell as if typed.
    pub fn write(self: *Session, bytes: []const u8) Error!void {
        var rest = bytes;
        while (rest.len > 0) {
            var n: u32 = 0;
            if (WriteFile(self.input, rest.ptr, @intCast(@min(rest.len, 4096)), &n, null) == 0 or n == 0) return error.WriteFailed;
            rest = rest[n..];
        }
    }

    pub fn resize(self: *Session, cols: u16, rows: u16) void {
        _ = ResizePseudoConsole(self.pty, .{ .x = @intCast(cols), .y = @intCast(rows) });
    }

    /// The shell's exit code once it has ended, else null.
    pub fn exitCode(self: *Session) ?u32 {
        if (self.exit_code) |c| return c;
        var code: u32 = 0;
        if (GetExitCodeProcess(self.process, &code) == 0 or code == STILL_ACTIVE) return null;
        self.exit_code = code;
        return code;
    }

    /// Ends the shell if it is still running (the learner closed the terminal)
    /// and releases everything.
    pub fn close(self: *Session) void {
        if (self.exitCode() == null) _ = TerminateProcess(self.process, 1);
        // Close our pipe ends first: ClosePseudoConsole can block while the console
        // host still has output nobody is reading.
        _ = CloseHandle(self.input);
        _ = CloseHandle(self.output);
        ClosePseudoConsole(self.pty);
        _ = CloseHandle(self.thread);
        _ = CloseHandle(self.process);
        self.* = undefined;
    }
};

test "cmd.exe runs under a pseudo console and reports its exit code" {
    const gpa = std.testing.allocator;
    var s = try Session.start(gpa, "cmd.exe /c echo winlab-conpty-ok & exit 7", null, 80, 25);
    defer {
        s.close();
    }

    var collected: std.ArrayList(u8) = .empty;
    defer collected.deinit(gpa);
    var buf: [1024]u8 = undefined;
    var waited: u32 = 0;
    var quiet: u32 = 0;
    while (waited < 10_000) : (waited += 20) {
        const n = s.read(&buf);
        try collected.appendSlice(gpa, buf[0..n]);
        // Output can trail the process exit, so wait for a quiet period after it ends.
        if (n != 0) quiet = 0 else quiet += 1;
        if (s.exitCode() != null and quiet >= 15) break;
        Sleep(20);
    }
    try std.testing.expect(std.mem.indexOf(u8, collected.items, "winlab-conpty-ok") != null);
    try std.testing.expectEqual(@as(?u32, 7), s.exitCode());
}

test "typed input reaches the shell" {
    const gpa = std.testing.allocator;
    var s = try Session.start(gpa, "cmd.exe", null, 80, 25);
    defer s.close();
    try s.write("echo typed-by-test\r");
    try s.write("exit 3\r");

    var collected: std.ArrayList(u8) = .empty;
    defer collected.deinit(gpa);
    var buf: [1024]u8 = undefined;
    var waited: u32 = 0;
    var quiet: u32 = 0;
    while (waited < 10_000) : (waited += 20) {
        const n = s.read(&buf);
        try collected.appendSlice(gpa, buf[0..n]);
        // Output can trail the process exit, so wait for a quiet period after it ends.
        if (n != 0) quiet = 0 else quiet += 1;
        if (s.exitCode() != null and quiet >= 15) break;
        Sleep(20);
    }
    try std.testing.expect(std.mem.indexOf(u8, collected.items, "typed-by-test") != null);
    try std.testing.expectEqual(@as(?u32, 3), s.exitCode());
}
