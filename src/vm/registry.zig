//! Registered VMs (%APPDATA%\WinLab\vms.toml). A VM is usable by labs only when
//! it is listed here with `training_target = true`; nothing is inferred, and the
//! current host can never be registered as a target (decision record 0006).
const std = @import("std");
const toml = @import("toml");
const provider = @import("provider.zig");

pub const sub_dir = "WinLab";
pub const file_name = "vms.toml";
const sub_path = sub_dir ++ "/" ++ file_name;
const max_bytes = 256 * 1024;
pub const schema_version = 1;

pub const Vm = struct {
    id: []const u8,
    name: []const u8,
    /// Provider key, for example "qemu".
    provider: []const u8,
    disk: []const u8,
    memory_mb: u32 = 4096,
    cpus: u32 = 2,
    /// The learner's explicit statement that this VM may be changed and rolled back.
    training_target: bool = false,

    pub fn target(self: Vm) provider.Target {
        return .{ .id = self.id, .name = self.name, .disk = self.disk, .memory_mb = self.memory_mb, .cpus = self.cpus };
    }
};

pub const Registry = struct {
    arena: std.heap.ArenaAllocator,
    vms: []Vm,

    pub fn deinit(self: *Registry) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn find(self: *const Registry, id: []const u8) ?Vm {
        for (self.vms) |v| {
            if (std.mem.eql(u8, v.id, id)) return v;
        }
        return null;
    }
};

pub const ParseError = error{ InvalidToml, UnsupportedSchema, InvalidEntry, DuplicateId, OutOfMemory };

pub fn validId(s: []const u8) bool {
    if (s.len == 0 or s.len > 48) return false;
    for (s, 0..) |c, i| switch (c) {
        'a'...'z', '0'...'9' => {},
        '-' => if (i == 0 or i == s.len - 1) return false,
        else => return false,
    };
    return true;
}

pub fn parse(gpa: std.mem.Allocator, text: []const u8) ParseError!Registry {
    var doc = toml.Document.parse(gpa, text, .{}, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidToml,
    };
    defer doc.deinit();
    const v = doc.root.getInt("schema_version") orelse return error.UnsupportedSchema;
    if (v != schema_version) return error.UnsupportedSchema;

    var reg: Registry = .{ .arena = std.heap.ArenaAllocator.init(gpa), .vms = &.{} };
    errdefer reg.arena.deinit();
    const a = reg.arena.allocator();
    const arr = doc.root.getArray("vm") orelse return reg;
    const out = try a.alloc(Vm, arr.items.items.len);
    for (arr.items.items, out, 0..) |item, *slot, i| {
        const t = switch (item) {
            .table => |t| t,
            else => return error.InvalidEntry,
        };
        const id = t.getString("id") orelse return error.InvalidEntry;
        if (!validId(id)) return error.InvalidEntry;
        for (out[0..i]) |prev| {
            if (std.mem.eql(u8, prev.id, id)) return error.DuplicateId;
        }
        const disk = t.getString("disk") orelse return error.InvalidEntry;
        const prov = t.getString("provider") orelse return error.InvalidEntry;
        if (disk.len == 0 or prov.len == 0) return error.InvalidEntry;
        const mem = t.getInt("memory_mb") orelse 4096;
        const cpus = t.getInt("cpus") orelse 2;
        if (mem < 512 or mem > 1024 * 1024 or cpus < 1 or cpus > 256) return error.InvalidEntry;
        slot.* = .{
            .id = try a.dupe(u8, id),
            .name = try a.dupe(u8, t.getString("name") orelse id),
            .provider = try a.dupe(u8, prov),
            .disk = try a.dupe(u8, disk),
            .memory_mb = @intCast(mem),
            .cpus = @intCast(cpus),
            .training_target = t.getBool("training_target") orelse false,
        };
    }
    reg.vms = out;
    return reg;
}

fn writeQuoted(w: *std.Io.Writer, s: []const u8) std.Io.Writer.Error!void {
    try w.writeByte('"');
    for (s) |c| switch (c) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        0...31, 127 => try w.print("\\u{x:0>4}", .{c}),
        else => try w.writeByte(c),
    };
    try w.writeByte('"');
}

pub fn write(vms: []const Vm, w: *std.Io.Writer) std.Io.Writer.Error!void {
    try w.print("schema_version = {d}\n", .{schema_version});
    for (vms) |v| {
        try w.writeAll("\n[[vm]]\nid = ");
        try writeQuoted(w, v.id);
        try w.writeAll("\nname = ");
        try writeQuoted(w, v.name);
        try w.writeAll("\nprovider = ");
        try writeQuoted(w, v.provider);
        try w.writeAll("\ndisk = ");
        try writeQuoted(w, v.disk);
        try w.print("\nmemory_mb = {d}\ncpus = {d}\ntraining_target = {}\n", .{ v.memory_mb, v.cpus, v.training_target });
    }
}

pub fn load(gpa: std.mem.Allocator, io: std.Io, base: std.Io.Dir) !Registry {
    const text = base.readFileAlloc(io, sub_path, gpa, .limited(max_bytes)) catch |err| switch (err) {
        error.FileNotFound => return parse(gpa, "schema_version = 1\n"),
        else => return err,
    };
    defer gpa.free(text);
    return parse(gpa, text);
}

pub fn save(gpa: std.mem.Allocator, io: std.Io, base: std.Io.Dir, vms: []const Vm) !void {
    var body: std.Io.Writer.Allocating = .init(gpa);
    defer body.deinit();
    try write(vms, &body.writer);
    var atomic = try base.createFileAtomic(io, sub_path, .{ .make_path = true, .replace = true });
    defer atomic.deinit(io);
    var fw: std.Io.File.Writer = .init(atomic.file, io, &.{});
    try fw.interface.writeAll(body.written());
    try fw.interface.flush();
    try atomic.replace(io);
}

test "round trip and lookup" {
    const gpa = std.testing.allocator;
    const vms = [_]Vm{
        .{ .id = "win11-lab", .name = "Win11 \"lab\"", .provider = "qemu", .disk = "D:\\vm\\win11.qcow2", .training_target = true },
        .{ .id = "other", .name = "Other", .provider = "qemu", .disk = "D:\\vm\\o.qcow2", .memory_mb = 8192, .cpus = 4 },
    };
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try write(&vms, &out.writer);
    var r = try parse(gpa, out.written());
    defer r.deinit();
    try std.testing.expectEqual(@as(usize, 2), r.vms.len);
    const v = r.find("win11-lab").?;
    try std.testing.expect(v.training_target);
    try std.testing.expectEqualStrings("Win11 \"lab\"", v.name);
    try std.testing.expect(!r.find("other").?.training_target);
    try std.testing.expectEqual(@as(u32, 8192), r.find("other").?.memory_mb);
    try std.testing.expect(r.find("missing") == null);
}

test "unregistered means not a training target by default" {
    var r = try parse(std.testing.allocator,
        \\schema_version = 1
        \\[[vm]]
        \\id = "a"
        \\provider = "qemu"
        \\disk = "x.qcow2"
        \\
    );
    defer r.deinit();
    try std.testing.expect(!r.find("a").?.training_target);
}

test "bad files are errors" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.UnsupportedSchema, parse(gpa, ""));
    try std.testing.expectError(error.InvalidToml, parse(gpa, "x = \n"));
    try std.testing.expectError(error.InvalidEntry, parse(gpa, "schema_version = 1\n[[vm]]\nid = \"Bad ID\"\nprovider = \"qemu\"\ndisk = \"x\"\n"));
    try std.testing.expectError(error.DuplicateId, parse(gpa, "schema_version = 1\n[[vm]]\nid = \"a\"\nprovider = \"q\"\ndisk = \"x\"\n[[vm]]\nid = \"a\"\nprovider = \"q\"\ndisk = \"y\"\n"));
}

test "save and load through a directory; missing file is empty" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var empty = try load(gpa, io, tmp.dir);
    try std.testing.expectEqual(@as(usize, 0), empty.vms.len);
    empty.deinit();
    try save(gpa, io, tmp.dir, &.{.{ .id = "v", .name = "V", .provider = "qemu", .disk = "d.qcow2", .training_target = true }});
    var r = try load(gpa, io, tmp.dir);
    defer r.deinit();
    try std.testing.expect(r.find("v").?.training_target);
}
