//! Lab manifests (TOML) and the lab lifecycle (decision record 0006). A lab
//! declares what it changes, what it needs and how it is undone; the runner
//! refuses to touch anything that is not a registered training target and
//! reports incomplete cleanup instead of success.
const std = @import("std");
const toml = @import("toml");
const manifest = @import("../content/manifest.zig");
const script_lab = @import("script_lab.zig");
const flags = @import("flags.zig");
const guest = @import("../vm/guest.zig");
const certs = @import("../content/certs.zig");
const provider = @import("../vm/provider.zig");
const registry = @import("../vm/registry.zig");

pub const schema_version = 1;

/// `scenario`: a baked broken machine to fix. `script`: write a script that is checked against fresh data.
pub const Kind = enum { scenario, script };

/// Which kind of guest a lab runs on. A Linux lab needs a Linux lab VM (guest.toml `shell = "bash"`).
pub const Target = enum { windows, linux };

pub const Lab = struct {
    kind: Kind = .scenario,
    target: Target = .windows,
    /// For Linux labs: the distribution this lab needs (for example "almalinux"); empty runs on any Linux VM.
    distro: []const u8 = "",
    /// Certification domains this lab supports ("exam-id/domain-id", see certs/catalog.toml).
    certifications: []const []const u8 = &.{},
    /// For script labs: where in the guest the learner saves the script.
    script_path: []const u8 = "",
    id: []const u8,
    title: []const u8,
    summary: []const u8,
    /// Lesson this lab belongs to, if any.
    lesson: []const u8,
    /// What the learner is told will change in the guest.
    expected_changes: []const []const u8,
    hazards: []const []const u8,
    scope: []const u8,
    privilege: manifest.Privilege,
    /// Rollback is by snapshot; a lab that changes anything must require one.
    requires_snapshot: bool,
    /// `network = "isolated"`: the lab VM can reach neither this computer nor anything beyond it. Required for
    /// labs that put hostile or deliberately vulnerable things in the guest. The default, "open", can reach both.
    isolated: bool = false,
    /// Guest scripts, in the guest's own script language. Empty means the step is skipped.
    setup: []const u8,
    fault: []const u8,
    /// Authoring aid: a script that fixes the fault. Used only by `winlab lab selftest` to prove the lab is solvable.
    solution: []const u8,
    /// What the learner is told is wrong (a user-style report, never the cause). Required to build a scenario.
    symptom: []const u8,
    /// Optional nudges, shown one at a time on request, from vague to specific.
    hints: []const []const u8,
    validate: Validation,
    /// `[[flags]]`: answers the learner digs out of an investigation scenario. Values are new on each preparation.
    flags: []const flags.Spec = &.{},
};

pub const Validation = struct {
    script: []const u8,
    expect_exit: u32 = 0,
    /// If non-empty, the output must contain this text.
    expect_output_contains: []const u8 = "",
};

pub const Parsed = struct {
    arena: std.heap.ArenaAllocator,
    lab: Lab,

    pub fn deinit(self: *Parsed) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub const ParseError = error{ InvalidToml, UnsupportedSchema, InvalidLab, OutOfMemory };

pub const Failure = struct { field: []const u8 = "", message: []const u8 = "" };

fn bad(f: ?*Failure, field: []const u8, msg: []const u8) ParseError {
    if (f) |p| p.* = .{ .field = field, .message = msg };
    return error.InvalidLab;
}

fn strings(a: std.mem.Allocator, t: *const toml.Table, key: []const u8, f: ?*Failure, min: usize) ParseError![]const []const u8 {
    const arr = t.getArray(key) orelse {
        if (min == 0 and t.get(key) == null) return &.{};
        return bad(f, key, "must be an array of strings");
    };
    if (arr.items.items.len < min) return bad(f, key, "needs at least one entry");
    const out = try a.alloc([]const u8, arr.items.items.len);
    for (arr.items.items, out) |item, *slot| {
        const s = switch (item) {
            .string => |s| s,
            else => return bad(f, key, "must contain only strings"),
        };
        if (s.len == 0) return bad(f, key, "entries must not be empty");
        slot.* = try a.dupe(u8, s);
    }
    return out;
}

fn str(a: std.mem.Allocator, t: *const toml.Table, key: []const u8, f: ?*Failure, required: bool) ParseError![]const u8 {
    const s = t.getString(key) orelse {
        if (!required and t.get(key) == null) return "";
        return bad(f, key, "must be a string");
    };
    if (required and s.len == 0) return bad(f, key, "must not be empty");
    return a.dupe(u8, s);
}

pub fn parse(gpa: std.mem.Allocator, text: []const u8, failure: ?*Failure) ParseError!Parsed {
    var doc = toml.Document.parse(gpa, text, .{}, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidToml,
    };
    defer doc.deinit();
    const t = doc.root;
    const v = t.getInt("schema_version") orelse return error.UnsupportedSchema;
    if (v != schema_version) return error.UnsupportedSchema;

    var out: Parsed = .{ .arena = std.heap.ArenaAllocator.init(gpa), .lab = undefined };
    errdefer out.arena.deinit();
    const a = out.arena.allocator();

    const id = try str(a, t, "id", failure, true);
    if (!manifest.validId(id)) return bad(failure, "id", "must be dotted lowercase, e.g. labs.spooler-stopped");
    const priv_text = t.getString("privilege") orelse "standard";
    const priv = std.meta.stringToEnum(manifest.Privilege, priv_text) orelse return bad(failure, "privilege", "must be standard or administrator");

    const kind_text = t.getString("kind") orelse "scenario";
    const kind = std.meta.stringToEnum(Kind, kind_text) orelse return bad(failure, "kind", "must be scenario or script");
    // Script labs get their validation generated from [[tests]]; scenarios must provide [validate].
    const vt_opt = t.getTable("validate");
    if (kind == .scenario and vt_opt == null) return bad(failure, "validate", "a [validate] table is required");
    var vscript: []const u8 = "";
    var expect_exit: i64 = 0;
    var expect_contains: []const u8 = "";
    if (vt_opt) |vt| {
        vscript = try str(a, vt, "script", failure, true);
        expect_exit = vt.getInt("expect_exit") orelse 0;
        if (expect_exit < 0 or expect_exit > 65535) return bad(failure, "validate.expect_exit", "out of range");
        expect_contains = try str(a, vt, "expect_output_contains", failure, false);
    }

    var lab: Lab = .{
        .kind = kind,
        .target = std.meta.stringToEnum(Target, t.getString("target") orelse "windows") orelse return bad(failure, "target", "must be windows or linux"),
        .distro = blk: {
            const d = t.getString("distro") orelse break :blk "";
            for (d) |ch| if (!(std.ascii.isLower(ch) or std.ascii.isDigit(ch) or ch == '-')) return bad(failure, "distro", "lowercase letters, digits and hyphens only");
            break :blk try a.dupe(u8, d);
        },
        .id = id,
        .title = try str(a, t, "title", failure, true),
        .summary = try str(a, t, "summary", failure, true),
        .lesson = try str(a, t, "lesson", failure, false),
        .expected_changes = try strings(a, t, "expected_changes", failure, 1),
        .hazards = try strings(a, t, "hazards", failure, 0),
        .scope = try str(a, t, "scope", failure, true),
        .privilege = priv,
        .requires_snapshot = t.getBool("requires_snapshot") orelse return bad(failure, "requires_snapshot", "must be stated (true or false)"),
        .isolated = blk: {
            if (t.get("network") == null) break :blk false;
            // Anything unexpected is an error, never silently "open".
            const n = t.getString("network") orelse return bad(failure, "network", "must be open or isolated");
            if (std.mem.eql(u8, n, "isolated")) break :blk true;
            if (std.mem.eql(u8, n, "open")) break :blk false;
            return bad(failure, "network", "must be open or isolated");
        },
        .setup = try str(a, t, "setup", failure, false),
        .fault = try str(a, t, "fault", failure, false),
        .solution = try str(a, t, "solution", failure, false),
        .symptom = try str(a, t, "symptom", failure, false),
        .hints = try strings(a, t, "hints", failure, 0),
        .certifications = blk: {
            const tags = try strings(a, t, "certifications", failure, 0);
            for (tags) |tag| if (!certs.validTagShape(tag)) return bad(failure, "certifications", "tags look like exam-id/domain-id");
            break :blk tags;
        },
        .validate = .{
            .script = vscript,
            .expect_exit = @intCast(expect_exit),
            .expect_output_contains = expect_contains,
        },
    };
    if (kind == .script) try applyScript(a, t, &lab, failure);
    if (t.get("flags") != null) try applyFlags(a, t, &lab, failure);
    const cleanup = t.getString("cleanup_strategy") orelse return bad(failure, "cleanup_strategy", "is required");
    if (!std.mem.eql(u8, cleanup, "snapshot-restore")) return bad(failure, "cleanup_strategy", "only snapshot-restore is supported");
    // A lab that changes guest state must be rolled back by a snapshot.
    if ((lab.setup.len > 0 or lab.fault.len > 0) and !lab.requires_snapshot)
        return bad(failure, "requires_snapshot", "labs that change guest state must require a snapshot");
    out.lab = lab;
    return out;
}

/// Turns a script lab's fields into the scripts the runner already understands: `setup` writes the
/// starter file, `solution` writes the reference script (for `lab verify`), and `validate` is the
/// generated harness. The task text is `symptom`.
fn applyScript(a: std.mem.Allocator, t: *const toml.Table, lab: *Lab, failure: ?*Failure) ParseError!void {
    const lang_text = t.getString("language") orelse return bad(failure, "language", "must be cmd, powershell or bash");
    const language = std.meta.stringToEnum(script_lab.Language, lang_text) orelse return bad(failure, "language", "must be cmd, powershell or bash");
    // bash scripts run on a Linux VM; CMD and PowerShell scripts on a Windows VM.
    if (language.isLinux() != (lab.target == .linux)) return bad(failure, "language", "bash labs need target = \"linux\"; cmd and powershell labs target windows");
    const path = try str(a, t, "script_path", failure, true);
    const starter = try str(a, t, "starter", failure, true);
    const solution = try str(a, t, "solution", failure, true);
    if (lab.symptom.len == 0) return bad(failure, "symptom", "a script lab needs its task text in `symptom`");
    const tests_arr = t.getArray("tests") orelse return bad(failure, "tests", "at least one [[tests]] table is required");
    const tests = try a.alloc(script_lab.Test, tests_arr.items.items.len);
    for (tests_arr.items.items, tests) |item, *slot| {
        const tt = switch (item) {
            .table => |x| x,
            else => return bad(failure, "tests", "each test must be a table"),
        };
        const exit_code: ?u32 = if (tt.getInt("expect_exit")) |c| (if (c >= 0 and c <= 255) @as(u32, @intCast(c)) else return bad(failure, "tests", "expect_exit must be 0..255")) else null;
        slot.* = .{
            .setup = try str(a, tt, "setup", failure, true),
            .expect = try str(a, tt, "expect", failure, false),
            .args = try str(a, tt, "args", failure, false),
            .expect_exit = exit_code,
            .check = try str(a, tt, "check", failure, false),
        };
    }
    const spec: script_lab.Spec = .{ .language = language, .script_path = path, .starter = starter, .solution = solution, .tests = tests };
    script_lab.check(spec) catch |e| return bad(failure, "script", switch (e) {
        error.InvalidPath => "script_path must be an absolute path: C:\\Labs\\name.ps1 for Windows, /home/labadmin/labs/name.sh for Linux",
        error.WrongExtension => "script_path must end in .ps1 (powershell), .cmd/.bat (cmd) or .sh (bash)",
        error.NotAscii => "starter, solution and tests must be plain ASCII",
        error.UnsafeText => "a line begins with '@ or WINLAB_EOF (would end a here-document), or args has unsafe characters",
        error.NoTests => "at least one [[tests]] table is required",
        error.EmptyTest => "every test needs at least one of expect, expect_exit or check",
        else => "invalid script lab",
    });
    lab.script_path = path;
    lab.setup = script_lab.writeFileScript(a, language, path, starter) catch return bad(failure, "starter", "too long");
    lab.solution = script_lab.writeFileScript(a, language, path, solution) catch return bad(failure, "solution", "too long");
    lab.validate = .{
        .script = script_lab.harness(a, spec) catch return bad(failure, "tests", "the tests are too long (keep setup/expect short)"),
        .expect_output_contains = script_lab.passLine(a, tests.len) catch return error.OutOfMemory,
    };
    lab.requires_snapshot = true;
}

/// Reads `[[flags]]` and proves the placeholders in `setup` and `fault` match them.
fn applyFlags(a: std.mem.Allocator, t: *const toml.Table, lab: *Lab, failure: ?*Failure) ParseError!void {
    if (lab.kind != .scenario) return bad(failure, "flags", "only scenario labs can have flags");
    const arr = t.getArray("flags") orelse return bad(failure, "flags", "must be [[flags]] tables");
    const n = arr.items.items.len;
    if (n == 0 or n > flags.max_flags) return bad(failure, "flags", "between 1 and 8 flags");
    const specs = try a.alloc(flags.Spec, n);
    for (arr.items.items, 0..) |item, i| {
        const ft = switch (item) {
            .table => |x| x,
            else => return bad(failure, "flags", "each flag must be a table"),
        };
        specs[i] = .{
            .name = try str(a, ft, "name", failure, true),
            .question = try str(a, ft, "question", failure, true),
            .recover = try str(a, ft, "recover", failure, true),
        };
        if (!flags.validName(specs[i].name)) return bad(failure, "flags.name", "lowercase letters, digits and hyphens, at most 24");
        for (specs[0..i]) |other| if (std.mem.eql(u8, other.name, specs[i].name)) return bad(failure, "flags.name", "names must differ");
    }
    const sample: [flags.max_flags]flags.Value = @splat(flags.valueFrom(@splat(0)));
    var used: u8 = 0;
    for ([_][]const u8{ lab.setup, lab.fault }) |script| {
        const full = flags.expand(a, script, specs, &sample, &used) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.BadPlaceholder => return bad(failure, "flags", "a {{flag...}} placeholder is malformed or names no [[flags]] entry"),
        };
        if (full.len > guest.max_script_bytes) return bad(failure, "flags", "setup and fault must each fit in 4000 bytes with the flags filled in");
    }
    if (used != @as(u8, @intCast((@as(u16, 1) << @intCast(n)) - 1))) return bad(failure, "flags", "every flag must be planted by setup or fault");
    lab.flags = specs;
}

// ---- lifecycle -------------------------------------------------------------

/// The VM as this lab uses it.
fn labTarget(vm: registry.Vm, lab: Lab) provider.Target {
    var t = vm.target();
    t.isolated = lab.isolated;
    return t;
}

pub const Phase = enum { idle, prepared, set_up, fault_injected };

pub const RunError = error{
    NotTrainingTarget,
    ProviderMismatch,
    MissingCapability,
    VmNotStopped,
    StaleSnapshot,
    OutOfOrder,
    GuestFailed,
    /// The self-test cannot run a lab with flags; it is built and verified as a scenario.
    FlagsNeedScenario,
} || provider.Error;

pub const Validated = struct {
    passed: bool,
    exit_code: u32,
    output: []u8,
};

pub const ResetReport = struct {
    /// The VM was stopped and the pre-lab snapshot restored.
    restored: bool = false,
    /// The pre-lab snapshot was removed afterwards.
    snapshot_removed: bool = false,
    /// True only if everything above succeeded. Anything else is incomplete cleanup.
    complete: bool = false,
    /// Short reason when incomplete (static text).
    problem: []const u8 = "",
};

pub const Runner = struct {
    gpa: std.mem.Allocator,
    provider: provider.Provider,
    vm: registry.Vm,
    lab: Lab,
    phase: Phase = .idle,
    snap_buf: [96]u8 = undefined,
    snap_len: usize = 0,

    pub fn init(gpa: std.mem.Allocator, prov: provider.Provider, vm: registry.Vm, lab: Lab) Runner {
        return .{ .gpa = gpa, .provider = prov, .vm = vm, .lab = lab };
    }

    fn target(self: *const Runner) provider.Target {
        return labTarget(self.vm, self.lab);
    }

    pub fn snapshotName(self: *const Runner) []const u8 {
        return self.snap_buf[0..self.snap_len];
    }

    /// Checks everything that can be checked before touching the VM. Safe to call repeatedly.
    pub fn check(self: *const Runner) RunError!void {
        if (!self.vm.training_target) return error.NotTrainingTarget;
        if (!std.mem.eql(u8, self.vm.provider, self.provider.name())) return error.ProviderMismatch;
        const caps = self.provider.capabilities();
        if (!caps.power) return error.MissingCapability;
        if (self.lab.requires_snapshot and !caps.snapshots) return error.MissingCapability;
        if ((self.lab.setup.len > 0 or self.lab.fault.len > 0 or self.lab.validate.script.len > 0) and !caps.guest_exec) return error.MissingCapability;
    }

    /// Takes the pre-lab snapshot (VM must be stopped) and boots the VM. This is the
    /// explicit "begin lab" action; nothing in the guest has changed yet.
    pub fn prepare(self: *Runner) RunError!void {
        if (self.phase != .idle) return error.OutOfOrder;
        if (self.lab.flags.len > 0) return error.FlagsNeedScenario;
        try self.check();
        if ((try self.provider.state(self.target())) != .stopped) return error.VmNotStopped;
        const name = std.fmt.bufPrint(&self.snap_buf, "winlab-pre-{s}", .{self.lab.id}) catch return error.ProviderFailed;
        self.snap_len = name.len;
        if (!provider.validSnapshotName(name)) return error.ProviderFailed;
        if (self.lab.requires_snapshot) {
            if (try self.provider.hasSnapshot(self.target(), name)) return error.StaleSnapshot;
            try self.provider.createSnapshot(self.target(), name);
        }
        self.provider.start(self.target()) catch |e| {
            // Do not leave a snapshot behind for a lab that never began.
            if (self.lab.requires_snapshot) self.provider.deleteSnapshot(self.target(), name) catch {};
            return e;
        };
        self.phase = .prepared;
    }

    fn runScript(self: *Runner, script: []const u8) RunError!void {
        if (script.len == 0) return;
        const r = try self.provider.runInGuest(self.gpa, self.target(), script);
        defer self.gpa.free(r.output);
        if (r.exit_code != 0) return error.GuestFailed;
    }

    pub fn setup(self: *Runner) RunError!void {
        if (self.phase != .prepared) return error.OutOfOrder;
        try self.runScript(self.lab.setup);
        self.phase = .set_up;
    }

    pub fn injectFault(self: *Runner) RunError!void {
        if (self.phase != .set_up) return error.OutOfOrder;
        try self.runScript(self.lab.fault);
        self.phase = .fault_injected;
    }

    /// Runs the validation script and compares the final state, not the commands the
    /// learner used. Caller frees `output` with the runner's allocator.
    pub fn validate(self: *Runner) RunError!Validated {
        if (self.phase != .fault_injected and self.phase != .set_up) return error.OutOfOrder;
        const r = try self.provider.runInGuest(self.gpa, self.target(), self.lab.validate.script);
        const v = self.lab.validate;
        const exit_ok = r.exit_code == v.expect_exit;
        const out_ok = v.expect_output_contains.len == 0 or std.mem.indexOf(u8, r.output, v.expect_output_contains) != null;
        return .{ .passed = exit_ok and out_ok, .exit_code = r.exit_code, .output = r.output };
    }

    /// Rolls the VM back. Never claims success it cannot prove: every failure is reported.
    pub fn reset(self: *Runner) ResetReport {
        var rep: ResetReport = .{};
        const t = self.target();
        if (!self.lab.requires_snapshot) {
            self.phase = .idle;
            self.provider.stop(t) catch {
                rep.problem = "the VM could not be stopped";
                return rep;
            };
            rep = .{ .restored = true, .snapshot_removed = true, .complete = true };
            return rep;
        }
        self.provider.stop(t) catch {
            rep.problem = "the VM could not be stopped";
            return rep;
        };
        self.provider.restoreSnapshot(t, self.snapshotName()) catch {
            rep.problem = "the pre-lab snapshot could not be restored; the VM may still contain lab changes";
            return rep;
        };
        rep.restored = true;
        self.phase = .idle;
        self.provider.deleteSnapshot(t, self.snapshotName()) catch {
            rep.problem = "the VM was restored but the snapshot could not be removed";
            return rep;
        };
        rep.snapshot_removed = true;
        rep.complete = true;
        return rep;
    }
};

// ---- baked scenarios ---------------------------------------------------------
//
// A scenario is a lab whose fault is injected AHEAD of time: from the clean snapshot the
// builder runs setup and fault, shuts the VM down and snapshots the broken machine. A learner
// session just restores that snapshot and boots it (see docs/decisions/0006-vm-provider.md).

pub const clean_snapshot = "winlab-clean";

pub const ScenarioError = error{
    NoSymptom,
    NoCleanSnapshot,
    ScenarioExists,
    NoScenario,
    /// The lab has flags and no place to keep them was given, or the record could not be written.
    FlagRecord,
} || RunError;

pub const Scenario = struct {
    gpa: std.mem.Allocator,
    provider: provider.Provider,
    vm: registry.Vm,
    lab: Lab,
    name_buf: [96]u8 = undefined,
    name_len: usize = 0,
    /// The last failed guest script: its exit code and the end of its output, for a window that has no console.
    guest_exit: u32 = 0,
    guest_tail: [400]u8 = undefined,
    guest_tail_len: usize = 0,
    /// Where a lab with flags keeps them: the VM's folder. Required for such labs.
    store: ?flags.Store = null,

    pub fn failedOutput(self: *const Scenario) []const u8 {
        return self.guest_tail[0..self.guest_tail_len];
    }

    pub fn init(gpa: std.mem.Allocator, prov: provider.Provider, vm: registry.Vm, lab: Lab) Scenario {
        var s: Scenario = .{ .gpa = gpa, .provider = prov, .vm = vm, .lab = lab };
        const n = std.fmt.bufPrint(&s.name_buf, "winlab-scenario-{s}", .{lab.id}) catch "";
        s.name_len = n.len;
        return s;
    }

    fn target(self: *const Scenario) provider.Target {
        return labTarget(self.vm, self.lab);
    }

    pub fn snapshotName(self: *const Scenario) []const u8 {
        return self.name_buf[0..self.name_len];
    }

    fn check(self: *const Scenario) ScenarioError!void {
        if (!self.vm.training_target) return error.NotTrainingTarget;
        if (!std.mem.eql(u8, self.vm.provider, self.provider.name())) return error.ProviderMismatch;
        const caps = self.provider.capabilities();
        if (!caps.power or !caps.snapshots or !caps.guest_exec) return error.MissingCapability;
        if (!provider.validSnapshotName(self.snapshotName())) return error.ProviderFailed;
    }

    fn requireStopped(self: *const Scenario) ScenarioError!void {
        if ((try self.provider.state(self.target())) != .stopped) return error.VmNotStopped;
    }

    fn script(self: *Scenario, text: []const u8) ScenarioError!void {
        if (text.len == 0) return;
        const r = try self.provider.runInGuest(self.gpa, self.target(), text);
        defer self.gpa.free(r.output);
        if (r.exit_code != 0) {
            std.debug.print("guest script failed (exit {d}):\n{s}\n", .{ r.exit_code, r.output });
            self.guest_exit = r.exit_code;
            const out = std.mem.trim(u8, r.output, " \r\n\t");
            var from = out.len -| self.guest_tail.len;
            while (from < out.len and out[from] & 0xC0 == 0x80) from += 1; // never start inside a UTF-8 character
            self.guest_tail_len = out.len - from;
            @memcpy(self.guest_tail[0..self.guest_tail_len], out[from..]);
            return error.GuestFailed;
        }
    }

    /// True if the lab can begin: the baked snapshot exists and, for a lab with flags, so does the record of
    /// the flags that were planted in it.
    pub fn isBuilt(self: *const Scenario) ScenarioError!bool {
        if (self.lab.kind == .script) return true; // always available: the starter file is written when it begins
        if (!try self.hasScenarioSnapshot()) return false;
        if (self.lab.flags.len == 0) return true;
        const store = self.store orelse return error.FlagRecord;
        return store.load(self.lab.id, self.lab.flags) != null;
    }

    fn hasScenarioSnapshot(self: *const Scenario) ScenarioError!bool {
        return self.provider.hasSnapshot(self.target(), self.snapshotName());
    }

    /// This preparation's flags; null for a lab without flags or one that is not prepared.
    pub fn record(self: *const Scenario) ?flags.Record {
        if (self.lab.flags.len == 0) return null;
        const store = self.store orelse return null;
        return store.load(self.lab.id, self.lab.flags);
    }

    /// Checks a flag the learner typed and remembers a correct one.
    pub fn submit(self: *const Scenario, text: []const u8) ScenarioError!flags.Answer {
        var rec = self.record() orelse return error.NoScenario;
        const result = flags.answer(&rec, text);
        if (result == .correct) try self.store.?.save(self.lab.id, self.lab.flags, rec);
        return result;
    }

    /// Remembers that the containment check passed on this preparation.
    pub fn markContained(self: *const Scenario) ScenarioError!void {
        var rec = self.record() orelse return;
        if (rec.contained) return;
        rec.contained = true;
        try self.store.?.save(self.lab.id, self.lab.flags, rec);
    }

    /// Builds the broken machine: restore the clean snapshot, boot, run setup and fault, shut down,
    /// snapshot. With `rebuild`, an existing scenario snapshot is replaced. On any failure the VM is
    /// stopped and the clean snapshot restored, so nothing half-built is left behind.
    pub fn build(self: *Scenario, rebuild: bool) ScenarioError!void {
        if (self.lab.symptom.len == 0) return error.NoSymptom;
        try self.check();
        try self.requireStopped();
        if (self.lab.kind == .script) return; // nothing to bake: see `begin`
        const t = self.target();
        if (!try self.provider.hasSnapshot(t, clean_snapshot)) return error.NoCleanSnapshot;
        if (self.lab.flags.len > 0 and self.store == null) return error.FlagRecord;
        // A snapshot whose flag record is gone cannot be used, so it is replaced without being asked.
        if (try self.hasScenarioSnapshot()) {
            if (!rebuild and try self.isBuilt()) return error.ScenarioExists;
            try self.provider.deleteSnapshot(t, self.snapshotName());
        }

        // New flags for every preparation.
        var arena = std.heap.ArenaAllocator.init(self.gpa);
        defer arena.deinit();
        var setup_text = self.lab.setup;
        var fault_text = self.lab.fault;
        var fresh: flags.Record = .{ .count = self.lab.flags.len };
        if (self.lab.flags.len > 0) {
            const store = self.store.?;
            try store.delete(self.lab.id);
            for (fresh.values[0..fresh.count]) |*v| v.* = flags.generate(store.io);
            var used: u8 = 0;
            setup_text = flags.expand(arena.allocator(), setup_text, self.lab.flags, &fresh.values, &used) catch return error.OutOfMemory;
            fault_text = flags.expand(arena.allocator(), fault_text, self.lab.flags, &fresh.values, &used) catch return error.OutOfMemory;
        }

        try self.provider.restoreSnapshot(t, clean_snapshot);
        errdefer {
            self.provider.stop(t) catch {};
            self.provider.restoreSnapshot(t, clean_snapshot) catch {};
        }
        try self.provider.start(t);
        try self.script(setup_text);
        try self.script(fault_text);
        try self.provider.stop(t);
        try self.provider.createSnapshot(t, self.snapshotName());
        if (self.lab.flags.len > 0) {
            self.store.?.save(self.lab.id, self.lab.flags, fresh) catch |e| {
                self.provider.deleteSnapshot(t, self.snapshotName()) catch {};
                return e;
            };
        }
    }

    /// Learner flow: restore the broken machine and boot it. Returns once the guest is reachable.
    pub fn begin(self: *Scenario) ScenarioError!void {
        try self.check();
        try self.requireStopped();
        if (self.lab.kind == .script) {
            // A scripting lab has nothing to bake: restore the clean machine, boot it, and write the starter file.
            if (!try self.provider.hasSnapshot(self.target(), clean_snapshot)) return error.NoCleanSnapshot;
            try self.provider.restoreSnapshot(self.target(), clean_snapshot);
            try self.provider.start(self.target());
            try self.script(self.lab.setup);
            return;
        }
        if (!try self.isBuilt()) return error.NoScenario;
        try self.provider.restoreSnapshot(self.target(), self.snapshotName());
        try self.provider.start(self.target());
    }

    /// Runs the lab's validation against the machine as it is now (the final state, not the commands used).
    pub fn validate(self: *Scenario) ScenarioError!Validated {
        // The guest may be restarting (a learner can restart it); wait for it before reading its state.
        _ = self.provider.waitReady(self.target(), 180);
        const r = try self.provider.runInGuest(self.gpa, self.target(), self.lab.validate.script);
        const v = self.lab.validate;
        const exit_ok = r.exit_code == v.expect_exit;
        const out_ok = v.expect_output_contains.len == 0 or std.mem.indexOf(u8, r.output, v.expect_output_contains) != null;
        return .{ .passed = exit_ok and out_ok, .exit_code = r.exit_code, .output = r.output };
    }

    /// Back to the starting problem: stop the VM, restore the scenario snapshot. Not started again.
    pub fn reset(self: *Scenario) ScenarioError!void {
        try self.check();
        const t = self.target();
        if (self.lab.kind == .script) {
            try self.provider.stop(t);
            try self.provider.restoreSnapshot(t, clean_snapshot);
            return;
        }
        if (!try self.isBuilt()) return error.NoScenario;
        try self.provider.stop(t);
        try self.provider.restoreSnapshot(t, self.snapshotName());
    }

    /// Ends the session: stop the VM, leaving whatever state the learner reached (the next `begin` restores).
    pub fn end(self: *Scenario) ScenarioError!void {
        try self.provider.stop(self.target());
    }
};

/// Chooses among the VMs that suit a lab's OS and distribution (given in preference order): the first
/// one where the lab's scenario is built. Otherwise (and always for a script lab, which has nothing to
/// build) the first with a clean snapshot, where it can start or be built. Otherwise the first VM, so
/// the caller can say what is missing. Null only for no VMs.
pub fn pickVm(gpa: std.mem.Allocator, prov: provider.Provider, vms: []const registry.Vm, lab: Lab) ?registry.Vm {
    // A VM whose snapshots cannot be listed (missing disk, say) must not hide a later good one.
    if (lab.kind != .script) for (vms) |vm| {
        var s = Scenario.init(gpa, prov, vm, lab);
        if (s.hasScenarioSnapshot() catch false) return vm;
    };
    for (vms) |vm| {
        if (prov.hasSnapshot(vm.target(), clean_snapshot) catch false) return vm;
    }
    return if (vms.len > 0) vms[0] else null;
}

// ---- tests -------------------------------------------------------------------

const mock = @import("../vm/mock.zig");

test "the lab VM is the one where the scenario is built, not just the first listed" {
    const gpa = std.testing.allocator;
    var parsed = try parse(gpa, scenario_toml, null);
    defer parsed.deinit();
    var spare = mock.Mock.init(gpa);
    defer spare.deinit();
    var built = mock.Mock.init(gpa);
    defer built.deinit();
    try built.provider().createSnapshot(testVm(true).target(), "winlab-scenario-labs.dns-broken");

    // One provider serves every VM, as QEMU does: it answers by the target's disk.
    const Router = struct {
        var a: *mock.Mock = undefined;
        var b: *mock.Mock = undefined;
        fn has(_: *anyopaque, t: provider.Target, snap: []const u8) provider.Error!bool {
            const m = if (std.mem.eql(u8, t.disk, "built.qcow2")) b else a;
            return m.provider().vtable.hasSnapshot(m, t, snap);
        }
    };
    Router.a = &spare;
    Router.b = &built;
    var vtable = spare.provider().vtable.*;
    vtable.hasSnapshot = Router.has;
    const prov: provider.Provider = .{ .ptr = &spare, .vtable = &vtable };

    var first = testVm(true);
    first.id = "spare";
    var second = testVm(true);
    second.id = "built";
    second.disk = "built.qcow2";

    try std.testing.expectEqualStrings("built", pickVm(gpa, prov, &.{ first, second }, parsed.lab).?.id);
    // Built nowhere: the VM with a clean snapshot, where it can be built; failing that, the first.
    try spare.provider().createSnapshot(first.target(), clean_snapshot);
    var bare = first;
    bare.id = "bare";
    bare.disk = "built.qcow2"; // answered by `built`, which has no clean snapshot
    var script = parsed.lab;
    script.kind = .script;
    try std.testing.expectEqualStrings("spare", pickVm(gpa, prov, &.{ bare, first }, script).?.id);
    var unbuilt = parsed.lab;
    unbuilt.id = "labs.not-built-anywhere";
    try std.testing.expectEqualStrings("spare", pickVm(gpa, prov, &.{ bare, first }, unbuilt).?.id);
    try std.testing.expectEqualStrings("bare", pickVm(gpa, prov, &.{bare}, unbuilt).?.id);
    try std.testing.expect(pickVm(gpa, prov, &.{}, parsed.lab) == null);
}

const sample_toml =
    \\schema_version = 1
    \\id = "labs.spooler-stopped"
    \\title = "Print Spooler stopped"
    \\summary = "The spooler is stopped; bring it back."
    \\lesson = "foundations.architecture"
    \\expected_changes = ["Stops the Print Spooler service"]
    \\hazards = ["Printing is unavailable in the guest until fixed"]
    \\scope = "single guest"
    \\privilege = "administrator"
    \\requires_snapshot = true
    \\cleanup_strategy = "snapshot-restore"
    \\setup = "set svc.Spooler=running"
    \\fault = "set svc.Spooler=stopped"
    \\[validate]
    \\script = "get svc.Spooler"
    \\expect_output_contains = "running"
    \\
;

fn testVm(training: bool) registry.Vm {
    return .{ .id = "vm1", .name = "Lab VM", .provider = "mock", .disk = "x.qcow2", .training_target = training };
}

test "manifest parses; unsafe manifests are rejected" {
    const gpa = std.testing.allocator;
    var p = try parse(gpa, sample_toml, null);
    defer p.deinit();
    try std.testing.expectEqualStrings("labs.spooler-stopped", p.lab.id);
    try std.testing.expect(p.lab.requires_snapshot);

    var f: Failure = .{};
    const no_snapshot = try std.mem.replaceOwned(u8, gpa, sample_toml, "requires_snapshot = true", "requires_snapshot = false");
    defer gpa.free(no_snapshot);
    try std.testing.expectError(error.InvalidLab, parse(gpa, no_snapshot, &f));
    try std.testing.expectEqualStrings("requires_snapshot", f.field);

    const no_cleanup = try std.mem.replaceOwned(u8, gpa, sample_toml, "cleanup_strategy = \"snapshot-restore\"", "cleanup_strategy = \"hope\"");
    defer gpa.free(no_cleanup);
    try std.testing.expectError(error.InvalidLab, parse(gpa, no_cleanup, &f));
}

test "full lifecycle: setup, fault, fix, validate, reset restores the guest" {
    const gpa = std.testing.allocator;
    var parsed = try parse(gpa, sample_toml, null);
    defer parsed.deinit();
    var m = mock.Mock.init(gpa);
    defer m.deinit();
    try m.put("svc.Spooler", "original");
    var r = Runner.init(gpa, m.provider(), testVm(true), parsed.lab);

    try r.prepare();
    try std.testing.expectEqualStrings("winlab-pre-labs.spooler-stopped", r.snapshotName());
    try r.setup();
    try r.injectFault();
    try std.testing.expectEqualStrings("stopped", m.get("svc.Spooler").?);

    const bad_check = try r.validate();
    defer gpa.free(bad_check.output);
    try std.testing.expect(!bad_check.passed);

    try m.put("svc.Spooler", "running"); // the learner's repair
    const good = try r.validate();
    defer gpa.free(good.output);
    try std.testing.expect(good.passed);

    const rep = r.reset();
    try std.testing.expect(rep.complete);
    try std.testing.expectEqualStrings("original", m.get("svc.Spooler").?);
    try std.testing.expect(!m.running);
    try std.testing.expectEqual(Phase.idle, r.phase);
    try std.testing.expect(!(try m.provider().hasSnapshot(testVm(true).target(), "winlab-pre-labs.spooler-stopped")));
}

test "refuses unregistered VMs, missing capabilities, wrong state and stale snapshots" {
    const gpa = std.testing.allocator;
    var parsed = try parse(gpa, sample_toml, null);
    defer parsed.deinit();
    var m = mock.Mock.init(gpa);
    defer m.deinit();

    var r = Runner.init(gpa, m.provider(), testVm(false), parsed.lab);
    try std.testing.expectError(error.NotTrainingTarget, r.prepare());

    var wrong = testVm(true);
    wrong.provider = "qemu";
    r = Runner.init(gpa, m.provider(), wrong, parsed.lab);
    try std.testing.expectError(error.ProviderMismatch, r.prepare());

    m.caps = .{ .power = true, .guest_exec = true };
    r = Runner.init(gpa, m.provider(), testVm(true), parsed.lab);
    try std.testing.expectError(error.MissingCapability, r.prepare());
    m.caps = .{ .snapshots = true, .guest_exec = true, .power = true };

    m.running = true;
    try std.testing.expectError(error.VmNotStopped, r.prepare());
    m.running = false;

    try m.provider().createSnapshot(testVm(true).target(), "winlab-pre-labs.spooler-stopped");
    try std.testing.expectError(error.StaleSnapshot, r.prepare());
    try std.testing.expect(!m.running); // nothing was started
}

test "steps must happen in order and nothing runs before prepare" {
    const gpa = std.testing.allocator;
    var parsed = try parse(gpa, sample_toml, null);
    defer parsed.deinit();
    var m = mock.Mock.init(gpa);
    defer m.deinit();
    var r = Runner.init(gpa, m.provider(), testVm(true), parsed.lab);
    try std.testing.expectError(error.OutOfOrder, r.setup());
    try std.testing.expectError(error.OutOfOrder, r.injectFault());
    try std.testing.expect(m.guest.count() == 0);
}

test "failed rollback is reported as incomplete, never as success" {
    const gpa = std.testing.allocator;
    var parsed = try parse(gpa, sample_toml, null);
    defer parsed.deinit();
    var m = mock.Mock.init(gpa);
    defer m.deinit();
    var r = Runner.init(gpa, m.provider(), testVm(true), parsed.lab);
    try r.prepare();
    try r.setup();
    try r.injectFault();
    m.fail_restore = true;
    const rep = r.reset();
    try std.testing.expect(!rep.complete);
    try std.testing.expect(!rep.restored);
    try std.testing.expect(rep.problem.len > 0);
}

test "a failing guest script stops the lab" {
    const gpa = std.testing.allocator;
    var parsed = try parse(gpa, sample_toml, null);
    defer parsed.deinit();
    var m = mock.Mock.init(gpa);
    defer m.deinit();
    var r = Runner.init(gpa, m.provider(), testVm(true), parsed.lab);
    try r.prepare();
    var lab = parsed.lab;
    lab.setup = "bogus command";
    r.lab = lab;
    try std.testing.expectError(error.GuestFailed, r.setup());
    try std.testing.expectEqual(Phase.prepared, r.phase);
}

const scenario_toml =
    \\schema_version = 1
    \\id = "labs.dns-broken"
    \\title = "Names do not resolve"
    \\summary = "DNS lookups fail."
    \\symptom = "Websites will not open by name, but pinging an address works."
    \\hints = ["Is it the network or the name lookup?", "Look at the DNS servers on the adapter."]
    \\expected_changes = ["Points the adapter at an unreachable DNS server"]
    \\scope = "single guest"
    \\requires_snapshot = true
    \\cleanup_strategy = "snapshot-restore"
    \\setup = "set dns=ok"
    \\fault = "set dns=bad"
    \\solution = "set dns=ok"
    \\[validate]
    \\script = "get dns"
    \\expect_output_contains = "ok"
    \\
;

test "baked scenario: build once, begin restores the broken machine, fixing and reset behave" {
    const gpa = std.testing.allocator;
    var parsed = try parse(gpa, scenario_toml, null);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("Websites will not open by name, but pinging an address works.", parsed.lab.symptom);
    try std.testing.expectEqual(@as(usize, 2), parsed.lab.hints.len);

    var m = mock.Mock.init(gpa);
    defer m.deinit();
    try m.put("dns", "ok");
    const vm = testVm(true);
    var s = Scenario.init(gpa, m.provider(), vm, parsed.lab);

    // Needs the clean snapshot first.
    try std.testing.expectError(error.NoCleanSnapshot, s.build(false));
    try m.provider().createSnapshot(vm.target(), clean_snapshot);

    try s.build(false);
    try std.testing.expect(try s.isBuilt());
    try std.testing.expect(!m.running);
    try std.testing.expectEqualStrings("bad", m.get("dns").?);
    try std.testing.expectError(error.ScenarioExists, s.build(false));

    // A learner session: the broken machine is restored and booted; the fault was NOT injected live.
    try m.put("dns", "changed-after-build");
    try s.begin();
    try std.testing.expect(m.running);
    try std.testing.expectEqualStrings("bad", m.get("dns").?);
    const before = try s.validate();
    defer gpa.free(before.output);
    try std.testing.expect(!before.passed);

    try m.put("dns", "ok"); // the learner repairs it
    const good = try s.validate();
    defer gpa.free(good.output);
    try std.testing.expect(good.passed);

    // Reset returns to the broken starting point, stopped.
    try s.reset();
    try std.testing.expect(!m.running);
    try std.testing.expectEqualStrings("bad", m.get("dns").?);

    // Rebuild replaces the scenario snapshot.
    try s.build(true);
    try std.testing.expect(try s.isBuilt());
}

test "scenario builder refuses bad inputs and a failed build restores the clean state" {
    const gpa = std.testing.allocator;
    var parsed = try parse(gpa, scenario_toml, null);
    defer parsed.deinit();
    var m = mock.Mock.init(gpa);
    defer m.deinit();
    try m.put("dns", "ok");
    try m.provider().createSnapshot(testVm(true).target(), clean_snapshot);

    var no_symptom = parsed.lab;
    no_symptom.symptom = "";
    var s = Scenario.init(gpa, m.provider(), testVm(true), no_symptom);
    try std.testing.expectError(error.NoSymptom, s.build(false));

    s = Scenario.init(gpa, m.provider(), testVm(false), parsed.lab);
    try std.testing.expectError(error.NotTrainingTarget, s.build(false));

    var broken = parsed.lab;
    broken.fault = "bogus command"; // the mock answers 127 to unknown commands
    s = Scenario.init(gpa, m.provider(), testVm(true), broken);
    try std.testing.expectError(error.GuestFailed, s.build(false));
    try std.testing.expectEqual(@as(u32, 127), s.guest_exit);
    try std.testing.expect(!m.running);
    try std.testing.expectEqualStrings("ok", m.get("dns").?); // clean state restored
    try std.testing.expect(!(try s.isBuilt()));
}

test "network defaults to open, accepts isolated, and rejects anything else" {
    const gpa = std.testing.allocator;
    var plain = try parse(gpa, sample_toml, null);
    defer plain.deinit();
    try std.testing.expect(!plain.lab.isolated);
    for ([_]struct { line: []const u8, ok: bool, isolated: bool }{
        .{ .line = "network = \"isolated\"\n", .ok = true, .isolated = true },
        .{ .line = "network = \"open\"\n", .ok = true, .isolated = false },
        .{ .line = "network = \"Isolated\"\n", .ok = false, .isolated = false },
        .{ .line = "network = false\n", .ok = false, .isolated = false },
    }) |case| {
        const full = try std.mem.concat(gpa, u8, &.{ case.line, sample_toml });
        defer gpa.free(full);
        if (case.ok) {
            var p = try parse(gpa, full, null);
            defer p.deinit();
            try std.testing.expectEqual(case.isolated, p.lab.isolated);
        } else try std.testing.expectError(error.InvalidLab, parse(gpa, full, null));
    }
}

test "an isolated lab starts its VM isolated, as a lab run and as a scenario" {
    const gpa = std.testing.allocator;
    var m = mock.Mock.init(gpa);
    defer m.deinit();
    const Spy = struct {
        var starts: u32 = 0;
        var isolated_starts: u32 = 0;
        var inner: *const fn (*anyopaque, provider.Target) provider.Error!void = undefined;
        fn start(ptr: *anyopaque, t: provider.Target) provider.Error!void {
            starts += 1;
            if (t.isolated) isolated_starts += 1;
            return inner(ptr, t);
        }
    };
    var vtable = m.provider().vtable.*;
    Spy.inner = vtable.start;
    vtable.start = Spy.start;
    const prov: provider.Provider = .{ .ptr = &m, .vtable = &vtable };

    const text = try std.mem.concat(gpa, u8, &.{ "network = \"isolated\"\n", sample_toml });
    defer gpa.free(text);
    var parsed = try parse(gpa, text, null);
    defer parsed.deinit();

    var runner = Runner.init(gpa, prov, testVm(true), parsed.lab);
    try runner.prepare();
    _ = runner.reset();
    try std.testing.expectEqual(@as(u32, 1), Spy.starts);
    try std.testing.expectEqual(@as(u32, 1), Spy.isolated_starts);
}

const flag_toml = scenario_toml ++
    \\[[flags]]
    \\name = "planted"
    \\question = "Where is it?"
    \\recover = "get secret"
    \\
;

fn flagLabText(gpa: std.mem.Allocator, fault: []const u8) ![]u8 {
    return std.mem.replaceOwned(u8, gpa, flag_toml, "fault = \"set dns=bad\"", fault);
}

test "flags must be planted, named properly and only in scenarios" {
    const gpa = std.testing.allocator;
    const good = try flagLabText(gpa, "fault = \"set secret={{flag_b64:planted}}\"");
    defer gpa.free(good);
    var p = try parse(gpa, good, null);
    defer p.deinit();
    try std.testing.expectEqual(@as(usize, 1), p.lab.flags.len);

    for ([_][]const u8{
        "fault = \"set dns=bad\"", // the flag is never planted
        "fault = \"set secret={{flag:other}}\"", // no such flag
        "fault = \"set secret={{flag:planted\"", // unfinished placeholder
    }) |fault| {
        const text = try flagLabText(gpa, fault);
        defer gpa.free(text);
        var f: Failure = .{};
        try std.testing.expectError(error.InvalidLab, parse(gpa, text, &f));
        try std.testing.expectEqualStrings("flags", f.field);
    }
}

test "each preparation plants new flags; answers and containment are remembered" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const text = try flagLabText(gpa, "fault = \"set secret={{flag:planted}}\"");
    defer gpa.free(text);
    var parsed = try parse(gpa, text, null);
    defer parsed.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(dir);

    var m = mock.Mock.init(gpa);
    defer m.deinit();
    const vm = testVm(true);
    try m.provider().createSnapshot(vm.target(), clean_snapshot);
    var s = Scenario.init(gpa, m.provider(), vm, parsed.lab);
    try std.testing.expectError(error.FlagRecord, s.build(false)); // nowhere to keep them
    try std.testing.expect(!m.running);
    s.store = .{ .io = io, .vm_dir = dir };

    try s.build(false);
    const first = s.record().?;
    try std.testing.expectEqualStrings(&first.values[0], m.get("secret").?);
    try std.testing.expectEqual(flags.Answer.wrong, try s.submit("WL{000000000000}"));
    try std.testing.expectEqual(flags.Answer{ .correct = 0 }, try s.submit(&first.values[0]));
    try std.testing.expect(!s.record().?.complete());
    try s.markContained();
    try std.testing.expect(s.record().?.complete());
    try std.testing.expectError(error.ScenarioExists, s.build(false));

    // Rebuilding draws a new flag and forgets the progress; the old answer is now wrong.
    try s.build(true);
    const second = s.record().?;
    try std.testing.expect(!std.mem.eql(u8, &first.values[0], &second.values[0]));
    try std.testing.expectEqual(@as(usize, 1), second.left());
    try std.testing.expect(!second.contained);
    try std.testing.expectEqual(flags.Answer.wrong, try s.submit(&first.values[0]));

    // Without its record a snapshot cannot be played: it counts as unbuilt and is replaced.
    try s.store.?.delete(parsed.lab.id);
    try std.testing.expect(!try s.isBuilt());
    try std.testing.expectError(error.NoScenario, s.begin());
    try s.build(false);
    try s.begin();
    try std.testing.expectEqualStrings(&s.record().?.values[0], m.get("secret").?);

    // A build that fails leaves no flags behind.
    try s.end();
    var broken = parsed.lab;
    broken.setup = "bogus command";
    s.lab = broken;
    try std.testing.expectError(error.GuestFailed, s.build(true));
    try std.testing.expect(s.record() == null);

    var runner = Runner.init(gpa, m.provider(), vm, parsed.lab);
    try std.testing.expectError(error.FlagsNeedScenario, runner.prepare());
}
