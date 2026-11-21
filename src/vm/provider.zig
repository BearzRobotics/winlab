//! The hypervisor-independent VM provider interface (decision record 0006).
//! Lab and safety logic depends only on this; QEMU and the in-memory mock
//! implement it. A provider states what it can do (`Capabilities`) and callers
//! must check before relying on a feature.
const std = @import("std");

/// A registered training target as a provider sees it.
pub const Target = struct {
    /// Stable id from vms.toml.
    id: []const u8,
    /// Display name shown to the learner.
    name: []const u8,
    /// Path of the primary disk image (identity for providers that use files).
    disk: []const u8,
    memory_mb: u32 = 4096,
    cpus: u32 = 2,
};

pub const State = enum { stopped, running };

pub const Capabilities = struct {
    /// Can create, list, restore and delete snapshots of a stopped VM.
    snapshots: bool = false,
    /// Can start and stop the VM.
    power: bool = false,
    /// Can run commands inside the guest and read the result.
    guest_exec: bool = false,
    /// Hardware acceleration is available (informational).
    accelerated: bool = false,
};

pub const GuestResult = struct {
    exit_code: u32,
    /// Owned by the caller's allocator.
    output: []u8,
};

pub const Error = error{
    /// The provider does not have this capability.
    Unsupported,
    /// The operation needs the VM to be stopped (or running).
    WrongState,
    SnapshotNotFound,
    SnapshotExists,
    ProviderFailed,
    OutOfMemory,
};

pub const Provider = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        name: *const fn (ptr: *anyopaque) []const u8,
        capabilities: *const fn (ptr: *anyopaque) Capabilities,
        state: *const fn (ptr: *anyopaque, t: Target) Error!State,
        start: *const fn (ptr: *anyopaque, t: Target) Error!void,
        stop: *const fn (ptr: *anyopaque, t: Target) Error!void,
        hasSnapshot: *const fn (ptr: *anyopaque, t: Target, snap: []const u8) Error!bool,
        createSnapshot: *const fn (ptr: *anyopaque, t: Target, snap: []const u8) Error!void,
        restoreSnapshot: *const fn (ptr: *anyopaque, t: Target, snap: []const u8) Error!void,
        deleteSnapshot: *const fn (ptr: *anyopaque, t: Target, snap: []const u8) Error!void,
        runInGuest: *const fn (ptr: *anyopaque, gpa: std.mem.Allocator, t: Target, script: []const u8) Error!GuestResult,
        waitReady: *const fn (ptr: *anyopaque, t: Target, timeout_s: u32) bool,
    };

    pub fn name(self: Provider) []const u8 {
        return self.vtable.name(self.ptr);
    }
    pub fn capabilities(self: Provider) Capabilities {
        return self.vtable.capabilities(self.ptr);
    }
    pub fn state(self: Provider, t: Target) Error!State {
        return self.vtable.state(self.ptr, t);
    }
    pub fn start(self: Provider, t: Target) Error!void {
        return self.vtable.start(self.ptr, t);
    }
    /// Stops the VM (a hard stop is acceptable: lab rollback restores a snapshot anyway).
    pub fn stop(self: Provider, t: Target) Error!void {
        return self.vtable.stop(self.ptr, t);
    }
    pub fn hasSnapshot(self: Provider, t: Target, snap: []const u8) Error!bool {
        return self.vtable.hasSnapshot(self.ptr, t, snap);
    }
    pub fn createSnapshot(self: Provider, t: Target, snap: []const u8) Error!void {
        return self.vtable.createSnapshot(self.ptr, t, snap);
    }
    pub fn restoreSnapshot(self: Provider, t: Target, snap: []const u8) Error!void {
        return self.vtable.restoreSnapshot(self.ptr, t, snap);
    }
    pub fn deleteSnapshot(self: Provider, t: Target, snap: []const u8) Error!void {
        return self.vtable.deleteSnapshot(self.ptr, t, snap);
    }
    /// Blocks until the guest answers (it may be restarting), up to `timeout_s`. Never runs anything in the guest.
    pub fn waitReady(self: Provider, t: Target, timeout_s: u32) bool {
        return self.vtable.waitReady(self.ptr, t, timeout_s);
    }
    pub fn runInGuest(self: Provider, gpa: std.mem.Allocator, t: Target, script: []const u8) Error!GuestResult {
        return self.vtable.runInGuest(self.ptr, gpa, t, script);
    }
};

/// Snapshot names are used on command lines and in files, so they are restricted.
pub fn validSnapshotName(s: []const u8) bool {
    if (s.len == 0 or s.len > 64) return false;
    if (s[0] == '-') return false; // would read as an option on a command line
    for (s) |c| switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '_', '.' => {},
        else => return false,
    };
    return true;
}

test "snapshot name validation" {
    try std.testing.expect(validSnapshotName("winlab-pre-lab.one_1"));
    try std.testing.expect(!validSnapshotName(""));
    try std.testing.expect(!validSnapshotName("bad name"));
    try std.testing.expect(!validSnapshotName("a;b"));
    try std.testing.expect(!validSnapshotName("-delete"));
}
