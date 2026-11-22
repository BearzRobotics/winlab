//! Badges: small milestones derived from the progress file. Nothing extra is stored, so a badge cannot be
//! lost or faked by editing a second file, and switching badges off just hides them. There are no points,
//! streaks or rankings: a badge says "you did this", nothing more.
const std = @import("std");
const progress = @import("progress.zig");

/// Entries whose id starts with this are labs (a fixed lab is recorded as a completed entry), not lessons.
pub const lab_prefix = "labs.";

pub const Stats = struct {
    lessons_done: usize = 0,
    quizzes_taken: usize = 0,
    quizzes_passed: usize = 0,
    perfect_quizzes: usize = 0,
    labs_fixed: usize = 0,
    /// Lessons with some notes written.
    notes_written: usize = 0,

    pub fn from(p: *const progress.Progress) Stats {
        var s: Stats = .{};
        var it = p.map.iterator();
        while (it.next()) |kv| {
            const id = kv.key_ptr.*;
            const e = kv.value_ptr.*;
            if (std.mem.startsWith(u8, id, lab_prefix)) {
                if (e.status == .completed) s.labs_fixed += 1;
                continue;
            }
            if (e.status.isDone()) s.lessons_done += 1;
            if (e.quiz_attempts > 0) {
                s.quizzes_taken += 1;
                if (e.quiz_best >= progress.Progress.placement_percent) s.quizzes_passed += 1;
                if (e.quiz_best == 100) s.perfect_quizzes += 1;
            }
            if (e.notes.len > 0) s.notes_written += 1;
        }
        return s;
    }
};

pub const Kind = enum { lessons, quizzes_taken, quizzes_passed, perfect_quizzes, labs_fixed, notes_written };

pub const Def = struct {
    id: []const u8,
    title: []const u8,
    how: []const u8,
    kind: Kind,
    need: usize,
};

/// The fixed set. Thresholds are small on purpose: early badges arrive early.
pub const defs = [_]Def{
    .{ .id = "first-lesson", .title = "First lesson", .how = "Finish 1 lesson", .kind = .lessons, .need = 1 },
    .{ .id = "ten-lessons", .title = "Ten lessons", .how = "Finish 10 lessons", .kind = .lessons, .need = 10 },
    .{ .id = "thirty-lessons", .title = "Thirty lessons", .how = "Finish 30 lessons", .kind = .lessons, .need = 30 },
    .{ .id = "fifty-lessons", .title = "Fifty lessons", .how = "Finish 50 lessons", .kind = .lessons, .need = 50 },
    .{ .id = "first-quiz", .title = "First quiz", .how = "Finish a quiz", .kind = .quizzes_taken, .need = 1 },
    .{ .id = "quiz-passer", .title = "Quiz passer", .how = "Score 80% or more on 5 different quizzes", .kind = .quizzes_passed, .need = 5 },
    .{ .id = "perfect-score", .title = "Perfect score", .how = "Score 100% on a quiz", .kind = .perfect_quizzes, .need = 1 },
    .{ .id = "first-lab", .title = "First lab fixed", .how = "Fix a lab", .kind = .labs_fixed, .need = 1 },
    .{ .id = "five-labs", .title = "Five labs fixed", .how = "Fix 5 labs", .kind = .labs_fixed, .need = 5 },
    .{ .id = "note-taker", .title = "Note taker", .how = "Write notes on 3 lessons", .kind = .notes_written, .need = 3 },
};

pub fn value(s: Stats, k: Kind) usize {
    return switch (k) {
        .lessons => s.lessons_done,
        .quizzes_taken => s.quizzes_taken,
        .quizzes_passed => s.quizzes_passed,
        .perfect_quizzes => s.perfect_quizzes,
        .labs_fixed => s.labs_fixed,
        .notes_written => s.notes_written,
    };
}

pub fn earned(s: Stats, d: Def) bool {
    return value(s, d.kind) >= d.need;
}

pub fn countEarned(s: Stats) usize {
    var n: usize = 0;
    for (defs) |d| {
        if (earned(s, d)) n += 1;
    }
    return n;
}

test "empty progress earns nothing" {
    var p = progress.Progress.init(std.testing.allocator);
    defer p.deinit();
    try std.testing.expectEqual(@as(usize, 0), countEarned(Stats.from(&p)));
}

test "lessons, known lessons, quizzes, labs and notes are counted separately" {
    var p = progress.Progress.init(std.testing.allocator);
    defer p.deinit();
    try p.setStatus("a.one", .completed);
    try p.setStatus("a.two", .known); // placement counts as done
    try p.setStatus("a.three", .in_progress); // does not
    try p.setStatus("a.skip", .skipped); // does not
    try p.setQuizResult("a.one", 100, "");
    try p.setQuizResult("a.two", 85, "q1");
    try p.setQuizResult("a.three", 40, "q1 q2");
    try p.setNotes("a.one", "hello");
    try p.setStatus("labs.fix-it", .completed);
    try p.setStatus("labs.half", .in_progress);
    const s = Stats.from(&p);
    try std.testing.expectEqual(@as(usize, 2), s.lessons_done);
    try std.testing.expectEqual(@as(usize, 3), s.quizzes_taken);
    try std.testing.expectEqual(@as(usize, 2), s.quizzes_passed);
    try std.testing.expectEqual(@as(usize, 1), s.perfect_quizzes);
    try std.testing.expectEqual(@as(usize, 1), s.labs_fixed);
    try std.testing.expectEqual(@as(usize, 1), s.notes_written);
    // first-lesson, first-quiz, perfect-score, first-lab
    try std.testing.expectEqual(@as(usize, 4), countEarned(s));
}

test "thresholds" {
    const s: Stats = .{ .lessons_done = 10, .quizzes_passed = 4 };
    for (defs) |d| {
        if (std.mem.eql(u8, d.id, "ten-lessons")) try std.testing.expect(earned(s, d));
        if (std.mem.eql(u8, d.id, "thirty-lessons")) try std.testing.expect(!earned(s, d));
        if (std.mem.eql(u8, d.id, "quiz-passer")) try std.testing.expect(!earned(s, d));
    }
}
