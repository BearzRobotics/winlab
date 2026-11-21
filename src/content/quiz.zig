//! Lesson quizzes: `quizzes/<lesson-id>.toml` at the content root (next to `labs/`).
//! UI-independent. A quiz file is untrusted input like a lesson manifest: every field is validated and
//! a failure names the offending key.
//!
//! ```toml
//! schema_version = 1
//! lesson = "networking.models-and-protocols"
//! draw = 10                        # optional: questions asked per attempt, drawn from the whole bank
//!
//! [[question]]
//! id = "switch-layer"              # unique in the file; progress records missed questions by it
//! type = "choice"                  # choice (one right answer) | multi (several) | short (typed)
//! prompt = "At which layer does a switch forward frames?"
//! choices = ["Layer 1", "Layer 2", "Layer 3"]
//! answers = ["Layer 2"]            # choice/multi: texts from `choices`. short: accepted spellings.
//! explanation = "A switch uses MAC addresses, which belong to layer 2."   # required
//! review = "Local delivery: MAC addresses, ARP and switches"  # optional: lesson section to re-read
//! certifications = ["comptia-network-plus/networking-concepts"]            # optional
//! ```
//!
//! Choices are graded by their text, never by position, so the window may shuffle them.
const std = @import("std");
const toml = @import("toml");

pub const schema_version: i64 = 1;
pub const max_choices = 8;
pub const max_questions = 200;

pub const Kind = enum { choice, multi, short };

pub const Question = struct {
    id: []const u8,
    kind: Kind,
    prompt: []const u8,
    /// choice and multi only.
    choices: []const []const u8,
    /// choice/multi: the correct choice texts. short: the accepted answers.
    answers: []const []const u8,
    explanation: []const u8,
    review: []const u8,
    certifications: []const []const u8,
};

pub const default_draw = 10;

pub const Quiz = struct {
    arena: std.heap.ArenaAllocator,
    lesson: []const u8,
    /// The whole bank. An attempt asks only `draw` of them (see `pick`).
    questions: []const Question,
    draw: usize,

    pub fn deinit(self: *Quiz) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub const Failure = struct {
    key: []const u8 = "",
    message: []const u8 = "",
    /// 1-based question number, 0 when the problem is not in a question.
    question: usize = 0,
    toml_line: usize = 0,
    toml_column: usize = 0,
};

pub const Error = error{ InvalidToml, InvalidQuiz, OutOfMemory };

fn fail(f: *Failure, q: usize, key: []const u8, message: []const u8) error{InvalidQuiz} {
    f.* = .{ .key = key, .message = message, .question = q };
    return error.InvalidQuiz;
}

pub fn parse(gpa: std.mem.Allocator, text: []const u8, failure: *Failure) Error!Quiz {
    var diag: toml.Diagnostic = .{};
    var doc = toml.Document.parse(gpa, text, .{}, &diag) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            failure.* = .{ .message = diag.message, .toml_line = diag.line, .toml_column = diag.column };
            return error.InvalidToml;
        },
    };
    defer doc.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();
    const t = doc.root;

    const version = t.getInt("schema_version") orelse return fail(failure, 0, "schema_version", "missing or not an integer");
    if (version != schema_version) return fail(failure, 0, "schema_version", "unsupported schema version");
    const lesson = t.getString("lesson") orelse return fail(failure, 0, "lesson", "missing or not a string");
    if (lesson.len == 0) return fail(failure, 0, "lesson", "must not be empty");

    const arr = t.getArray("question") orelse return fail(failure, 0, "question", "at least one [[question]] is required");
    if (arr.items.items.len == 0) return fail(failure, 0, "question", "at least one [[question]] is required");
    if (arr.items.items.len > max_questions) return fail(failure, 0, "question", "too many questions");

    const out = try a.alloc(Question, arr.items.items.len);
    for (arr.items.items, out, 1..) |item, *slot, n| {
        const q = switch (item) {
            .table => |tb| tb,
            else => return fail(failure, n, "question", "must be a table"),
        };
        slot.* = try parseQuestion(a, q, n, failure);
        for (out[0 .. n - 1]) |earlier| {
            if (std.mem.eql(u8, earlier.id, slot.id)) return fail(failure, n, "id", "duplicate question id");
        }
    }
    var draw: usize = @min(default_draw, out.len);
    if (t.get("draw") != null) {
        const d = t.getInt("draw") orelse return fail(failure, 0, "draw", "not an integer");
        if (d < 1 or d > out.len) return fail(failure, 0, "draw", "must be between 1 and the number of questions");
        draw = @intCast(d);
    }
    return .{ .arena = arena, .lesson = try a.dupe(u8, lesson), .questions = out, .draw = draw };
}

fn parseQuestion(a: std.mem.Allocator, q: *const toml.Table, n: usize, f: *Failure) Error!Question {
    const id = try requiredString(a, q, "id", n, f);
    for (id) |c| {
        if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '-')) return fail(f, n, "id", "use lowercase letters, digits and '-' only");
    }
    const type_str = q.getString("type") orelse return fail(f, n, "type", "missing or not a string");
    const kind = std.meta.stringToEnum(Kind, type_str) orelse return fail(f, n, "type", "must be choice, multi or short");
    const prompt = try requiredString(a, q, "prompt", n, f);
    const explanation = try requiredString(a, q, "explanation", n, f);
    const review = try optionalString(a, q, "review", n, f);
    const certs = try stringList(a, q, "certifications", n, f);
    const answers = try stringList(a, q, "answers", n, f);
    if (answers.len == 0) return fail(f, n, "answers", "at least one answer is required");

    var choices: []const []const u8 = &.{};
    switch (kind) {
        .short => {
            for (answers) |ans| {
                if (std.mem.trim(u8, ans, " \t").len == 0) return fail(f, n, "answers", "accepted answers must not be blank");
            }
        },
        .choice, .multi => {
            choices = try stringList(a, q, "choices", n, f);
            if (choices.len < 2) return fail(f, n, "choices", "at least two choices are required");
            if (choices.len > max_choices) return fail(f, n, "choices", "too many choices");
            for (choices, 0..) |c, i| {
                for (choices[0..i]) |d| if (std.mem.eql(u8, c, d)) return fail(f, n, "choices", "choices must be different");
            }
            for (answers, 0..) |ans, i| {
                var found = false;
                for (choices) |c| if (std.mem.eql(u8, c, ans)) {
                    found = true;
                };
                if (!found) return fail(f, n, "answers", "every answer must be one of the choices, spelled exactly");
                for (answers[0..i]) |d| if (std.mem.eql(u8, d, ans)) return fail(f, n, "answers", "an answer is listed twice");
            }
            if (answers.len >= choices.len) return fail(f, n, "answers", "at least one choice must be wrong");
            if (kind == .choice and answers.len != 1) return fail(f, n, "answers", "a choice question has exactly one answer; use multi for several");
            if (kind == .multi and answers.len < 2) return fail(f, n, "answers", "a multi question has at least two answers; use choice for one");
        },
    }
    return .{ .id = id, .kind = kind, .prompt = prompt, .choices = choices, .answers = answers, .explanation = explanation, .review = review, .certifications = certs };
}

fn requiredString(a: std.mem.Allocator, t: *const toml.Table, key: []const u8, n: usize, f: *Failure) Error![]const u8 {
    const s = t.getString(key) orelse return fail(f, n, key, "missing or not a string");
    if (std.mem.trim(u8, s, " \t\r\n").len == 0) return fail(f, n, key, "must not be empty");
    return try a.dupe(u8, s);
}

fn optionalString(a: std.mem.Allocator, t: *const toml.Table, key: []const u8, n: usize, f: *Failure) Error![]const u8 {
    if (t.get(key) == null) return "";
    const s = t.getString(key) orelse return fail(f, n, key, "not a string");
    return try a.dupe(u8, s);
}

fn stringList(a: std.mem.Allocator, t: *const toml.Table, key: []const u8, n: usize, f: *Failure) Error![]const []const u8 {
    if (t.get(key) == null) return &.{};
    const arr = t.getArray(key) orelse return fail(f, n, key, "not an array");
    const out = try a.alloc([]const u8, arr.items.items.len);
    for (arr.items.items, out) |item, *slot| {
        const s = switch (item) {
            .string => |s| s,
            else => return fail(f, n, key, "entries must be strings"),
        };
        if (s.len == 0) return fail(f, n, key, "entries must not be empty");
        slot.* = try a.dupe(u8, s);
    }
    return out;
}

// ---------------------------------------------------------------------------------------------
// Grading
// ---------------------------------------------------------------------------------------------

/// Lower-cases ASCII, trims and collapses runs of blanks, so "  TCP   443 " matches "tcp 443".
/// The result is written to `buf` (truncated if longer) and returned.
pub fn normalize(buf: []u8, text: []const u8) []const u8 {
    var n: usize = 0;
    var pending_space = false;
    for (text) |c| {
        if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
            pending_space = n > 0;
            continue;
        }
        if (pending_space) {
            if (n < buf.len) {
                buf[n] = ' ';
                n += 1;
            }
            pending_space = false;
        }
        if (n < buf.len) {
            buf[n] = std.ascii.toLower(c);
            n += 1;
        }
    }
    return buf[0..n];
}

/// A typed answer is right if it equals any accepted answer after normalising both.
pub fn gradeShort(q: Question, typed: []const u8) bool {
    var b1: [256]u8 = undefined;
    var b2: [256]u8 = undefined;
    const given = normalize(&b1, typed);
    if (given.len == 0) return false;
    for (q.answers) |ans| {
        if (std.mem.eql(u8, given, normalize(&b2, ans))) return true;
    }
    return false;
}

/// `picked` holds the choice *texts* the learner selected. Right when it is exactly the set of answers.
pub fn gradeChoices(q: Question, picked: []const []const u8) bool {
    if (picked.len != q.answers.len) return false;
    for (picked) |p| {
        var ok = false;
        for (q.answers) |ans| if (std.mem.eql(u8, p, ans)) {
            ok = true;
        };
        if (!ok) return false;
    }
    // Same size and every pick is an answer; duplicates in `picked` would pass, so reject them.
    for (picked, 0..) |p, i| {
        for (picked[0..i]) |d| if (std.mem.eql(u8, p, d)) return false;
    }
    return true;
}

/// Chooses which questions one attempt asks, written to `out` (length = the quiz's `draw`, or fewer if
/// `out` is shorter). Questions the learner missed last time come first (up to half the attempt) so weak
/// spots come back; the rest are random from the bank; the final order is shuffled. Returns the count.
/// `missed` is a space-separated list of question ids (as stored in progress).
pub fn pick(quiz: *const Quiz, missed: []const u8, random: std.Random, out: []usize) usize {
    const want = @min(quiz.draw, out.len);
    if (want == 0) return 0;
    var pool: [max_questions]usize = undefined;
    var n: usize = 0;
    var weak: [max_questions]usize = undefined;
    var nw: usize = 0;
    for (quiz.questions, 0..) |q, i| {
        var is_missed = false;
        var it = std.mem.tokenizeScalar(u8, missed, ' ');
        while (it.next()) |m| if (std.mem.eql(u8, m, q.id)) {
            is_missed = true;
        };
        if (is_missed) {
            weak[nw] = i;
            nw += 1;
        } else {
            pool[n] = i;
            n += 1;
        }
    }
    random.shuffle(usize, weak[0..nw]);
    random.shuffle(usize, pool[0..n]);
    var k: usize = 0;
    const weak_take = @min(nw, (want + 1) / 2);
    for (weak[0..weak_take]) |i| {
        out[k] = i;
        k += 1;
    }
    for (pool[0..n]) |i| {
        if (k == want) break;
        out[k] = i;
        k += 1;
    }
    // Not enough fresh questions: top up with the remaining missed ones.
    for (weak[weak_take..nw]) |i| {
        if (k == want) break;
        out[k] = i;
        k += 1;
    }
    random.shuffle(usize, out[0..k]);
    return k;
}

/// Whole-number percentage, rounded down; an empty quiz scores 0.
pub fn percent(correct: usize, total: usize) u8 {
    if (total == 0) return 0;
    return @intCast(@min(100, correct * 100 / total));
}

// ---------------------------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------------------------

const sample =
    \\schema_version = 1
    \\lesson = "networking.models-and-protocols"
    \\
    \\[[question]]
    \\id = "switch-layer"
    \\type = "choice"
    \\prompt = "At which layer does a switch forward frames?"
    \\choices = ["Layer 1", "Layer 2", "Layer 3"]
    \\answers = ["Layer 2"]
    \\explanation = "MAC addresses are layer 2."
    \\review = "Local delivery"
    \\
    \\[[question]]
    \\id = "udp-users"
    \\type = "multi"
    \\prompt = "Which normally use UDP?"
    \\choices = ["DNS queries", "SSH", "DHCP", "HTTPS"]
    \\answers = ["DNS queries", "DHCP"]
    \\explanation = "SSH and HTTPS need TCP's reliability."
    \\
    \\[[question]]
    \\id = "https-port"
    \\type = "short"
    \\prompt = "Which TCP port does HTTPS use?"
    \\answers = ["443", "tcp 443"]
    \\explanation = "443 is the registered port for HTTPS."
    \\
;

test "parses and grades a sample quiz" {
    const gpa = std.testing.allocator;
    var f: Failure = .{};
    var q = try parse(gpa, sample, &f);
    defer q.deinit();
    try std.testing.expectEqualStrings("networking.models-and-protocols", q.lesson);
    try std.testing.expectEqual(@as(usize, 3), q.questions.len);

    try std.testing.expect(gradeChoices(q.questions[0], &.{"Layer 2"}));
    try std.testing.expect(!gradeChoices(q.questions[0], &.{"Layer 3"}));
    try std.testing.expect(gradeChoices(q.questions[1], &.{ "DHCP", "DNS queries" }));
    try std.testing.expect(!gradeChoices(q.questions[1], &.{"DHCP"}));
    try std.testing.expect(!gradeChoices(q.questions[1], &.{ "DHCP", "DHCP" }));
    try std.testing.expect(!gradeChoices(q.questions[1], &.{ "DHCP", "SSH" }));
    try std.testing.expect(gradeShort(q.questions[2], "  TCP   443 "));
    try std.testing.expect(gradeShort(q.questions[2], "443"));
    try std.testing.expect(!gradeShort(q.questions[2], "4430"));
    try std.testing.expect(!gradeShort(q.questions[2], "   "));
}

fn expectRejected(text: []const u8, key: []const u8) !void {
    var f: Failure = .{};
    if (parse(std.testing.allocator, text, &f)) |*ok| {
        var q = ok.*;
        q.deinit();
        std.debug.print("accepted a quiz that should fail on '{s}'\n", .{key});
        return error.TestUnexpectedResult;
    } else |err| {
        try std.testing.expectEqual(error.InvalidQuiz, err);
        try std.testing.expectEqualStrings(key, f.key);
    }
}

test "rejects malformed quizzes and names the key" {
    const head = "schema_version = 1\nlesson = \"a.b\"\n[[question]]\nid = \"q\"\nprompt = \"p\"\nexplanation = \"e\"\n";
    try expectRejected("lesson = \"a.b\"\n", "schema_version");
    try expectRejected("schema_version = 1\nlesson = \"a.b\"\n", "question");
    try expectRejected(head ++ "type = \"quiz\"\n", "type");
    try expectRejected(head ++ "type = \"choice\"\nchoices = [\"a\", \"b\"]\nanswers = [\"c\"]\n", "answers");
    try expectRejected(head ++ "type = \"choice\"\nchoices = [\"a\", \"b\"]\nanswers = [\"a\", \"b\"]\n", "answers");
    try expectRejected(head ++ "type = \"choice\"\nchoices = [\"a\", \"a\"]\nanswers = [\"a\"]\n", "choices");
    try expectRejected(head ++ "type = \"choice\"\nchoices = [\"a\"]\nanswers = [\"a\"]\n", "choices");
    try expectRejected(head ++ "type = \"multi\"\nchoices = [\"a\", \"b\", \"c\"]\nanswers = [\"a\"]\n", "answers");
    try expectRejected(head ++ "type = \"short\"\nanswers = [\" \"]\n", "answers");
    try expectRejected("schema_version = 1\nlesson = \"a.b\"\n[[question]]\nid = \"Q 1\"\ntype = \"short\"\nprompt = \"p\"\nexplanation = \"e\"\nanswers = [\"x\"]\n", "id");
    // A missing explanation is rejected: every answer must be explained.
    try expectRejected("schema_version = 1\nlesson = \"a.b\"\n[[question]]\nid = \"q\"\ntype = \"short\"\nprompt = \"p\"\nanswers = [\"x\"]\n", "explanation");
    // Duplicate ids.
    try expectRejected(head ++ "type = \"short\"\nanswers = [\"x\"]\n[[question]]\nid = \"q\"\ntype = \"short\"\nprompt = \"p\"\nexplanation = \"e\"\nanswers = [\"x\"]\n", "id");
}

test "pick draws a subset, favours missed questions and never repeats" {
    const gpa = std.testing.allocator;
    var text: std.Io.Writer.Allocating = .init(gpa);
    defer text.deinit();
    try text.writer.writeAll("schema_version = 1\nlesson = \"a.b\"\ndraw = 4\n");
    for (0..12) |i| try text.writer.print("[[question]]\nid = \"q{d}\"\ntype = \"short\"\nprompt = \"p\"\nanswers = [\"x\"]\nexplanation = \"e\"\n", .{i});
    var f: Failure = .{};
    var quiz = try parse(gpa, text.written(), &f);
    defer quiz.deinit();
    try std.testing.expectEqual(@as(usize, 4), quiz.draw);

    var prng = std.Random.DefaultPrng.init(42);
    var out: [10]usize = undefined;
    for (0..50) |_| {
        const n = pick(&quiz, "q3 q7 q9", prng.random(), &out);
        try std.testing.expectEqual(@as(usize, 4), n);
        var seen: [12]bool = @splat(false);
        var weak: usize = 0;
        for (out[0..n]) |i| {
            try std.testing.expect(!seen[i]);
            seen[i] = true;
            if (i == 3 or i == 7 or i == 9) weak += 1;
        }
        try std.testing.expect(weak >= 2); // half of 4 come from the missed list
    }
    // Different seeds give different draws.
    var a1: [4]usize = undefined;
    var a2: [4]usize = undefined;
    var r1 = std.Random.DefaultPrng.init(1);
    var r2 = std.Random.DefaultPrng.init(2);
    _ = pick(&quiz, "", r1.random(), &a1);
    _ = pick(&quiz, "", r2.random(), &a2);
    try std.testing.expect(!std.mem.eql(usize, &a1, &a2));
}

test "percent and normalize" {
    try std.testing.expectEqual(@as(u8, 66), percent(2, 3));
    try std.testing.expectEqual(@as(u8, 100), percent(3, 3));
    try std.testing.expectEqual(@as(u8, 0), percent(0, 0));
    var b: [16]u8 = undefined;
    try std.testing.expectEqualStrings("a b", normalize(&b, "  A \t B  "));
}
