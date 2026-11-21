//! A tiny ISO 9660 (level 2, no extensions) image builder, used to hand an answer
//! file and first-logon script to Windows Setup as an ordinary CD-ROM. A virtual
//! USB drive made from a host folder (QEMU vvfat) sometimes left SeaBIOS spinning
//! forever after Setup's first reboot, so the answer media is now a plain CD.
//!
//! The image has a single flat root directory. File names are upper-cased and get
//! ";1"; allowed characters are A-Z 0-9 '_' and '.', which keeps the result valid
//! for any reader. Pure: builds bytes in memory.
const std = @import("std");

pub const File = struct {
    /// Name as the guest should see it, for example "Autounattend.xml".
    name: []const u8,
    data: []const u8,
};

pub const Error = error{ InvalidName, TooManyFiles, TooLarge, OutOfMemory };

const sector = 2048;
const root_lba = 20;
const first_file_lba = 21;
/// One directory sector holds ~40 short entries; keep well inside it.
const max_files = 24;

fn le32(buf: []u8, v: u32) void {
    std.mem.writeInt(u32, buf[0..4], v, .little);
}
fn be32(buf: []u8, v: u32) void {
    std.mem.writeInt(u32, buf[0..4], v, .big);
}
fn both32(buf: []u8, v: u32) void {
    le32(buf[0..4], v);
    be32(buf[4..8], v);
}
fn both16(buf: []u8, v: u16) void {
    std.mem.writeInt(u16, buf[0..2], v, .little);
    std.mem.writeInt(u16, buf[2..4], v, .big);
}

fn validDChars(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| switch (c) {
        'A'...'Z', '0'...'9', '_', '.', '-' => {}, // '-' is outside strict ISO 9660 but needed for cloud-init's user-data/meta-data and read fine everywhere
        else => return false,
    };
    return true;
}

/// The file identifier ("NAME.EXT;1") for `name`, upper-cased, into `out`.
fn fileId(name: []const u8, out: *[34]u8) Error![]const u8 {
    if (name.len == 0 or name.len > 28) return error.InvalidName;
    var n: usize = 0;
    for (name) |c| {
        out[n] = std.ascii.toUpper(c);
        n += 1;
    }
    if (!validDChars(out[0..n])) return error.InvalidName;
    out[n] = ';';
    out[n + 1] = '1';
    return out[0 .. n + 2];
}

fn dirRecord(buf: []u8, lba: u32, size: u32, is_dir: bool, id: []const u8) usize {
    const pad: usize = if (id.len % 2 == 0) 1 else 0;
    const len = 33 + id.len + pad;
    @memset(buf[0..len], 0);
    buf[0] = @intCast(len);
    both32(buf[2..10], lba);
    both32(buf[10..18], size);
    // Recording date: 2026-11-08 00:00:00, GMT offset 0 (fixed so the image is reproducible).
    buf[18] = 126;
    buf[19] = 11;
    buf[20] = 8;
    buf[25] = if (is_dir) 2 else 0;
    both16(buf[28..32], 1);
    buf[32] = @intCast(id.len);
    @memcpy(buf[33 .. 33 + id.len], id);
    return len;
}

pub fn build(gpa: std.mem.Allocator, volume_id: []const u8, files: []const File) Error![]u8 {
    if (files.len > max_files) return error.TooManyFiles;
    if (!validDChars(volume_id) or volume_id.len > 32) return error.InvalidName;

    // Lay out file extents after the root directory, sector aligned.
    var total_sectors: usize = first_file_lba;
    var lbas: [max_files]u32 = undefined;
    for (files, 0..) |f, i| {
        lbas[i] = @intCast(total_sectors);
        total_sectors += @max(1, (f.data.len + sector - 1) / sector);
    }
    if (total_sectors > 1 << 20) return error.TooLarge;
    const img = try gpa.alloc(u8, total_sectors * sector);
    errdefer gpa.free(img);
    @memset(img, 0);

    // Primary volume descriptor.
    const pvd = img[16 * sector ..][0..sector];
    pvd[0] = 1;
    @memcpy(pvd[1..6], "CD001");
    pvd[6] = 1;
    @memset(pvd[8..72], ' '); // system id and volume id
    @memcpy(pvd[40 .. 40 + volume_id.len], volume_id);
    both32(pvd[80..88], @intCast(total_sectors));
    both16(pvd[120..124], 1);
    both16(pvd[124..128], 1);
    both16(pvd[128..132], sector);
    both32(pvd[132..140], 10); // path table size: one root entry
    le32(pvd[140..144], 18); // L path table
    be32(pvd[148..152], 19); // M path table
    _ = dirRecord(pvd[156..190], root_lba, sector, true, &.{0});
    @memset(pvd[190..813], ' '); // set, publisher, preparer, application, copyright, abstract, biblio ids
    // Dates: creation and modification set, expiration and effective unset.
    @memcpy(pvd[813..829], "2026110800000000");
    @memcpy(pvd[830..846], "2026110800000000");
    @memset(pvd[847..863], '0');
    @memset(pvd[864..880], '0');
    pvd[881] = 1;

    // Volume descriptor set terminator.
    const term = img[17 * sector ..][0..sector];
    term[0] = 255;
    @memcpy(term[1..6], "CD001");
    term[6] = 1;

    // Path tables (a single root entry each).
    const lpt = img[18 * sector ..][0..sector];
    lpt[0] = 1;
    le32(lpt[2..6], root_lba);
    std.mem.writeInt(u16, lpt[6..8], 1, .little);
    const mpt = img[19 * sector ..][0..sector];
    mpt[0] = 1;
    be32(mpt[2..6], root_lba);
    std.mem.writeInt(u16, mpt[6..8], 1, .big);

    // Root directory: ".", "..", then files sorted by identifier.
    const dir = img[root_lba * sector ..][0..sector];
    var pos: usize = 0;
    pos += dirRecord(dir[pos..], root_lba, sector, true, &.{0});
    pos += dirRecord(dir[pos..], root_lba, sector, true, &.{1});
    var order: [max_files]usize = undefined;
    for (0..files.len) |i| order[i] = i;
    std.mem.sort(usize, order[0..files.len], files, struct {
        fn less(fs: []const File, a: usize, b: usize) bool {
            var ba: [34]u8 = undefined;
            var bb: [34]u8 = undefined;
            const ia = fileId(fs[a].name, &ba) catch return false;
            const ib = fileId(fs[b].name, &bb) catch return false;
            return std.mem.lessThan(u8, ia, ib);
        }
    }.less);
    for (order[0..files.len]) |i| {
        var idbuf: [34]u8 = undefined;
        const id = try fileId(files[i].name, &idbuf);
        if (pos + 33 + id.len + 1 > sector) return error.TooManyFiles;
        pos += dirRecord(dir[pos..], lbas[i], @intCast(files[i].data.len), false, id);
        @memcpy(img[@as(usize, lbas[i]) * sector ..][0..files[i].data.len], files[i].data);
    }
    return img;
}

/// Reads back a file's data from an image built by `build` (used by tests).
fn find(img: []const u8, id: []const u8) ?[]const u8 {
    const dir = img[root_lba * sector ..][0..sector];
    var pos: usize = 0;
    while (pos < sector and dir[pos] != 0) {
        const len = dir[pos];
        const id_len = dir[pos + 32];
        if (std.mem.eql(u8, dir[pos + 33 ..][0..id_len], id)) {
            const lba = std.mem.readInt(u32, dir[pos + 2 ..][0..4], .little);
            const size = std.mem.readInt(u32, dir[pos + 10 ..][0..4], .little);
            return img[@as(usize, lba) * sector ..][0..size];
        }
        pos += len;
    }
    return null;
}

test "image is well formed and files read back" {
    const gpa = std.testing.allocator;
    const big: [3000]u8 = @splat('x');
    const img = try build(gpa, "WINLAB_ANSWERS", &.{
        .{ .name = "Autounattend.xml", .data = "<unattend/>" },
        .{ .name = "winlab_firstlogon.ps1", .data = &big },
    });
    defer gpa.free(img);
    try std.testing.expectEqual(@as(usize, 0), img.len % sector);
    try std.testing.expectEqualStrings("CD001", img[16 * sector + 1 ..][0..5]);
    try std.testing.expectEqual(@as(u8, 255), img[17 * sector]);
    try std.testing.expectEqualStrings("<unattend/>", find(img, "AUTOUNATTEND.XML;1").?);
    try std.testing.expectEqual(@as(usize, 3000), find(img, "WINLAB_FIRSTLOGON.PS1;1").?.len);
    try std.testing.expect(find(img, "MISSING.TXT;1") == null);
    const blocks = std.mem.readInt(u32, img[16 * sector + 80 ..][0..4], .little);
    try std.testing.expectEqual(@as(usize, blocks), img.len / sector);
}

test "bad names are refused" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.InvalidName, build(gpa, "OK", &.{.{ .name = "has space.txt", .data = "" }}));
    try std.testing.expectError(error.InvalidName, build(gpa, "bad volume", &.{}));
    // Hyphens are allowed (cloud-init needs user-data and meta-data).
    const ok = try build(gpa, "CIDATA", &.{.{ .name = "user-data", .data = "x" }});
    gpa.free(ok);
}
