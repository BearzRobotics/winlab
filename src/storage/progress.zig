//! Learner progress and notes (decision record 0004). Stored as TOML in
//! %APPDATA%\WinLab\progress.toml, keyed by lesson id so it survives content
//! reordering. Unknown ids are kept (a lesson may be temporarily absent) and
//! unusable entries are dropped with a count, never a crash.
const std = @import("std");
const toml = @import("toml");

pub const Status = enum {
    not_started,
    in_progress,
    completed,
    /// Passed the lesson's quiz before studying it (a placement test): counts as done without the lesson being read.
    known,
    /// Left out on purpose; stays one click away.
    skipped,

    pub fn label(self: Status) []const u8 {
        return switch (self) {
            .not_started => "Not started",
            .in_progress => "In progress",
            .completed => "Completed",
            .known => "Known",
            .skipped => "Skipped",
        };
    }

    /// Counts toward "done": studied, or shown by the quiz to be already known.
    pub fn isDone(self: Status) bool {
        return self == .completed or self == .known;
    }
};

pub const max_notes_bytes = 64 * 1024;
pub const schema_version = 1;

pub const Entry = struct {
    status: Status = .not_started,
    /// Owned by the Progress; empty when there are no notes.
    notes: []const u8 = "",
    /// Quiz results (percent 0..100). `quiz_attempts` is 0 until the learner finishes a quiz.
    quiz_best: u8 = 0,
    quiz_last: u8 = 0,
    quiz_attempts: u32 = 0,
    /// Space-separated ids of the questions missed in the last attempt; owned, empty when none.
    quiz_missed: []const u8 = "",
};

pub const max_missed_bytes = 8 * 1024;

pub const Progress = struct {
    gpa: std.mem.Allocator,
    /// Keys and notes are owned by `gpa`.
    map: std.StringArrayHashMapUnmanaged(Entry) = .empty,
    /// Entries in the file that could not be used.
    dropped: usize = 0,
    /// Id of the learning path the learner is following; empty for "all lessons". Owned.
    active_path: []const u8 = "",
    /// Per path id: the lesson last open on that path. Keys and values owned.
    last_on_path: std.StringArrayHashMapUnmanaged([]const u8) = .empty,

    pub fn init(gpa: std.mem.Allocator) Progress {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Progress) void {
        for (self.map.keys(), self.map.values()) |k, v| {
            self.gpa.free(k);
            self.gpa.free(v.notes);
            self.gpa.free(v.quiz_missed);
        }
        self.map.deinit(self.gpa);
        self.gpa.free(self.active_path);
        for (self.last_on_path.keys(), self.last_on_path.values()) |k, v| {
            self.gpa.free(k);
            self.gpa.free(v);
        }
        self.last_on_path.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn get(self: *const Progress, id: []const u8) Entry {
        return self.map.get(id) orelse .{};
    }

    fn slot(self: *Progress, id: []const u8) !*Entry {
        const gop = try self.map.getOrPut(self.gpa, id);
        if (!gop.found_existing) {
            errdefer _ = self.map.swapRemove(id);
            gop.key_ptr.* = try self.gpa.dupe(u8, id);
            gop.value_ptr.* = .{};
        }
        return gop.value_ptr;
    }

    pub fn setStatus(self: *Progress, id: []const u8, status: Status) !void {
        (try self.slot(id)).status = status;
    }

    /// Replaces the notes. Over-long notes are rejected rather than truncated.
    pub fn setNotes(self: *Progress, id: []const u8, notes: []const u8) !void {
        if (notes.len > max_notes_bytes) return error.NotesTooLong;
        const copy = try self.gpa.dupe(u8, notes);
        errdefer self.gpa.free(copy);
        const e = try self.slot(id);
        self.gpa.free(e.notes);
        e.notes = copy;
    }

    /// Records a finished quiz attempt. `missed` is a space-separated list of question ids.
    pub fn setQuizResult(self: *Progress, id: []const u8, percent: u8, missed: []const u8) !void {
        if (percent > 100 or missed.len > max_missed_bytes) return error.InvalidQuizResult;
        const copy = try self.gpa.dupe(u8, missed);
        errdefer self.gpa.free(copy);
        const e = try self.slot(id);
        self.gpa.free(e.quiz_missed);
        e.quiz_missed = copy;
        e.quiz_last = percent;
        e.quiz_best = @max(e.quiz_best, percent);
        e.quiz_attempts +|= 1;
    }

    pub fn countCompleted(self: *const Progress) usize {
        var n: usize = 0;
        for (self.map.values()) |v| {
            if (v.status == .completed) n += 1;
        }
        return n;
    }

    /// A full quiz attempt at or above this percent, on a lesson not yet started, marks it Known.
    pub const placement_percent: u8 = 80;

    /// Placement test rule: a lesson the learner has not started (or skipped) and then passes the quiz for
    /// is Known. Returns true when the status changed. A lesson already in progress or completed is left
    /// alone: a good score there is revision, not placement.
    pub fn markKnownIfPassed(self: *Progress, id: []const u8, percent: u8) !bool {
        if (percent < placement_percent) return false;
        const current = self.get(id).status;
        if (current != .not_started and current != .skipped) return false;
        try self.setStatus(id, .known);
        return true;
    }

    pub fn setActivePath(self: *Progress, path_id: []const u8) !void {
        const copy = try self.gpa.dupe(u8, path_id);
        self.gpa.free(self.active_path);
        self.active_path = copy;
    }

    pub fn lastOnPath(self: *const Progress, path_id: []const u8) []const u8 {
        return self.last_on_path.get(path_id) orelse "";
    }

    pub fn setLastOnPath(self: *Progress, path_id: []const u8, lesson_id: []const u8) !void {
        const val = try self.gpa.dupe(u8, lesson_id);
        errdefer self.gpa.free(val);
        const gop = try self.last_on_path.getOrPut(self.gpa, path_id);
        if (gop.found_existing) {
            self.gpa.free(gop.value_ptr.*);
        } else {
            errdefer _ = self.last_on_path.swapRemove(path_id);
            gop.key_ptr.* = try self.gpa.dupe(u8, path_id);
        }
        gop.value_ptr.* = val;
    }

    pub const ParseError = error{ InvalidToml, UnsupportedSchema, OutOfMemory };

    pub fn parse(gpa: std.mem.Allocator, text: []const u8) ParseError!Progress {
        var doc = toml.Document.parse(gpa, text, .{}, null) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidToml,
        };
        defer doc.deinit();
        const v = doc.root.getInt("schema_version") orelse return error.UnsupportedSchema;
        if (v != schema_version) return error.UnsupportedSchema;

        var p = init(gpa);
        errdefer p.deinit();
        if (doc.root.getTable("state")) |st| {
            if (st.getString("path")) |id| if (id.len <= 64) try p.setActivePath(id) else {
                p.dropped += 1;
            };
        }
        if (doc.root.getTable("paths")) |pt| {
            for (pt.entries.keys(), pt.entries.values()) |pid, val| {
                const t = switch (val) {
                    .table => |t| t,
                    else => {
                        p.dropped += 1;
                        continue;
                    },
                };
                const last = t.getString("last") orelse continue;
                if (pid.len > 64 or last.len > 128) {
                    p.dropped += 1;
                    continue;
                }
                try p.setLastOnPath(pid, last);
            }
        }
        const lessons = doc.root.getTable("lessons") orelse return p;
        for (lessons.entries.keys(), lessons.entries.values()) |id, val| {
            const t = switch (val) {
                .table => |t| t,
                else => {
                    p.dropped += 1;
                    continue;
                },
            };
            const status = if (t.getString("status")) |s|
                std.meta.stringToEnum(Status, s) orelse {
                    p.dropped += 1;
                    continue;
                }
            else
                Status.not_started;
            const notes = t.getString("notes") orelse "";
            if (notes.len > max_notes_bytes) {
                p.dropped += 1;
                continue;
            }
            try p.setStatus(id, status);
            const best = t.getInt("quiz_best") orelse 0;
            const last = t.getInt("quiz_last") orelse 0;
            const attempts = t.getInt("quiz_attempts") orelse 0;
            const missed = t.getString("quiz_missed") orelse "";
            if (best < 0 or best > 100 or last < 0 or last > 100 or attempts < 0 or attempts > std.math.maxInt(u32) or missed.len > max_missed_bytes) {
                p.dropped += 1;
            } else if (attempts > 0) {
                const e = try p.slot(id);
                e.quiz_best = @intCast(best);
                e.quiz_last = @intCast(last);
                e.quiz_attempts = @intCast(attempts);
                e.quiz_missed = try p.gpa.dupe(u8, missed);
            }
            // Length was checked above, so only allocation can fail here.
            p.setNotes(id, notes) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.NotesTooLong => unreachable,
            };
        }
        return p;
    }

    pub fn write(self: *const Progress, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("schema_version = {d}\n", .{schema_version});
        if (self.active_path.len != 0) {
            try w.writeAll("\n[state]\npath = ");
            try writeQuoted(w, self.active_path);
            try w.writeByte('\n');
        }
        for (self.last_on_path.keys(), self.last_on_path.values()) |pid, last| {
            try w.writeAll("\n[paths.");
            try writeQuoted(w, pid);
            try w.writeAll("]\nlast = ");
            try writeQuoted(w, last);
            try w.writeByte('\n');
        }
        for (self.map.keys(), self.map.values()) |id, e| {
            if (e.status == .not_started and e.notes.len == 0 and e.quiz_attempts == 0) continue;
            try w.writeAll("\n[lessons.");
            try writeQuoted(w, id);
            try w.print("]\nstatus = \"{s}\"\n", .{@tagName(e.status)});
            if (e.notes.len != 0) {
                try w.writeAll("notes = ");
                try writeQuoted(w, e.notes);
                try w.writeByte('\n');
            }
            if (e.quiz_attempts != 0) {
                try w.print("quiz_best = {d}\nquiz_last = {d}\nquiz_attempts = {d}\nquiz_missed = ", .{ e.quiz_best, e.quiz_last, e.quiz_attempts });
                try writeQuoted(w, e.quiz_missed);
                try w.writeByte('\n');
            }
        }
    }
};

fn writeQuoted(w: *std.Io.Writer, s: []const u8) std.Io.Writer.Error!void {
    try w.writeByte('"');
    for (s) |c| switch (c) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        '\n' => try w.writeAll("\\n"),
        '\r' => try w.writeAll("\\r"),
        '\t' => try w.writeAll("\\t"),
        0...8, 11, 12, 14...31, 127 => try w.print("\\u{x:0>4}", .{c}),
        else => try w.writeByte(c),
    };
    try w.writeByte('"');
}

test "round trip with awkward notes" {
    const gpa = std.testing.allocator;
    var p = Progress.init(gpa);
    defer p.deinit();
    try p.setStatus("part1.alpha", .completed);
    try p.setNotes("part1.alpha", "line1\nline \"2\" \\ tab\there\x01 é");
    try p.setStatus("part2.gamma", .in_progress);
    try p.setStatus("untouched", .not_started);

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try p.write(&out.writer);

    var q = try Progress.parse(gpa, out.written());
    defer q.deinit();
    try std.testing.expectEqual(Status.completed, q.get("part1.alpha").status);
    try std.testing.expectEqualStrings("line1\nline \"2\" \\ tab\there\x01 é", q.get("part1.alpha").notes);
    try std.testing.expectEqual(Status.in_progress, q.get("part2.gamma").status);
    try std.testing.expectEqual(Status.not_started, q.get("untouched").status);
    try std.testing.expectEqual(@as(usize, 1), q.countCompleted());
}

test "quiz results round trip and keep the best score" {
    const gpa = std.testing.allocator;
    var p = Progress.init(gpa);
    defer p.deinit();
    try p.setQuizResult("a.b", 60, "q1 q2");
    try p.setQuizResult("a.b", 40, "q3");
    try std.testing.expectEqual(@as(u8, 60), p.get("a.b").quiz_best);
    try std.testing.expectEqual(@as(u8, 40), p.get("a.b").quiz_last);
    try std.testing.expectEqual(@as(u32, 2), p.get("a.b").quiz_attempts);
    try std.testing.expectError(error.InvalidQuizResult, p.setQuizResult("a.b", 101, ""));

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try p.write(&out.writer);
    var q = try Progress.parse(gpa, out.written());
    defer q.deinit();
    try std.testing.expectEqual(@as(u8, 60), q.get("a.b").quiz_best);
    try std.testing.expectEqual(@as(u32, 2), q.get("a.b").quiz_attempts);
    try std.testing.expectEqualStrings("q3", q.get("a.b").quiz_missed);
    // Out-of-range values are dropped, not trusted.
    var bad = try Progress.parse(gpa, "schema_version = 1\n[lessons.\"x.y\"]\nstatus = \"completed\"\nquiz_best = 900\nquiz_attempts = 1\n");
    defer bad.deinit();
    try std.testing.expectEqual(@as(usize, 1), bad.dropped);
    try std.testing.expectEqual(@as(u32, 0), bad.get("x.y").quiz_attempts);
}

test "bad entries are dropped, bad files are errors" {
    const gpa = std.testing.allocator;
    var p = try Progress.parse(gpa,
        \\schema_version = 1
        \\[lessons."a.b"]
        \\status = "bogus"
        \\[lessons."c.d"]
        \\status = "completed"
        \\
    );
    defer p.deinit();
    try std.testing.expectEqual(@as(usize, 1), p.dropped);
    try std.testing.expectEqual(Status.completed, p.get("c.d").status);
    try std.testing.expectError(error.InvalidToml, Progress.parse(gpa, "x = \n"));
    try std.testing.expectError(error.UnsupportedSchema, Progress.parse(gpa, "schema_version = 2\n"));
    try std.testing.expectError(error.UnsupportedSchema, Progress.parse(gpa, ""));
}

test "notes limit" {
    var p = Progress.init(std.testing.allocator);
    defer p.deinit();
    const big = try std.testing.allocator.alloc(u8, max_notes_bytes + 1);
    defer std.testing.allocator.free(big);
    @memset(big, 'x');
    try std.testing.expectError(error.NotesTooLong, p.setNotes("a.b", big));
}

test "placement: passing the quiz first marks Known, revision does not" {
    const gpa = std.testing.allocator;
    var p = Progress.init(gpa);
    defer p.deinit();
    try std.testing.expect(!try p.markKnownIfPassed("a.b", 70));
    try std.testing.expectEqual(Status.not_started, p.get("a.b").status);
    try std.testing.expect(try p.markKnownIfPassed("a.b", 80));
    try std.testing.expectEqual(Status.known, p.get("a.b").status);
    try std.testing.expect(Status.known.isDone() and Status.completed.isDone());
    try std.testing.expect(!Status.skipped.isDone());
    // A lesson in progress or completed is not re-marked.
    try p.setStatus("c.d", .in_progress);
    try std.testing.expect(!try p.markKnownIfPassed("c.d", 100));
    try p.setStatus("e.f", .completed);
    try std.testing.expect(!try p.markKnownIfPassed("e.f", 100));
    // A skipped lesson can become Known.
    try p.setStatus("g.h", .skipped);
    try std.testing.expect(try p.markKnownIfPassed("g.h", 90));
}

test "active path and last position round trip, bad values are dropped" {
    const gpa = std.testing.allocator;
    var p = Progress.init(gpa);
    defer p.deinit();
    try p.setActivePath("windows-scripting");
    try p.setActivePath("networking"); // replaces
    try p.setLastOnPath("networking", "networking.dns");
    try p.setLastOnPath("networking", "networking.dhcp"); // replaces
    try p.setLastOnPath("windows-scripting", "foundations.cmd-basics");
    try p.setStatus("a.b", .known);
    try p.setStatus("c.d", .skipped);

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try p.write(&out.writer);
    var q = try Progress.parse(gpa, out.written());
    defer q.deinit();
    try std.testing.expectEqualStrings("networking", q.active_path);
    try std.testing.expectEqualStrings("networking.dhcp", q.lastOnPath("networking"));
    try std.testing.expectEqualStrings("foundations.cmd-basics", q.lastOnPath("windows-scripting"));
    try std.testing.expectEqualStrings("", q.lastOnPath("none"));
    try std.testing.expectEqual(Status.known, q.get("a.b").status);
    try std.testing.expectEqual(Status.skipped, q.get("c.d").status);

    const long = try gpa.alloc(u8, 65);
    defer gpa.free(long);
    @memset(long, 'x');
    const text = try std.fmt.allocPrint(gpa, "schema_version = 1\n[state]\npath = \"{s}\"\n[paths]\nbroken = 3\n", .{long});
    defer gpa.free(text);
    var bad = try Progress.parse(gpa, text);
    defer bad.deinit();
    try std.testing.expectEqual(@as(usize, 2), bad.dropped);
    try std.testing.expectEqualStrings("", bad.active_path);
}
