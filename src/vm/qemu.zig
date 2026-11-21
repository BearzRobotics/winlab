//! QEMU provider (decision record 0006). QEMU is an environment prerequisite:
//! it is discovered, never bundled. Snapshots use `qemu-img snapshot` on a
//! qcow2 disk while no QEMU process has it open.
//!
//! NOT implemented yet: starting/stopping a guest and guest command execution.
//! This provider therefore reports `power = false` and `guest_exec = false`,
//! and the lab runner will refuse to run a lab on it (that needs the guest
//! control transport decision and a verified Windows guest).
const std = @import("std");
const p = @import("provider.zig");
const guest = @import("guest.zig");

pub const Tools = struct {
    gpa: std.mem.Allocator,
    qemu_system: []u8,
    qemu_img: []u8,
    /// First line of `qemu-system-x86_64 --version`.
    version: []u8,
    /// The Windows Hypervisor Platform accelerator is available to this binary.
    whpx: bool,

    pub fn deinit(self: *Tools) void {
        self.gpa.free(self.qemu_system);
        self.gpa.free(self.qemu_img);
        self.gpa.free(self.version);
        self.* = undefined;
    }
};

const system_exe = "qemu-system-x86_64.exe";
const img_exe = "qemu-img.exe";

fn isFile(io: std.Io, path: []const u8) bool {
    const st = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return st.kind == .file;
}

/// Looks for QEMU in: `configured_dir`, each PATH directory, Program Files and MSYS2.
/// Returns null when both executables are not found in one directory.
pub fn discover(gpa: std.mem.Allocator, io: std.Io, path_list: []const u8, configured_dir: []const u8) !?Tools {
    var candidates: std.ArrayList([]const u8) = .empty;
    defer candidates.deinit(gpa);
    if (configured_dir.len > 0) try candidates.append(gpa, configured_dir);
    var it = std.mem.tokenizeScalar(u8, path_list, ';');
    while (it.next()) |d| try candidates.append(gpa, d);
    try candidates.append(gpa, "C:\\Program Files\\qemu");
    try candidates.append(gpa, "C:\\msys64\\ucrt64\\bin");

    for (candidates.items) |dir| {
        const d = std.mem.trimEnd(u8, dir, "\\");
        const sys = try std.fmt.allocPrint(gpa, "{s}\\{s}", .{ d, system_exe });
        errdefer gpa.free(sys);
        const img = try std.fmt.allocPrint(gpa, "{s}\\{s}", .{ d, img_exe });
        errdefer gpa.free(img);
        if (!isFile(io, sys) or !isFile(io, img)) {
            gpa.free(sys);
            gpa.free(img);
            continue;
        }
        const version = try firstLine(gpa, io, &.{ sys, "--version" });
        errdefer gpa.free(version);
        const accel = std.process.run(gpa, io, .{ .argv = &.{ sys, "-accel", "help" } }) catch null;
        var whpx = false;
        if (accel) |a| {
            defer gpa.free(a.stdout);
            defer gpa.free(a.stderr);
            whpx = std.mem.indexOf(u8, a.stdout, "whpx") != null or std.mem.indexOf(u8, a.stderr, "whpx") != null;
        }
        return .{ .gpa = gpa, .qemu_system = sys, .qemu_img = img, .version = version, .whpx = whpx };
    }
    return null;
}

fn firstLine(gpa: std.mem.Allocator, io: std.Io, argv: []const []const u8) ![]u8 {
    const r = std.process.run(gpa, io, .{ .argv = argv }) catch return gpa.dupe(u8, "unknown");
    defer gpa.free(r.stdout);
    defer gpa.free(r.stderr);
    const line = std.mem.trim(u8, std.mem.sliceTo(r.stdout, '\n'), " \r");
    return gpa.dupe(u8, if (line.len == 0) "unknown" else line);
}

/// Text shown when QEMU is not installed.
pub const install_guidance =
    "QEMU was not found. Install it, for example with winget: " ++
    "winget install --id SoftwareFreedomConservancy.QEMU --exact " ++
    "(or from https://www.qemu.org/download/#windows, or with MSYS2: " ++
    "pacman -S mingw-w64-ucrt-x86_64-qemu). The winget and installer versions land in " ++
    "C:\\Program Files\\qemu, which WinLab finds on its own; otherwise add the folder to PATH " ++
    "or set qemu-path in WinLab's settings. WinLab never installs software on its own.";

pub const Qemu = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    tools: *const Tools,
    /// Path of the host's ssh.exe (empty: guest control unavailable).
    ssh_exe: []const u8 = "",
    /// Present while a started VM is being kept alive across guest restarts.
    sup: ?*Supervisor = null,

    pub fn provider(self: *Qemu) p.Provider {
        return .{ .ptr = self, .vtable = &vtable };
    }

    /// Runs qemu-img; returns stdout (caller frees) or the provider error.
    fn img(self: *Qemu, args: []const []const u8) p.Error![]u8 {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(self.gpa);
        argv.append(self.gpa, self.tools.qemu_img) catch return error.OutOfMemory;
        argv.appendSlice(self.gpa, args) catch return error.OutOfMemory;
        const r = std.process.run(self.gpa, self.io, .{ .argv = argv.items }) catch return error.ProviderFailed;
        defer self.gpa.free(r.stderr);
        const ok = switch (r.term) {
            .exited => |c| c == 0,
            else => false,
        };
        if (!ok) {
            self.gpa.free(r.stdout);
            // qemu-img refuses to modify an image another process holds open.
            if (std.mem.indexOf(u8, r.stderr, "lock") != null) return error.WrongState;
            return error.ProviderFailed;
        }
        return r.stdout;
    }
};

fn me(ptr: *anyopaque) *Qemu {
    return @ptrCast(@alignCast(ptr));
}

fn safeDisk(t: p.Target) p.Error!void {
    // Never let a path be read as an option.
    if (t.disk.len == 0 or t.disk[0] == '-') return error.ProviderFailed;
}

fn name(_: *anyopaque) []const u8 {
    return "qemu";
}
fn capabilities(ptr: *anyopaque) p.Capabilities {
    const q = me(ptr);
    const ssh = q.ssh_exe.len != 0;
    return .{ .snapshots = true, .power = ssh, .guest_exec = ssh, .accelerated = q.tools.whpx };
}
/// "Running" means some process has the disk image open (see `diskInUse`): QEMU on
/// Windows takes no image lock, so qemu-img would happily modify a live disk.
fn state(ptr: *anyopaque, t: p.Target) p.Error!p.State {
    try safeDisk(t);
    return if (diskInUse(me(ptr).gpa, t.disk)) .running else .stopped;
}

/// Every modifying operation first proves the disk is not open anywhere.
fn requireStopped(ptr: *anyopaque, t: p.Target) p.Error!void {
    if (diskInUse(me(ptr).gpa, t.disk)) return error.WrongState;
}
const HANDLE_ = ?*anyopaque;
extern "kernel32" fn GetProcessId(HANDLE_) callconv(.winapi) u32;
extern "kernel32" fn OpenProcess(u32, i32, u32) callconv(.winapi) HANDLE_;
extern "kernel32" fn TerminateProcess(HANDLE_, u32) callconv(.winapi) i32;

const pid_file = "qemu.pid";

fn vmDir(t: p.Target) []const u8 {
    return std.fs.path.dirname(t.disk) orelse ".";
}

fn sleepMs(q: *Qemu, ms: i64) void {
    std.Io.sleep(q.io, .fromMilliseconds(ms), .real) catch {};
}

fn execIn(q: *Qemu, arena: std.mem.Allocator, t: p.Target, gpa: std.mem.Allocator, script: []const u8) p.Error!p.GuestResult {
    if (q.ssh_exe.len == 0) return error.Unsupported;
    const access = guest.load(arena, q.io, vmDir(t)) catch return error.Unsupported;
    return guest.exec(gpa, q.io, q.ssh_exe, vmDir(t), access, script);
}

/// Starts the VM (window shown) and returns once the guest answers over SSH, so the caller can
/// run scripts immediately. Fails (and ends the VM it started) if the guest is not reachable in time.
/// Keeps a started VM alive across guest restarts. QEMU runs with -no-reboot (an in-place reset hangs
/// the BIOS under WHPX), so a restart ends the process; this thread notices the disk is no longer open
/// and launches QEMU again with the same arguments. `stop` ends it first, so an intentional stop is
/// never "repaired". A guest SHUTDOWN is indistinguishable from a restart here and is also relaunched.
const Supervisor = struct {
    q: *Qemu,
    arena: std.heap.ArenaAllocator,
    argv: []const []const u8,
    disk: []const u8,
    dir: []const u8,
    stop_flag: std.atomic.Value(bool) = .init(false),
    /// True from the moment QEMU is seen gone until the relaunched guest answers (for `waitReady`).
    restarting: std.atomic.Value(bool) = .init(false),
    relaunches: u32 = 0,
    thread: ?std.Thread = null,

    fn loop(self: *Supervisor) void {
        const q = self.q;
        while (!self.stop_flag.load(.acquire)) {
            sleepMs(q, 500);
            if (self.stop_flag.load(.acquire)) break;
            if (diskInUse(q.gpa, self.disk)) continue;
            // QEMU is gone and nobody asked it to stop: the guest restarted.
            if (self.relaunches >= 20) break;
            self.restarting.store(true, .release);
            self.relaunches += 1;
            _ = spawnQemu(q, self.argv, self.dir) catch {
                sleepMs(q, 5000);
                continue;
            };
            // Wait for the new process to open the disk before checking again (two QEMUs on one disk would corrupt it).
            var waited: i64 = 0;
            while (waited < 30_000 and !diskInUse(q.gpa, self.disk) and !self.stop_flag.load(.acquire)) : (waited += 250) sleepMs(q, 250);
        }
        self.restarting.store(false, .release);
    }
};

fn spawnQemu(q: *Qemu, argv: []const []const u8, dir: []const u8) !u32 {
    const child = try std.process.spawn(q.io, .{ .argv = argv, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore });
    const pid = GetProcessId(child.id);
    // Record the pid so a later stop can end this exact process if the guest will not shut down.
    var buf: [24]u8 = undefined;
    if (std.fmt.bufPrint(&buf, "{d}\n", .{pid})) |text| {
        if (std.Io.Dir.cwd().openDir(q.io, dir, .{})) |d| {
            var folder = d;
            defer folder.close(q.io);
            folder.writeFile(q.io, .{ .sub_path = pid_file, .data = text }) catch {};
        } else |_| {}
    } else |_| {}
    return pid;
}

fn startSupervisor(q: *Qemu, t: p.Target, argv: []const []const u8) void {
    const s = q.gpa.create(Supervisor) catch return;
    s.* = .{ .q = q, .arena = std.heap.ArenaAllocator.init(q.gpa), .argv = &.{}, .disk = "", .dir = "" };
    const a = s.arena.allocator();
    const copy = a.alloc([]const u8, argv.len) catch {
        s.arena.deinit();
        q.gpa.destroy(s);
        return;
    };
    for (argv, copy) |arg, *slot| slot.* = a.dupe(u8, arg) catch "";
    s.argv = copy;
    s.disk = a.dupe(u8, t.disk) catch "";
    s.dir = a.dupe(u8, vmDir(t)) catch "";
    s.thread = std.Thread.spawn(.{}, Supervisor.loop, .{s}) catch {
        s.arena.deinit();
        q.gpa.destroy(s);
        return;
    };
    q.sup = s;
}

fn stopSupervisor(q: *Qemu) void {
    const s = q.sup orelse return;
    s.stop_flag.store(true, .release);
    if (s.thread) |th| th.join();
    q.sup = null;
    s.arena.deinit();
    q.gpa.destroy(s);
}

/// Blocks until the guest answers over SSH, up to `timeout_s`. For after a guest restart, when the
/// supervisor is relaunching QEMU and a command would otherwise fail to connect. Never re-runs scripts.
pub fn waitReady(q: *Qemu, t: p.Target, timeout_s: u32) bool {
    var arena_state = std.heap.ArenaAllocator.init(q.gpa);
    defer arena_state.deinit();
    var waited: u32 = 0;
    while (waited <= timeout_s) : (waited += 5) {
        if (execIn(q, arena_state.allocator(), t, q.gpa, "exit 0")) |r| {
            q.gpa.free(r.output);
            return true;
        } else |_| {}
        sleepMs(q, 5000);
    }
    return false;
}

fn start(ptr: *anyopaque, t: p.Target) p.Error!void {
    const q = me(ptr);
    try safeDisk(t);
    try requireStopped(ptr, t);
    var arena_state = std.heap.ArenaAllocator.init(q.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    if (q.ssh_exe.len == 0) return error.Unsupported;
    const access = guest.load(arena, q.io, vmDir(t)) catch return error.Unsupported;
    const argv = buildArgv(arena, q.tools, .{
        .disk = t.disk,
        .memory_mb = t.memory_mb,
        .cpus = t.cpus,
        .accel = if (q.tools.whpx) .whpx else .tcg,
        .ssh_port = access.port,
        .cpu = access.cpu,
        .no_reboot = true,
    }) catch return error.OutOfMemory;
    _ = spawnQemu(q, argv, vmDir(t)) catch return error.ProviderFailed;

    // Wait for SSH (Windows boot + sshd), up to 6 minutes. A restart during this wait (Windows
    // sometimes restarts once while finishing setup) is handled by the supervisor started below.
    var waited: i64 = 0;
    while (waited < 360_000) : (waited += 5000) {
        sleepMs(q, 5000);
        if (execIn(q, arena, t, q.gpa, "exit 0")) |r| {
            q.gpa.free(r.output);
            startSupervisor(q, t, argv);
            return;
        } else |_| {}
    }
    hardStop(q, t);
    return error.ProviderFailed;
}

fn hardStop(q: *Qemu, t: p.Target) void {
    var arena_state = std.heap.ArenaAllocator.init(q.gpa);
    defer arena_state.deinit();
    const path = std.fs.path.join(arena_state.allocator(), &.{ vmDir(t), pid_file }) catch return;
    const text = std.Io.Dir.cwd().readFileAlloc(q.io, path, arena_state.allocator(), .limited(64)) catch return;
    const pid = std.fmt.parseInt(u32, std.mem.trim(u8, text, " \r\n"), 10) catch return;
    // PROCESS_TERMINATE | PROCESS_QUERY_LIMITED_INFORMATION
    const h = OpenProcess(0x0001 | 0x1000, 0, pid) orelse return;
    _ = TerminateProcess(h, 1);
    _ = CloseHandle(h);
}

/// Asks the guest to shut down, waits for QEMU to release the disk, and ends the process
/// if it does not. Safe to call on a VM that is already stopped.
fn stop(ptr: *anyopaque, t: p.Target) p.Error!void {
    const q = me(ptr);
    try safeDisk(t);
    // First end the supervisor, or it would relaunch the VM we are about to shut down.
    stopSupervisor(q);
    if (!diskInUse(q.gpa, t.disk)) return;
    var arena_state = std.heap.ArenaAllocator.init(q.gpa);
    defer arena_state.deinit();
    if (execIn(q, arena_state.allocator(), t, q.gpa, "shutdown /s /t 0")) |r| q.gpa.free(r.output) else |_| {}
    var waited: i64 = 0;
    while (waited < 180_000 and diskInUse(q.gpa, t.disk)) : (waited += 2000) sleepMs(q, 2000);
    if (diskInUse(q.gpa, t.disk)) {
        hardStop(q, t);
        waited = 0;
        while (waited < 20_000 and diskInUse(q.gpa, t.disk)) : (waited += 1000) sleepMs(q, 1000);
        if (diskInUse(q.gpa, t.disk)) return error.ProviderFailed;
    }
}
fn hasSnapshot(ptr: *anyopaque, t: p.Target, snap: []const u8) p.Error!bool {
    if (!p.validSnapshotName(snap)) return error.ProviderFailed;
    try safeDisk(t);
    const q = me(ptr);
    const out = try q.img(&.{ "snapshot", "-f", "qcow2", "-l", t.disk });
    defer q.gpa.free(out);
    var lines = std.mem.tokenizeAny(u8, out, "\r\n");
    while (lines.next()) |line| {
        var cols = std.mem.tokenizeAny(u8, line, " \t");
        _ = cols.next() orelse continue; // ID
        const tag = cols.next() orelse continue;
        if (std.mem.eql(u8, tag, snap)) return true;
    }
    return false;
}
fn createSnapshot(ptr: *anyopaque, t: p.Target, snap: []const u8) p.Error!void {
    if (!p.validSnapshotName(snap)) return error.ProviderFailed;
    try safeDisk(t);
    try requireStopped(ptr, t);
    if (try hasSnapshot(ptr, t, snap)) return error.SnapshotExists;
    const q = me(ptr);
    q.gpa.free(try q.img(&.{ "snapshot", "-f", "qcow2", "-c", snap, t.disk }));
}
fn restoreSnapshot(ptr: *anyopaque, t: p.Target, snap: []const u8) p.Error!void {
    if (!p.validSnapshotName(snap)) return error.ProviderFailed;
    try safeDisk(t);
    try requireStopped(ptr, t);
    if (!try hasSnapshot(ptr, t, snap)) return error.SnapshotNotFound;
    const q = me(ptr);
    q.gpa.free(try q.img(&.{ "snapshot", "-f", "qcow2", "-a", snap, t.disk }));
}
fn deleteSnapshot(ptr: *anyopaque, t: p.Target, snap: []const u8) p.Error!void {
    if (!p.validSnapshotName(snap)) return error.ProviderFailed;
    try safeDisk(t);
    try requireStopped(ptr, t);
    if (!try hasSnapshot(ptr, t, snap)) return error.SnapshotNotFound;
    const q = me(ptr);
    q.gpa.free(try q.img(&.{ "snapshot", "-f", "qcow2", "-d", snap, t.disk }));
}
fn waitReadyVt(ptr: *anyopaque, t: p.Target, timeout_s: u32) bool {
    return waitReady(me(ptr), t, timeout_s);
}
fn runInGuest(ptr: *anyopaque, gpa: std.mem.Allocator, t: p.Target, script: []const u8) p.Error!p.GuestResult {
    const q = me(ptr);
    var arena_state = std.heap.ArenaAllocator.init(q.gpa);
    defer arena_state.deinit();
    return execIn(q, arena_state.allocator(), t, gpa, script);
}

const vtable: p.Provider.VTable = .{
    .name = name,
    .capabilities = capabilities,
    .state = state,
    .start = start,
    .stop = stop,
    .hasSnapshot = hasSnapshot,
    .createSnapshot = createSnapshot,
    .restoreSnapshot = restoreSnapshot,
    .deleteSnapshot = deleteSnapshot,
    .runInGuest = runInGuest,
    .waitReady = waitReadyVt,
};

// ---- tests (need a real QEMU; reported as skipped, never as passed, if it is missing) ----

test "disk paths that look like options are refused" {
    try std.testing.expectError(error.ProviderFailed, safeDisk(.{ .id = "x", .name = "x", .disk = "-evil" }));
}

test "QEMU snapshots on a throwaway qcow2: create, list, change, restore, delete" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tools = (try discover(gpa, io, "", "")) orelse return error.SkipZigTest;
    defer tools.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(dir);
    const disk = try std.fmt.allocPrint(gpa, "{s}\\scratch.qcow2", .{dir});
    defer gpa.free(disk);

    const created = try std.process.run(gpa, io, .{ .argv = &.{ tools.qemu_img, "create", "-f", "qcow2", disk, "16M" } });
    defer gpa.free(created.stdout);
    defer gpa.free(created.stderr);
    try std.testing.expect(created.term == .exited and created.term.exited == 0);

    var q: Qemu = .{ .gpa = gpa, .io = io, .tools = &tools };
    const prov = q.provider();
    const target: p.Target = .{ .id = "scratch", .name = "scratch", .disk = disk };

    try std.testing.expect(prov.capabilities().snapshots);
    try std.testing.expect(!prov.capabilities().guest_exec);
    try std.testing.expectEqual(p.State.stopped, try prov.state(target));
    try std.testing.expect(!(try prov.hasSnapshot(target, "winlab-pre-test")));
    try prov.createSnapshot(target, "winlab-pre-test");
    try std.testing.expect(try prov.hasSnapshot(target, "winlab-pre-test"));
    try std.testing.expectError(error.SnapshotExists, prov.createSnapshot(target, "winlab-pre-test"));
    try prov.restoreSnapshot(target, "winlab-pre-test");
    try prov.deleteSnapshot(target, "winlab-pre-test");
    try std.testing.expect(!(try prov.hasSnapshot(target, "winlab-pre-test")));
    try std.testing.expectError(error.SnapshotNotFound, prov.restoreSnapshot(target, "winlab-pre-test"));
}

/// Runs `qemu-io -f qcow2 -c <cmd> <disk>` and reports whether it exited 0.
fn qemuIo(gpa: std.mem.Allocator, io: std.Io, tools: *const Tools, disk: []const u8, cmd: []const u8) !bool {
    const exe = try std.mem.replaceOwned(u8, gpa, tools.qemu_img, "qemu-img.exe", "qemu-io.exe");
    defer gpa.free(exe);
    const r = try std.process.run(gpa, io, .{ .argv = &.{ exe, "-f", "qcow2", "-c", cmd, disk } });
    defer gpa.free(r.stdout);
    defer gpa.free(r.stderr);
    return r.term == .exited and r.term.exited == 0;
}

test "restoring a snapshot really rolls the disk contents back" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tools = (try discover(gpa, io, "", "")) orelse return error.SkipZigTest;
    defer tools.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(dir);
    const disk = try std.fmt.allocPrint(gpa, "{s}\\data.qcow2", .{dir});
    defer gpa.free(disk);
    const created = try std.process.run(gpa, io, .{ .argv = &.{ tools.qemu_img, "create", "-f", "qcow2", disk, "16M" } });
    defer gpa.free(created.stdout);
    defer gpa.free(created.stderr);

    var q: Qemu = .{ .gpa = gpa, .io = io, .tools = &tools };
    const prov = q.provider();
    const target: p.Target = .{ .id = "data", .name = "data", .disk = disk };

    // Known data, snapshot, "lab changes" the data, restore, the original data is back.
    if (!(qemuIo(gpa, io, &tools, disk, "write -P 0xaa 0 4k") catch false)) return error.SkipZigTest; // qemu-io unavailable
    try prov.createSnapshot(target, "winlab-pre-data");
    try std.testing.expect(try qemuIo(gpa, io, &tools, disk, "write -P 0xbb 0 4k"));
    try std.testing.expect(try qemuIo(gpa, io, &tools, disk, "read -P 0xbb 0 4k"));
    try prov.restoreSnapshot(target, "winlab-pre-data");
    try std.testing.expect(try qemuIo(gpa, io, &tools, disk, "read -P 0xaa 0 4k"));
    try std.testing.expect(!(try qemuIo(gpa, io, &tools, disk, "read -P 0xbb 0 4k")));
    try prov.deleteSnapshot(target, "winlab-pre-data");
}

const HANDLE = ?*anyopaque;
extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*anyopaque, u32, u32, HANDLE) callconv(.winapi) HANDLE;
extern "kernel32" fn CloseHandle(HANDLE) callconv(.winapi) i32;
extern "kernel32" fn GetLastError() callconv(.winapi) u32;

/// True when some process has the disk image open. QEMU on Windows does NOT take the
/// image-level locks that make qemu-img refuse a busy image (verified: `qemu-img
/// snapshot -c` succeeded against a disk a running QEMU had open), so WinLab asks the
/// OS directly: opening with share mode 0 fails with a sharing violation while any
/// other handle exists. Unknown errors count as in use (fail safe).
pub fn diskInUse(gpa: std.mem.Allocator, path: []const u8) bool {
    const w = std.unicode.utf8ToUtf16LeAllocZ(gpa, path) catch return true;
    defer gpa.free(w);
    // GENERIC_READ, no sharing, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL
    const h = CreateFileW(w.ptr, 0x80000000, 0, null, 3, 0x80, null);
    if (h == @as(HANDLE, @ptrFromInt(std.math.maxInt(usize)))) {
        const err = GetLastError();
        return err != 2 and err != 3; // missing file/path is "not in use" (the caller reports it separately)
    }
    _ = CloseHandle(h);
    return false;
}

test "diskInUse notices an open handle and is false once it is closed" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "d.img", .data = "x" });
    const dir = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(dir);
    const path = try std.fmt.allocPrint(gpa, "{s}\\d.img", .{dir});
    defer gpa.free(path);
    try std.testing.expect(!diskInUse(gpa, path));
    {
        var f = try tmp.dir.openFile(io, "d.img", .{});
        defer f.close(io);
        try std.testing.expect(diskInUse(gpa, path));
    }
    try std.testing.expect(!diskInUse(gpa, path));
}

test "a disk held open by a running QEMU is reported running and is never modified" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tools = (try discover(gpa, io, "", "")) orelse return error.SkipZigTest;
    defer tools.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(dir);
    const disk = try std.fmt.allocPrint(gpa, "{s}\\live.qcow2", .{dir});
    defer gpa.free(disk);
    const created = try std.process.run(gpa, io, .{ .argv = &.{ tools.qemu_img, "create", "-f", "qcow2", disk, "16M" } });
    defer gpa.free(created.stdout);
    defer gpa.free(created.stderr);

    const drive = try std.fmt.allocPrint(gpa, "file={s},format=qcow2,if=none,id=d0", .{disk});
    defer gpa.free(drive);
    // Paused (-S), headless, no devices: a real QEMU process holding the disk, no guest OS involved.
    var child = try std.process.spawn(io, .{
        .argv = &.{ tools.qemu_system, "-S", "-display", "none", "-nodefaults", "-m", "64", "-drive", drive },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    var killed = false;
    defer if (!killed) child.kill(io);

    var q: Qemu = .{ .gpa = gpa, .io = io, .tools = &tools };
    const prov = q.provider();
    const target: p.Target = .{ .id = "live", .name = "live", .disk = disk };
    // Give QEMU a moment to open the image.
    var tries: u32 = 0;
    while (tries < 50 and !diskInUse(gpa, disk)) : (tries += 1) std.Io.sleep(io, .fromMilliseconds(100), .real) catch {};
    try std.testing.expectEqual(p.State.running, try prov.state(target));
    try std.testing.expectError(error.WrongState, prov.createSnapshot(target, "winlab-pre-live"));
    try std.testing.expectError(error.WrongState, prov.restoreSnapshot(target, "winlab-pre-live"));

    child.kill(io);
    killed = true;
    tries = 0;
    while (tries < 50 and diskInUse(gpa, disk)) : (tries += 1) std.Io.sleep(io, .fromMilliseconds(100), .real) catch {};
    try std.testing.expectEqual(p.State.stopped, try prov.state(target));
    try prov.createSnapshot(target, "winlab-pre-live");
    try prov.deleteSnapshot(target, "winlab-pre-live");
}

// ---- command line for a VM (pure; starting the process is the caller's job) ----

pub const Accel = enum { whpx, tcg };

pub const RunConfig = struct {
    disk: []const u8,
    memory_mb: u32 = 4096,
    cpus: u32 = 2,
    accel: Accel = .whpx,
    /// Installer ISO to attach (first boot device while set).
    iso: ?[]const u8 = null,
    /// ISO image attached as a second CD-ROM (holds Autounattend.xml and the first-logon script).
    answer_iso: ?[]const u8 = null,
    /// Show the guest's screen in a window; false runs headless.
    show_display: bool = true,
    /// Local-only control port for QMP (127.0.0.1). Null disables it.
    qmp_port: ?u16 = null,
    /// Forward 127.0.0.1:<port> on the host to the guest's SSH port (22). Local only.
    ssh_port: ?u16 = null,
    /// Exit QEMU on a guest restart instead of resetting in place (an in-place reset hangs the BIOS under WHPX).
    no_reboot: bool = false,
    /// CPU model (see guest.Access.cpu).
    cpu: []const u8 = "qemu64",
};

/// BIOS-boot Windows machine on driver-free virtual hardware (AHCI disk and CD, e1000e
/// network, USB tablet), so Windows Setup needs no extra drivers.
pub fn buildArgv(arena: std.mem.Allocator, tools: *const Tools, c: RunConfig) ![]const []const u8 {
    var a: std.ArrayList([]const u8) = .empty;
    try a.append(arena, tools.qemu_system);
    try a.appendSlice(arena, &.{ "-machine", "q35", "-accel", switch (c.accel) {
        .whpx => "whpx", // kernel-irqchip=off made the guest hang at the BIOS screen after the first reboot
        .tcg => "tcg",
    } });
    try a.appendSlice(arena, &.{ "-cpu", c.cpu });
    try a.appendSlice(arena, &.{ "-m", try std.fmt.allocPrint(arena, "{d}", .{c.memory_mb}) });
    try a.appendSlice(arena, &.{ "-smp", try std.fmt.allocPrint(arena, "{d}", .{c.cpus}) });
    try a.appendSlice(arena, &.{ "-device", "ich9-ahci,id=ahci" });
    try a.appendSlice(arena, &.{ "-drive", try std.fmt.allocPrint(arena, "file={s},format=qcow2,if=none,id=hd0", .{c.disk}) });
    // Disk first: a blank disk falls through to the installer, but once Windows is installed the
    // machine boots from the disk. (CD first left the guest stuck at the BIOS screen after the
    // first reboot, waiting for "press any key to boot from CD".)
    try a.appendSlice(arena, &.{ "-device", "ide-hd,drive=hd0,bus=ahci.0,bootindex=1" });
    if (c.iso) |iso| {
        try a.appendSlice(arena, &.{ "-drive", try std.fmt.allocPrint(arena, "file={s},media=cdrom,readonly=on,if=none,id=cd0", .{iso}) });
        try a.appendSlice(arena, &.{ "-device", "ide-cd,drive=cd0,bus=ahci.1,bootindex=2" });
    }
    if (c.answer_iso) |ans| {
        // A second, non-bootable CD-ROM: Windows Setup looks for Autounattend.xml on any CD/USB.
        try a.appendSlice(arena, &.{ "-drive", try std.fmt.allocPrint(arena, "file={s},media=cdrom,readonly=on,if=none,id=ans0", .{ans}) });
        try a.appendSlice(arena, &.{ "-device", "ide-cd,drive=ans0,bus=ahci.2" });
    }
    const netdev = if (c.ssh_port) |port|
        try std.fmt.allocPrint(arena, "user,id=net0,hostfwd=tcp:127.0.0.1:{d}-:22", .{port})
    else
        "user,id=net0";
    try a.appendSlice(arena, &.{ "-netdev", netdev, "-device", "e1000e,netdev=net0" });
    try a.appendSlice(arena, &.{ "-device", "qemu-xhci,id=xhci2", "-device", "usb-tablet,bus=xhci2.0" });
    try a.appendSlice(arena, &.{ "-vga", "std" });
    if (!c.show_display) try a.appendSlice(arena, &.{ "-display", "none" });
    if (c.qmp_port) |port| try a.appendSlice(arena, &.{ "-qmp", try std.fmt.allocPrint(arena, "tcp:127.0.0.1:{d},server,nowait", .{port}) });
    if (c.no_reboot) try a.append(arena, "-no-reboot");
    try a.appendSlice(arena, &.{ "-name", "winlab-vm" });
    return a.items;
}

test "command line is driver-free, local-only and carries the answer CD" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const tools: Tools = .{ .gpa = std.testing.allocator, .qemu_system = @constCast("C:/q/qemu-system-x86_64.exe"), .qemu_img = @constCast("x"), .version = @constCast("v"), .whpx = true };
    const argv = try buildArgv(arena.allocator(), &tools, .{ .disk = "D:/vm/a.qcow2", .iso = "D:/iso/s.iso", .answer_iso = "D:/ans.iso", .show_display = false, .qmp_port = 4444 });
    const joined = try std.mem.join(arena.allocator(), " ", argv);
    try std.testing.expect(std.mem.indexOf(u8, joined, "e1000e") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "virtio") == null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "D:/ans.iso") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "tcp:127.0.0.1:4444,server,nowait") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "-display none") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "bootindex=1") != null);
}

/// A free 127.0.0.1 TCP port. Windows reserves ranges for itself (WinNAT/Hyper-V keep moving
/// "excluded port ranges", and QEMU then fails with "Failed to bind socket"), so each candidate
/// is proven by actually listening on it for a moment.
pub fn pickLoopbackPort(io: std.Io) !u16 {
    var attempt: u32 = 0;
    while (attempt < 200) : (attempt += 1) {
        var rnd: [2]u8 = undefined;
        io.random(&rnd);
        const port: u16 = 20000 + std.mem.readInt(u16, &rnd, .little) % 29000; // below the dynamic range (49152+)
        const addr = std.Io.net.IpAddress.parseIp4("127.0.0.1", port) catch continue;
        var server = addr.listen(io, .{}) catch continue;
        server.deinit(io);
        return port;
    }
    return error.NoFreePort;
}

test "pickLoopbackPort returns a bindable port" {
    const port = try pickLoopbackPort(std.testing.io);
    try std.testing.expect(port >= 20000 and port < 49000);
}
