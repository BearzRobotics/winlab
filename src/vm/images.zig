//! Installation-media catalog and download (decision record 0006). Downloading is
//! an explicit learner action: WinLab shows the URL, size and destination, asks,
//! and only then runs the system's own curl.exe. Files are fetched over HTTPS only,
//! land in a `.part` file, are size-checked and hashed, and are renamed into place
//! only when complete. WinLab never fetches anything in the background and never
//! installs or activates Windows.
const std = @import("std");
const toml = @import("toml");
const registry = @import("registry.zig");
const unattend = @import("unattend.zig");

pub const Entry = struct {
    id: []const u8,
    name: []const u8,
    /// "windows-server", "windows-client", ... (profile matching comes later).
    os: []const u8,
    edition: []const u8,
    /// Download address (empty for a local image).
    url: []const u8,
    /// Absolute path of a learner-supplied image (empty for a download).
    path: []const u8 = "",
    /// Local file name inside the images folder.
    file: []const u8,
    /// Expected size in bytes (0 = unknown). A mismatch fails the download.
    size_bytes: u64 = 0,
    /// Expected lowercase hex SHA-256 (empty = unknown; the computed hash is recorded for the learner).
    sha256: []const u8 = "",
    /// Shown to the learner before downloading (licence / trial terms).
    note: []const u8 = "",
    /// Unattended-install flavour, if this media can be installed by WinLab (see unattend.zig).
    unattend: ?unattend.Kind = null,
    /// Edition index inside install.wim for the answer file.
    image_index: u32 = 1,
    /// A ready-made Linux cloud image (qcow2/img) configured on first boot by a cloud-init seed ISO,
    /// instead of an installer ISO. See docs/decisions/0006-vm-provider.md.
    cloud_image: bool = false,
    /// QEMU CPU model this guest needs, when not the default (for example "max" for x86-64-v2 distributions).
    cpu: []const u8 = "",
    /// Linux distribution family label written to guest.toml ("ubuntu", "almalinux", ...); empty for Windows.
    distro: []const u8 = "",
    /// HTTPS address of a SHA256SUMS file that lists this download; if set, the downloaded file must match it.
    sums_url: []const u8 = "",
};

pub const Catalog = struct {
    arena: std.heap.ArenaAllocator,
    entries: []Entry,

    pub fn deinit(self: *Catalog) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn find(self: *const Catalog, id: []const u8) ?Entry {
        for (self.entries) |e| {
            if (std.mem.eql(u8, e.id, id)) return e;
        }
        return null;
    }
};

pub const ParseError = error{ InvalidToml, UnsupportedSchema, InvalidEntry, DuplicateId, OutOfMemory };

fn validFileName(s: []const u8) bool {
    if (s.len == 0 or s.len > 96 or s[0] == '.' or s[0] == '-') return false;
    for (s) |c| switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '_', '.' => {},
        else => return false,
    };
    return std.mem.endsWith(u8, s, ".iso") or std.mem.endsWith(u8, s, ".vhdx") or std.mem.endsWith(u8, s, ".qcow2") or std.mem.endsWith(u8, s, ".img");
}

fn validHex256(s: []const u8) bool {
    if (s.len != 64) return false;
    for (s) |c| switch (c) {
        '0'...'9', 'a'...'f' => {},
        else => return false,
    };
    return true;
}

pub fn parse(gpa: std.mem.Allocator, text: []const u8) ParseError!Catalog {
    var doc = toml.Document.parse(gpa, text, .{}, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidToml,
    };
    defer doc.deinit();
    const v = doc.root.getInt("schema_version") orelse return error.UnsupportedSchema;
    if (v != 1) return error.UnsupportedSchema;

    var cat: Catalog = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = &.{} };
    errdefer cat.arena.deinit();
    const a = cat.arena.allocator();
    const arr = doc.root.getArray("image") orelse return cat;
    const out = try a.alloc(Entry, arr.items.items.len);
    for (arr.items.items, out, 0..) |item, *slot, i| {
        const t = switch (item) {
            .table => |t| t,
            else => return error.InvalidEntry,
        };
        const id = t.getString("id") orelse return error.InvalidEntry;
        if (!registry.validId(id)) return error.InvalidEntry;
        for (out[0..i]) |prev| {
            if (std.mem.eql(u8, prev.id, id)) return error.DuplicateId;
        }
        // Either a download (https url + file name) or a local file the learner supplied (absolute path).
        const path = t.getString("path") orelse "";
        var url: []const u8 = "";
        var file: []const u8 = "";
        if (path.len > 0) {
            // A learner-supplied image: absolute Windows path, .iso, no control characters.
            const absolute = (path.len > 3 and std.ascii.isAlphabetic(path[0]) and path[1] == ':' and (path[2] == '\\' or path[2] == '/')) or std.mem.startsWith(u8, path, "\\\\");
            if (!absolute or !std.ascii.endsWithIgnoreCase(path, ".iso")) return error.InvalidEntry;
            for (path) |c| if (c < 0x20 or c == '"') return error.InvalidEntry;
            file = std.fs.path.basename(path);
        } else {
            url = t.getString("url") orelse return error.InvalidEntry;
            if (!std.mem.startsWith(u8, url, "https://")) return error.InvalidEntry;
            for (url) |c| if (c <= ' ' or c == '"' or c == '<' or c == '>') return error.InvalidEntry;
            file = t.getString("file") orelse return error.InvalidEntry;
            if (!validFileName(file)) return error.InvalidEntry;
        }
        const cpu = t.getString("cpu") orelse "";
        const distro = t.getString("distro") orelse "";
        for (cpu) |ch| if (!(std.ascii.isLower(ch) or std.ascii.isDigit(ch) or ch == '-' or ch == '_')) return error.InvalidEntry;
        for (distro) |ch| if (!(std.ascii.isLower(ch) or std.ascii.isDigit(ch) or ch == '-')) return error.InvalidEntry;
        const sums = t.getString("sums_url") orelse "";
        if (sums.len != 0 and !std.mem.startsWith(u8, sums, "https://")) return error.InvalidEntry;
        const sha = t.getString("sha256") orelse "";
        if (sha.len != 0 and !validHex256(sha)) return error.InvalidEntry;
        const size = t.getInt("size_bytes") orelse 0;
        if (size < 0) return error.InvalidEntry;
        slot.* = .{
            .id = try a.dupe(u8, id),
            .name = try a.dupe(u8, t.getString("name") orelse return error.InvalidEntry),
            .os = try a.dupe(u8, t.getString("os") orelse return error.InvalidEntry),
            .edition = try a.dupe(u8, t.getString("edition") orelse ""),
            .url = try a.dupe(u8, url),
            .file = try a.dupe(u8, file),
            .path = try a.dupe(u8, path),
            .size_bytes = @intCast(size),
            .sha256 = try a.dupe(u8, sha),
            .note = try a.dupe(u8, t.getString("note") orelse ""),
            .unattend = if (t.getString("unattend")) |u| (std.meta.stringToEnum(unattend.Kind, u) orelse return error.InvalidEntry) else null,
            .cloud_image = t.getBool("cloud_image") orelse false,
            .cpu = try a.dupe(u8, cpu),
            .distro = try a.dupe(u8, distro),
            .sums_url = try a.dupe(u8, sums),
            .image_index = if (t.getInt("image_index")) |n| (if (n >= 1 and n <= 64) @as(u32, @intCast(n)) else return error.InvalidEntry) else 1,
        };
    }
    cat.entries = out;
    return cat;
}

/// Arguments for curl.exe. HTTPS only (also across redirects), fail on HTTP errors,
/// resume a partial file, no credentials, no config file read.
pub fn curlArgs(arena: std.mem.Allocator, curl: []const u8, url: []const u8, part_path: []const u8) ![]const []const u8 {
    return arena.dupe([]const u8, &.{
        curl,
        "--disable", // ignore any .curlrc
        "--fail",
        "--location",
        "--proto",
        "=https",
        "--proto-redir",
        "=https",
        "--continue-at",
        "-",
        "--retry-all-errors", // a reset mid-transfer is retried too, resuming where it stopped
        "--retry-delay",
        "5",
        "--retry",
        "20",
        "--output",
        part_path,
        url,
    });
}

/// Streaming SHA-256 of a file as lowercase hex.
pub fn hashFile(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) ![64]u8 {
    var f = try dir.openFile(io, sub_path, .{});
    defer f.close(io);
    var rbuf: [64 * 1024]u8 = undefined;
    var fr = f.reader(io, &rbuf);
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    var chunk: [64 * 1024]u8 = undefined;
    while (true) {
        const n = try fr.interface.readSliceShort(&chunk);
        if (n == 0) break;
        h.update(chunk[0..n]);
        if (n < chunk.len) break;
    }
    var digest: [32]u8 = undefined;
    h.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

extern "kernel32" fn GetDiskFreeSpaceExW([*:0]const u16, ?*u64, ?*u64, ?*u64) callconv(.winapi) i32;

/// Bytes available to the current user on the volume containing `dir_path`, or null if unknown.
pub fn freeBytes(gpa: std.mem.Allocator, dir_path: []const u8) ?u64 {
    const w = std.unicode.utf8ToUtf16LeAllocZ(gpa, dir_path) catch return null;
    defer gpa.free(w);
    var avail: u64 = 0;
    if (GetDiskFreeSpaceExW(w.ptr, &avail, null, null) == 0) return null;
    return avail;
}

test "catalog parses and validates" {
    const gpa = std.testing.allocator;
    var c = try parse(gpa,
        \\schema_version = 1
        \\[[image]]
        \\id = "server-2022-eval"
        \\name = "Windows Server 2022 (evaluation)"
        \\os = "windows-server"
        \\url = "https://example.com/a.iso"
        \\file = "SERVER_EVAL.iso"
        \\size_bytes = 5044094976
        \\
    );
    defer c.deinit();
    try std.testing.expectEqual(@as(u64, 5044094976), c.find("server-2022-eval").?.size_bytes);
    try std.testing.expect(c.find("nope") == null);

    const bad = [_][]const u8{
        "schema_version = 1\n[[image]]\nid=\"a\"\nname=\"n\"\nos=\"o\"\nurl=\"http://x/a.iso\"\nfile=\"a.iso\"\n",
        "schema_version = 1\n[[image]]\nid=\"a\"\nname=\"n\"\nos=\"o\"\nurl=\"https://x/a.iso\"\nfile=\"..\\\\a.iso\"\n",
        "schema_version = 1\n[[image]]\nid=\"a\"\nname=\"n\"\nos=\"o\"\nurl=\"https://x/a.iso\"\nfile=\"a.iso\"\nsha256=\"zz\"\n",
        "schema_version = 1\n[[image]]\nid=\"a\"\nname=\"n\"\nos=\"o\"\nurl=\"https://x/a b.iso\"\nfile=\"a.iso\"\n",
    };
    for (bad) |text| try std.testing.expectError(error.InvalidEntry, parse(gpa, text));
}

test "curl arguments are https-only and ignore user config" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const args = try curlArgs(arena.allocator(), "C:\\Windows\\System32\\curl.exe", "https://x/a.iso", "D:\\a.iso.part");
    var has_proto = false;
    var has_disable = false;
    for (args, 0..) |a, i| {
        if (std.mem.eql(u8, a, "--proto") and std.mem.eql(u8, args[i + 1], "=https")) has_proto = true;
        if (std.mem.eql(u8, a, "--disable")) has_disable = true;
    }
    try std.testing.expect(has_proto and has_disable);
    try std.testing.expectEqualStrings("https://x/a.iso", args[args.len - 1]);
}

test "sha256 of a file matches a known vector" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "abc.bin", .data = "abc" });
    const hex = try hashFile(io, tmp.dir, "abc.bin");
    try std.testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &hex);
}

test "learner-supplied images use an absolute .iso path" {
    const gpa = std.testing.allocator;
    var c = try parse(gpa,
        \\schema_version = 1
        \\[[image]]
        \\id = "my-win11"
        \\name = "Windows 11 Pro (mine)"
        \\os = "windows-client"
        \\path = 'D:\isos\Win11_Pro.iso'
        \\unattend = "client"
        \\image_index = 6
        \\
    );
    defer c.deinit();
    const e = c.find("my-win11").?;
    try std.testing.expectEqualStrings("Win11_Pro.iso", e.file);
    try std.testing.expectEqualStrings("D:\\isos\\Win11_Pro.iso", e.path);
    try std.testing.expectEqual(@as(u32, 6), e.image_index);
    try std.testing.expectError(error.InvalidEntry, parse(gpa, "schema_version = 1\n[[image]]\nid=\"a\"\nname=\"n\"\nos=\"o\"\npath=\"relative.iso\"\n"));
    try std.testing.expectError(error.InvalidEntry, parse(gpa, "schema_version = 1\n[[image]]\nid=\"a\"\nname=\"n\"\nos=\"o\"\npath='D:\\x.exe'\n"));
}

/// Finds `file_name` in the text of a SHA256SUMS file ("<64 hex> *<name>" or "<64 hex>  <name>") and
/// returns its lowercase hash.
pub fn findSum(text: []const u8, file_name: []const u8) ?[64]u8 {
    var lines = std.mem.tokenizeAny(u8, text, "\r\n");
    while (lines.next()) |line| {
        if (line.len < 66 or !validHex256(line[0..64])) continue;
        var rest = std.mem.trimStart(u8, line[64..], " ");
        if (rest.len > 0 and rest[0] == '*') rest = rest[1..];
        if (std.mem.eql(u8, rest, file_name)) {
            var out: [64]u8 = undefined;
            @memcpy(&out, line[0..64]);
            return out;
        }
    }
    return null;
}

test "SHA256SUMS lookup" {
    const text = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa *other.img\n04e8f2461a16a44e78a370284471f29616cdd9baf1893df25807b71f985b6c94 *noble.img\nbad line\n";
    const h = findSum(text, "noble.img").?;
    try std.testing.expectEqualStrings("04e8f2461a16a44e78a370284471f29616cdd9baf1893df25807b71f985b6c94", &h);
    try std.testing.expect(findSum(text, "missing.img") == null);
    try std.testing.expect(findSum("04e8f2461a16a44e78a370284471f29616cdd9baf1893df25807b71f985b6c94  plain.img", "plain.img") != null);
}
