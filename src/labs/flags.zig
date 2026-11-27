//! Flags: the answers a learner digs out of an investigation lab.
//!
//! A lab file names its flags; its setup and fault scripts say where each one is planted with a placeholder.
//! Every preparation draws new random values, so an answer from one preparation is useless in the next.
//! The values are kept on this computer, next to the VM's disk, because they belong to its prepared snapshot.
//! They are plain text: this stops answers being passed around, not someone reading their own files.
const std = @import("std");

pub const max_flags = 8;

pub const Spec = struct {
    name: []const u8,
    /// What the learner is asked to find.
    question: []const u8,
    /// Authoring aid, like a lab's `solution`: a guest script that prints the flag. `winlab lab verify` runs it
    /// to prove the flag really can be recovered from the prepared machine.
    recover: []const u8,
};

pub const value_len = "WL{}".len + 12;
pub const Value = [value_len]u8;

pub fn valueFrom(bytes: [6]u8) Value {
    var out: Value = undefined;
    const hex = std.fmt.bytesToHex(bytes, .lower);
    @memcpy(out[0..3], "WL{");
    @memcpy(out[3..15], &hex);
    out[15] = '}';
    return out;
}

pub fn generate(io: std.Io) Value {
    var bytes: [6]u8 = undefined;
    io.random(&bytes);
    return valueFrom(bytes);
}

pub fn validName(s: []const u8) bool {
    if (s.len == 0 or s.len > 24) return false;
    for (s) |c| if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '-')) return false;
    return true;
}

const Form = enum { flag, flag_b64, flag_hex };

pub const ExpandError = error{ BadPlaceholder, OutOfMemory };

/// Replaces `{{flag:name}}`, `{{flag_b64:name}}` and `{{flag_hex:name}}` with the value of that flag, plain,
/// base64 or hex. `values` is in the order of `specs`. Sets the bit of each flag it planted in `used`.
pub fn expand(arena: std.mem.Allocator, script: []const u8, specs: []const Spec, values: []const Value, used: *u8) ExpandError![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var rest = script;
    while (std.mem.indexOf(u8, rest, "{{flag")) |at| {
        try out.appendSlice(arena, rest[0..at]);
        const body = rest[at + 2 ..];
        const end = std.mem.indexOf(u8, body, "}}") orelse return error.BadPlaceholder;
        const colon = std.mem.indexOfScalar(u8, body[0..end], ':') orelse return error.BadPlaceholder;
        const form = std.meta.stringToEnum(Form, body[0..colon]) orelse return error.BadPlaceholder;
        const wanted = body[colon + 1 .. end];
        const i = for (specs, 0..) |s, i| {
            if (std.mem.eql(u8, s.name, wanted)) break i;
        } else return error.BadPlaceholder;
        const v = &values[i];
        switch (form) {
            .flag => try out.appendSlice(arena, v),
            .flag_b64 => {
                var buf: [std.base64.standard.Encoder.calcSize(value_len)]u8 = undefined;
                try out.appendSlice(arena, std.base64.standard.Encoder.encode(&buf, v));
            },
            .flag_hex => try out.appendSlice(arena, &std.fmt.bytesToHex(v.*, .lower)),
        }
        used.* |= @as(u8, 1) << @intCast(i);
        rest = body[end + 2 ..];
    }
    try out.appendSlice(arena, rest);
    return out.items;
}

/// One preparation's flags and how far the learner has come with them.
pub const Record = struct {
    count: usize,
    values: [max_flags]Value = undefined,
    /// Bit n: flag n has been submitted.
    solved: u8 = 0,
    /// The containment check has passed.
    contained: bool = false,

    pub fn isSolved(self: Record, i: usize) bool {
        return self.solved & (@as(u8, 1) << @intCast(i)) != 0;
    }

    pub fn left(self: Record) usize {
        return self.count - @popCount(self.solved);
    }

    /// Every flag found and the machine contained.
    pub fn complete(self: Record) bool {
        return self.contained and self.left() == 0;
    }
};

pub const Answer = union(enum) {
    wrong,
    /// Index of the flag.
    correct: usize,
    already: usize,
};

/// Marks the flag matching `text` (surrounding spaces ignored) as solved.
pub fn answer(rec: *Record, text: []const u8) Answer {
    const given = std.mem.trim(u8, text, " \t\r\n");
    for (rec.values[0..rec.count], 0..) |*v, i| {
        if (!std.mem.eql(u8, v, given)) continue;
        if (rec.isSolved(i)) return .{ .already = i };
        rec.solved |= @as(u8, 1) << @intCast(i);
        return .{ .correct = i };
    }
    return .wrong;
}

/// Where a VM's flag records live.
pub const Store = struct {
    io: std.Io,
    vm_dir: []const u8,

    const header = "winlab-flags 1";
    const footer = "end";

    pub const Error = error{FlagRecord};

    fn fileName(buf: []u8, lab_id: []const u8) Error![]const u8 {
        // Lab ids are dotted lowercase (checked when the lab is read); refuse anything that could leave the folder.
        if (std.mem.indexOfAny(u8, lab_id, "/\\:") != null) return error.FlagRecord;
        return std.fmt.bufPrint(buf, "flags-{s}.txt", .{lab_id}) catch error.FlagRecord;
    }

    fn openVmDir(self: Store) Error!std.Io.Dir {
        return std.Io.Dir.cwd().openDir(self.io, self.vm_dir, .{}) catch error.FlagRecord;
    }

    /// Null when there is no record that matches these flags exactly (missing, damaged, or the lab's flags have
    /// changed): the lab has to be prepared again.
    pub fn load(self: Store, lab_id: []const u8, specs: []const Spec) ?Record {
        if (specs.len > max_flags) return null;
        var name_buf: [160]u8 = undefined;
        const name = fileName(&name_buf, lab_id) catch return null;
        var dir = self.openVmDir() catch return null;
        defer dir.close(self.io);
        var text_buf: [2048]u8 = undefined;
        const text = dir.readFile(self.io, name, &text_buf) catch return null;
        return parse(text, specs);
    }

    fn parse(text: []const u8, specs: []const Spec) ?Record {
        var lines = std.mem.tokenizeAny(u8, text, "\r\n");
        if (!std.mem.eql(u8, lines.next() orelse return null, header)) return null;
        const state = lines.next() orelse return null;
        var rec: Record = .{ .count = specs.len };
        if (std.mem.eql(u8, state, "contained=yes")) rec.contained = true else if (!std.mem.eql(u8, state, "contained=no")) return null;
        for (specs, 0..) |s, i| {
            var parts = std.mem.splitScalar(u8, lines.next() orelse return null, ' ');
            if (!std.mem.eql(u8, parts.first(), "flag")) return null;
            if (!std.mem.eql(u8, parts.next() orelse return null, s.name)) return null;
            const v = parts.next() orelse return null;
            if (v.len != value_len) return null;
            @memcpy(&rec.values[i], v);
            const solved = parts.next() orelse return null;
            if (std.mem.eql(u8, solved, "solved")) rec.solved |= @as(u8, 1) << @intCast(i) else if (!std.mem.eql(u8, solved, "open")) return null;
        }
        if (!std.mem.eql(u8, lines.next() orelse return null, footer)) return null;
        return if (lines.next() == null) rec else null;
    }

    pub fn save(self: Store, lab_id: []const u8, specs: []const Spec, rec: Record) Error!void {
        var out: [2048]u8 = undefined;
        var w: std.Io.Writer = .fixed(&out);
        w.print("{s}\ncontained={s}\n", .{ header, if (rec.contained) "yes" else "no" }) catch return error.FlagRecord;
        for (specs, 0..) |s, i| {
            w.print("flag {s} {s} {s}\n", .{ s.name, &rec.values[i], if (rec.isSolved(i)) "solved" else "open" }) catch return error.FlagRecord;
        }
        w.print("{s}\n", .{footer}) catch return error.FlagRecord;
        var name_buf: [160]u8 = undefined;
        const name = try fileName(&name_buf, lab_id);
        var dir = try self.openVmDir();
        defer dir.close(self.io);
        dir.writeFile(self.io, .{ .sub_path = name, .data = w.buffered() }) catch return error.FlagRecord;
    }

    pub fn delete(self: Store, lab_id: []const u8) Error!void {
        var name_buf: [160]u8 = undefined;
        const name = try fileName(&name_buf, lab_id);
        var dir = try self.openVmDir();
        defer dir.close(self.io);
        dir.deleteFile(self.io, name) catch |e| if (e != error.FileNotFound) return error.FlagRecord;
    }
};

const test_specs = [_]Spec{
    .{ .name = "first", .question = "q1", .recover = "r1" },
    .{ .name = "second", .question = "q2", .recover = "r2" },
};

test "placeholders are replaced in each form, and bad ones are refused" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const values = [_]Value{ valueFrom(.{ 0, 1, 2, 3, 4, 5 }), valueFrom(.{ 0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa }) };
    try std.testing.expectEqualStrings("WL{000102030405}", &values[0]);

    var used: u8 = 0;
    const out = try expand(arena, "a={{flag:first}} b={{flag_b64:second}} ${HOME} {{x}}", &test_specs, &values, &used);
    try std.testing.expectEqualStrings("a=WL{000102030405} b=V0x7ZmZlZWRkY2NiYmFhfQ== ${HOME} {{x}}", out);
    try std.testing.expectEqual(@as(u8, 3), used);
    used = 0;
    try std.testing.expectEqualStrings("574c7b3030303130323033303430357d", try expand(arena, "{{flag_hex:first}}", &test_specs, &values, &used));
    try std.testing.expectEqual(@as(u8, 1), used);

    for ([_][]const u8{ "{{flag:third}}", "{{flag_rot13:first}}", "{{flag}}", "{{flag:first" }) |bad|
        try std.testing.expectError(error.BadPlaceholder, expand(arena, bad, &test_specs, &values, &used));
}

test "answers are matched once; the record survives a save and rejects other flag sets and damage" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(dir);
    const store: Store = .{ .io = io, .vm_dir = dir };
    try std.testing.expect(store.load("labs.x", &test_specs) == null);

    var rec: Record = .{ .count = 2 };
    rec.values[0] = generate(io);
    rec.values[1] = generate(io);
    try std.testing.expect(!std.mem.eql(u8, &rec.values[0], &rec.values[1]));
    try std.testing.expectEqual(Answer.wrong, answer(&rec, "WL{nope}"));
    try std.testing.expectEqual(Answer.wrong, answer(&rec, ""));
    const typed = try std.fmt.allocPrint(std.testing.allocator, "  {s} \n", .{&rec.values[1]});
    defer std.testing.allocator.free(typed);
    try std.testing.expectEqual(Answer{ .correct = 1 }, answer(&rec, typed));
    try std.testing.expectEqual(Answer{ .already = 1 }, answer(&rec, typed));
    try std.testing.expectEqual(@as(usize, 1), rec.left());
    rec.contained = true;
    try std.testing.expect(!rec.complete());

    try store.save("labs.x", &test_specs, rec);
    const back = store.load("labs.x", &test_specs).?;
    try std.testing.expectEqualStrings(&rec.values[0], &back.values[0]);
    try std.testing.expectEqual(@as(u8, 2), back.solved);
    try std.testing.expect(back.contained);
    // A lab whose flags changed since it was prepared must be prepared again.
    try std.testing.expect(store.load("labs.x", test_specs[0..1]) == null);
    try std.testing.expect(store.load("labs.x", &.{ test_specs[1], test_specs[0] }) == null);
    try tmp.dir.writeFile(io, .{ .sub_path = "flags-labs.x.txt", .data = "winlab-flags 1\ncontained=no\n" });
    try std.testing.expect(store.load("labs.x", &test_specs) == null);
    try store.delete("labs.x");
    try store.delete("labs.x"); // deleting twice is fine
    try std.testing.expectError(error.FlagRecord, store.save("../x", &test_specs, rec));
}
