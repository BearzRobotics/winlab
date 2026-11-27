//! Which of a VM's disk states must only ever boot with an isolated network.
//!
//! A lab that runs something hostile asks for an isolated network. That request has to follow the disk, not just
//! the one call that made it: the same state can be booted again by another command, or saved in a snapshot and
//! restored later. So each VM folder keeps a small record:
//!   - whether the disk's CURRENT state has been booted isolated;
//!   - which snapshots were taken from such a state.
//! It fails closed: a record that exists but cannot be read means "isolated".
const std = @import("std");

pub const file_name = "isolation.txt";
const header = "winlab-isolation 1";
const footer = "end";
const max_bytes = 64 * 1024;

pub const Error = error{ IsolationRecord, OutOfMemory };

const Record = struct {
    /// The record exists but is damaged: everything counts as isolated, and it is never overwritten.
    damaged: bool = false,
    current: bool = false,
    snapshots: std.ArrayList([]const u8) = .empty,

    fn indexOf(self: *const Record, snap: []const u8) ?usize {
        for (self.snapshots.items, 0..) |s, i| if (std.mem.eql(u8, s, snap)) return i;
        return null;
    }
};

fn parse(arena: std.mem.Allocator, text: []const u8) Error!Record {
    var r: Record = .{};
    var lines = std.mem.tokenizeAny(u8, text, "\r\n");
    const first = lines.next() orelse return .{ .damaged = true };
    if (!std.mem.eql(u8, first, header)) return .{ .damaged = true };
    var saw_current = false;
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, footer)) {
            if (!saw_current or lines.next() != null) return .{ .damaged = true };
            return r;
        } else if (std.mem.eql(u8, line, "current=isolated") or std.mem.eql(u8, line, "current=open")) {
            r.current = std.mem.endsWith(u8, line, "isolated");
            saw_current = true;
        } else if (std.mem.startsWith(u8, line, "snapshot=")) {
            try r.snapshots.append(arena, line["snapshot=".len..]);
        } else return .{ .damaged = true };
    }
    return .{ .damaged = true }; // no end line: a half-written record
}

fn load(arena: std.mem.Allocator, io: std.Io, vm_dir: []const u8) Error!Record {
    const path = std.fs.path.join(arena, &.{ vm_dir, file_name }) catch return error.OutOfMemory;
    const text = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_bytes)) catch |e| switch (e) {
        error.FileNotFound => return .{},
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .damaged = true },
    };
    return parse(arena, text);
}

fn save(arena: std.mem.Allocator, io: std.Io, vm_dir: []const u8, r: *const Record) Error!void {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, header ++ "\n");
    try out.appendSlice(arena, if (r.current) "current=isolated\n" else "current=open\n");
    for (r.snapshots.items) |s| {
        try out.appendSlice(arena, "snapshot=");
        try out.appendSlice(arena, s);
        try out.append(arena, '\n');
    }
    try out.appendSlice(arena, footer ++ "\n");
    var dir = std.Io.Dir.cwd().openDir(io, vm_dir, .{}) catch return error.IsolationRecord;
    defer dir.close(io);
    dir.writeFile(io, .{ .sub_path = file_name, .data = out.items }) catch return error.IsolationRecord;
}

/// Must the disk, as it is now, boot with an isolated network?
pub fn currentIsolated(gpa: std.mem.Allocator, io: std.Io, vm_dir: []const u8) bool {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const r = load(arena.allocator(), io, vm_dir) catch return true;
    return r.damaged or r.current;
}

/// Call BEFORE booting a VM isolated. If this fails, do not boot.
pub fn markCurrent(gpa: std.mem.Allocator, io: std.Io, vm_dir: []const u8) Error!void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var r = try load(arena.allocator(), io, vm_dir);
    if (r.damaged or r.current) return; // already counts as isolated
    r.current = true;
    try save(arena.allocator(), io, vm_dir, &r);
}

/// Call BEFORE creating snapshot `snap`: a snapshot of an isolated state is itself isolated.
pub fn beforeCreate(gpa: std.mem.Allocator, io: std.Io, vm_dir: []const u8, snap: []const u8) Error!void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var r = try load(arena.allocator(), io, vm_dir);
    if (r.damaged or !r.current or r.indexOf(snap) != null) return;
    try r.snapshots.append(arena.allocator(), snap);
    try save(arena.allocator(), io, vm_dir, &r);
}

/// Call AFTER snapshot `snap` was created: forgets an old mark of the same name if this one is not isolated.
pub fn afterCreate(gpa: std.mem.Allocator, io: std.Io, vm_dir: []const u8, snap: []const u8) Error!void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var r = try load(arena.allocator(), io, vm_dir);
    if (r.damaged or r.current) return;
    const i = r.indexOf(snap) orelse return;
    _ = r.snapshots.orderedRemove(i);
    try save(arena.allocator(), io, vm_dir, &r);
}

/// Call BEFORE restoring `snap`: if it is isolated, the disk counts as isolated even if the restore half-fails.
pub fn beforeRestore(gpa: std.mem.Allocator, io: std.Io, vm_dir: []const u8, snap: []const u8) Error!void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var r = try load(arena.allocator(), io, vm_dir);
    if (r.damaged or r.current or r.indexOf(snap) == null) return;
    r.current = true;
    try save(arena.allocator(), io, vm_dir, &r);
}

/// Call AFTER `snap` was restored successfully: only now may the isolation be lifted.
pub fn afterRestore(gpa: std.mem.Allocator, io: std.Io, vm_dir: []const u8, snap: []const u8) Error!void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var r = try load(arena.allocator(), io, vm_dir);
    const isolated = r.indexOf(snap) != null;
    if (r.damaged or r.current == isolated) return;
    r.current = isolated;
    try save(arena.allocator(), io, vm_dir, &r);
}

/// Call AFTER snapshot `snap` was deleted.
pub fn afterDelete(gpa: std.mem.Allocator, io: std.Io, vm_dir: []const u8, snap: []const u8) Error!void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var r = try load(arena.allocator(), io, vm_dir);
    if (r.damaged) return;
    const i = r.indexOf(snap) orelse return;
    _ = r.snapshots.orderedRemove(i);
    try save(arena.allocator(), io, vm_dir, &r);
}

test "isolation follows the disk state through snapshots" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(dir);

    // No record: an ordinary VM.
    try std.testing.expect(!currentIsolated(gpa, io, dir));
    try beforeCreate(gpa, io, dir, "clean");
    try afterCreate(gpa, io, dir, "clean");

    // An isolated boot marks the disk; a snapshot taken from it is marked too.
    try markCurrent(gpa, io, dir);
    try std.testing.expect(currentIsolated(gpa, io, dir));
    try beforeCreate(gpa, io, dir, "hostile");
    try afterCreate(gpa, io, dir, "hostile");

    // Back to clean lifts it, but only once the restore has succeeded.
    try beforeRestore(gpa, io, dir, "clean");
    try std.testing.expect(currentIsolated(gpa, io, dir));
    try afterRestore(gpa, io, dir, "clean");
    try std.testing.expect(!currentIsolated(gpa, io, dir));

    // Restoring the hostile snapshot isolates again, already before the restore runs.
    try beforeRestore(gpa, io, dir, "hostile");
    try std.testing.expect(currentIsolated(gpa, io, dir));
    try afterRestore(gpa, io, dir, "hostile");
    try std.testing.expect(currentIsolated(gpa, io, dir));

    // Re-using a deleted snapshot's name for a clean state does not inherit the mark.
    try afterRestore(gpa, io, dir, "clean");
    try afterDelete(gpa, io, dir, "hostile");
    try beforeCreate(gpa, io, dir, "hostile");
    try afterCreate(gpa, io, dir, "hostile");
    try beforeRestore(gpa, io, dir, "hostile");
    try std.testing.expect(!currentIsolated(gpa, io, dir));
}

test "a damaged or half-written isolation record means isolated, and is left alone" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(dir);
    for ([_][]const u8{ "", "garbage", header ++ "\ncurrent=open\n", header ++ "\nend\n", header ++ "\ncurrent=open\nnonsense\nend\n" }) |text| {
        try tmp.dir.writeFile(io, .{ .sub_path = file_name, .data = text });
        try std.testing.expect(currentIsolated(gpa, io, dir));
        try afterRestore(gpa, io, dir, "clean");
        try std.testing.expect(currentIsolated(gpa, io, dir));
    }
}
