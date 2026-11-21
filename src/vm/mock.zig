//! In-memory provider for tests (AGENTS.md: mocks for anything that does not need
//! a hypervisor). Guest state is a key/value map; snapshots copy it and restore
//! puts it back, so tests can prove that a reset really undoes a lab.
//!
//! Guest "scripts" are lines of: `set KEY=VALUE`, `del KEY`, `get KEY` (prints the
//! value) and `exit N`. Anything else is an error with exit code 127.
const std = @import("std");
const p = @import("provider.zig");

pub const Mock = struct {
    gpa: std.mem.Allocator,
    caps: p.Capabilities = .{ .snapshots = true, .guest_exec = true, .power = true },
    running: bool = false,
    guest: std.StringArrayHashMapUnmanaged([]const u8) = .empty,
    snapshots: std.StringArrayHashMapUnmanaged(std.StringArrayHashMapUnmanaged([]const u8)) = .empty,
    /// Fault injection.
    fail_create: bool = false,
    fail_restore: bool = false,
    fail_exec: bool = false,
    /// Counts calls for assertions.
    restores: u32 = 0,

    pub fn init(gpa: std.mem.Allocator) Mock {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Mock) void {
        freeMap(self.gpa, &self.guest);
        for (self.snapshots.keys(), self.snapshots.values()) |k, *v| {
            self.gpa.free(k);
            freeMap(self.gpa, v);
        }
        self.snapshots.deinit(self.gpa);
    }

    pub fn provider(self: *Mock) p.Provider {
        return .{ .ptr = self, .vtable = &vtable };
    }

    pub fn get(self: *const Mock, key: []const u8) ?[]const u8 {
        return self.guest.get(key);
    }

    pub fn put(self: *Mock, key: []const u8, value: []const u8) !void {
        try putMap(self.gpa, &self.guest, key, value);
    }
};

fn freeMap(gpa: std.mem.Allocator, m: *std.StringArrayHashMapUnmanaged([]const u8)) void {
    for (m.keys(), m.values()) |k, v| {
        gpa.free(k);
        gpa.free(v);
    }
    m.deinit(gpa);
    m.* = .empty;
}

fn putMap(gpa: std.mem.Allocator, m: *std.StringArrayHashMapUnmanaged([]const u8), key: []const u8, value: []const u8) !void {
    const v = try gpa.dupe(u8, value);
    errdefer gpa.free(v);
    const gop = try m.getOrPut(gpa, key);
    if (gop.found_existing) {
        gpa.free(gop.value_ptr.*);
    } else {
        gop.key_ptr.* = gpa.dupe(u8, key) catch |e| {
            _ = m.swapRemove(key);
            return e;
        };
    }
    gop.value_ptr.* = v;
}

fn cloneMap(gpa: std.mem.Allocator, src: *const std.StringArrayHashMapUnmanaged([]const u8)) !std.StringArrayHashMapUnmanaged([]const u8) {
    var out: std.StringArrayHashMapUnmanaged([]const u8) = .empty;
    errdefer freeMap(gpa, &out);
    for (src.keys(), src.values()) |k, v| try putMap(gpa, &out, k, v);
    return out;
}

fn self_(ptr: *anyopaque) *Mock {
    return @ptrCast(@alignCast(ptr));
}

fn name(_: *anyopaque) []const u8 {
    return "mock";
}
fn capabilities(ptr: *anyopaque) p.Capabilities {
    return self_(ptr).caps;
}
fn state(ptr: *anyopaque, _: p.Target) p.Error!p.State {
    return if (self_(ptr).running) .running else .stopped;
}
fn start(ptr: *anyopaque, _: p.Target) p.Error!void {
    const m = self_(ptr);
    if (!m.caps.power) return error.Unsupported;
    if (m.running) return error.WrongState;
    m.running = true;
}
fn stop(ptr: *anyopaque, _: p.Target) p.Error!void {
    const m = self_(ptr);
    if (!m.caps.power) return error.Unsupported;
    m.running = false;
}
fn hasSnapshot(ptr: *anyopaque, _: p.Target, snap: []const u8) p.Error!bool {
    return self_(ptr).snapshots.contains(snap);
}
fn createSnapshot(ptr: *anyopaque, _: p.Target, snap: []const u8) p.Error!void {
    const m = self_(ptr);
    if (!m.caps.snapshots) return error.Unsupported;
    if (m.running) return error.WrongState;
    if (m.fail_create) return error.ProviderFailed;
    if (m.snapshots.contains(snap)) return error.SnapshotExists;
    var copy = cloneMap(m.gpa, &m.guest) catch return error.OutOfMemory;
    errdefer freeMap(m.gpa, &copy);
    const key = m.gpa.dupe(u8, snap) catch return error.OutOfMemory;
    errdefer m.gpa.free(key);
    m.snapshots.put(m.gpa, key, copy) catch return error.OutOfMemory;
}
fn restoreSnapshot(ptr: *anyopaque, _: p.Target, snap: []const u8) p.Error!void {
    const m = self_(ptr);
    if (!m.caps.snapshots) return error.Unsupported;
    if (m.running) return error.WrongState;
    if (m.fail_restore) return error.ProviderFailed;
    const saved = m.snapshots.getPtr(snap) orelse return error.SnapshotNotFound;
    const copy = cloneMap(m.gpa, saved) catch return error.OutOfMemory;
    freeMap(m.gpa, &m.guest);
    m.guest = copy;
    m.restores += 1;
}
fn deleteSnapshot(ptr: *anyopaque, _: p.Target, snap: []const u8) p.Error!void {
    const m = self_(ptr);
    if (!m.caps.snapshots) return error.Unsupported;
    const kv = m.snapshots.fetchSwapRemove(snap) orelse return error.SnapshotNotFound;
    m.gpa.free(kv.key);
    var v = kv.value;
    freeMap(m.gpa, &v);
}
fn runInGuest(ptr: *anyopaque, gpa: std.mem.Allocator, _: p.Target, script: []const u8) p.Error!p.GuestResult {
    const m = self_(ptr);
    if (!m.caps.guest_exec) return error.Unsupported;
    if (m.fail_exec) return error.ProviderFailed;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var code: u32 = 0;
    var lines = std.mem.tokenizeAny(u8, script, "\r\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "set ")) {
            const kv = line[4..];
            const eq = std.mem.indexOfScalar(u8, kv, '=') orelse {
                code = 127;
                break;
            };
            m.put(kv[0..eq], kv[eq + 1 ..]) catch return error.OutOfMemory;
        } else if (std.mem.startsWith(u8, line, "del ")) {
            if (m.guest.fetchSwapRemove(line[4..])) |kv| {
                m.gpa.free(kv.key);
                m.gpa.free(kv.value);
            }
        } else if (std.mem.startsWith(u8, line, "get ")) {
            out.appendSlice(gpa, m.guest.get(line[4..]) orelse "") catch return error.OutOfMemory;
            out.append(gpa, '\n') catch return error.OutOfMemory;
        } else if (std.mem.startsWith(u8, line, "exit ")) {
            code = std.fmt.parseInt(u32, line[5..], 10) catch 127;
            break;
        } else {
            code = 127;
            break;
        }
    }
    return .{ .exit_code = code, .output = out.toOwnedSlice(gpa) catch return error.OutOfMemory };
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
    .waitReady = waitReady,
};

const test_target: p.Target = .{ .id = "vm1", .name = "Test VM", .disk = "x.qcow2" };

test "snapshot then restore undoes guest changes" {
    const gpa = std.testing.allocator;
    var m = Mock.init(gpa);
    defer m.deinit();
    const prov = m.provider();
    try m.put("svc.Spooler", "running");
    try prov.createSnapshot(test_target, "before");
    const r = try prov.runInGuest(gpa, test_target, "set svc.Spooler=stopped\nset extra=1\nget svc.Spooler");
    defer gpa.free(r.output);
    try std.testing.expectEqualStrings("stopped\n", r.output);
    try prov.restoreSnapshot(test_target, "before");
    try std.testing.expectEqualStrings("running", m.get("svc.Spooler").?);
    try std.testing.expect(m.get("extra") == null);
}

test "wrong state and duplicate names are refused" {
    const gpa = std.testing.allocator;
    var m = Mock.init(gpa);
    defer m.deinit();
    const prov = m.provider();
    try prov.createSnapshot(test_target, "s");
    try std.testing.expectError(error.SnapshotExists, prov.createSnapshot(test_target, "s"));
    m.running = true;
    try std.testing.expectError(error.WrongState, prov.restoreSnapshot(test_target, "s"));
    try std.testing.expectError(error.SnapshotNotFound, blk: {
        m.running = false;
        break :blk prov.restoreSnapshot(test_target, "nope");
    });
}

test "capabilities gate features" {
    const gpa = std.testing.allocator;
    var m = Mock.init(gpa);
    defer m.deinit();
    m.caps = .{};
    try std.testing.expectError(error.Unsupported, m.provider().createSnapshot(test_target, "s"));
    try std.testing.expectError(error.Unsupported, m.provider().runInGuest(gpa, test_target, "exit 0"));
}

fn waitReady(ptr: *anyopaque, _: p.Target, _: u32) bool {
    return self_(ptr).running;
}
