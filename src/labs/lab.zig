//! Lab manifests (TOML) and the lab lifecycle (decision record 0006). A lab
//! declares what it changes, what it needs and how it is undone; the runner
//! refuses to touch anything that is not a registered training target and
//! reports incomplete cleanup instead of success.
const std = @import("std");
const toml = @import("toml");
const manifest = @import("../content/manifest.zig");
const script_lab = @import("script_lab.zig");
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

// ---- lifecycle -------------------------------------------------------------

pub const Phase = enum { idle, prepared, set_up, fault_injected };

pub const RunError = error{
    NotTrainingTarget,
    ProviderMismatch,
    MissingCapability,
    VmNotStopped,
    StaleSnapshot,
    OutOfOrder,
    GuestFailed,
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
        try self.check();
        if ((try self.provider.state(self.vm.target())) != .stopped) return error.VmNotStopped;
        const name = std.fmt.bufPrint(&self.snap_buf, "winlab-pre-{s}", .{self.lab.id}) catch return error.ProviderFailed;
        self.snap_len = name.len;
        if (!provider.validSnapshotName(name)) return error.ProviderFailed;
        if (self.lab.requires_snapshot) {
            if (try self.provider.hasSnapshot(self.vm.target(), name)) return error.StaleSnapshot;
            try self.provider.createSnapshot(self.vm.target(), name);
        }
        self.provider.start(self.vm.target()) catch |e| {
            // Do not leave a snapshot behind for a lab that never began.
            if (self.lab.requires_snapshot) self.provider.deleteSnapshot(self.vm.target(), name) catch {};
            return e;
        };
        self.phase = .prepared;
    }

    fn runScript(self: *Runner, script: []const u8) RunError!void {
        if (script.len == 0) return;
        const r = try self.provider.runInGuest(self.gpa, self.vm.target(), script);
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
        const r = try self.provider.runInGuest(self.gpa, self.vm.target(), self.lab.validate.script);
        const v = self.lab.validate;
        const exit_ok = r.exit_code == v.expect_exit;
        const out_ok = v.expect_output_contains.len == 0 or std.mem.indexOf(u8, r.output, v.expect_output_contains) != null;
        return .{ .passed = exit_ok and out_ok, .exit_code = r.exit_code, .output = r.output };
    }

    /// Rolls the VM back. Never claims success it cannot prove: every failure is reported.
    pub fn reset(self: *Runner) ResetReport {
        var rep: ResetReport = .{};
        const t = self.vm.target();
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
} || RunError;

pub const Scenario = struct {
    gpa: std.mem.Allocator,
    provider: provider.Provider,
    vm: registry.Vm,
    lab: Lab,
    name_buf: [96]u8 = undefined,
    name_len: usize = 0,

    pub fn init(gpa: std.mem.Allocator, prov: provider.Provider, vm: registry.Vm, lab: Lab) Scenario {
        var s: Scenario = .{ .gpa = gpa, .provider = prov, .vm = vm, .lab = lab };
        const n = std.fmt.bufPrint(&s.name_buf, "winlab-scenario-{s}", .{lab.id}) catch "";
        s.name_len = n.len;
        return s;
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
        if ((try self.provider.state(self.vm.target())) != .stopped) return error.VmNotStopped;
    }

    fn script(self: *Scenario, text: []const u8) ScenarioError!void {
        if (text.len == 0) return;
        const r = try self.provider.runInGuest(self.gpa, self.vm.target(), text);
        defer self.gpa.free(r.output);
        if (r.exit_code != 0) {
            std.debug.print("guest script failed (exit {d}):\n{s}\n", .{ r.exit_code, r.output });
            return error.GuestFailed;
        }
    }

    /// True if the baked snapshot exists.
    pub fn isBuilt(self: *const Scenario) ScenarioError!bool {
        if (self.lab.kind == .script) return true; // always available: the starter file is written when it begins
        return self.provider.hasSnapshot(self.vm.target(), self.snapshotName());
    }

    /// Builds the broken machine: restore the clean snapshot, boot, run setup and fault, shut down,
    /// snapshot. With `rebuild`, an existing scenario snapshot is replaced. On any failure the VM is
    /// stopped and the clean snapshot restored, so nothing half-built is left behind.
    pub fn build(self: *Scenario, rebuild: bool) ScenarioError!void {
        if (self.lab.symptom.len == 0) return error.NoSymptom;
        try self.check();
        try self.requireStopped();
        if (self.lab.kind == .script) return; // nothing to bake: see `begin`
        const t = self.vm.target();
        if (!try self.provider.hasSnapshot(t, clean_snapshot)) return error.NoCleanSnapshot;
        if (try self.isBuilt()) {
            if (!rebuild) return error.ScenarioExists;
            try self.provider.deleteSnapshot(t, self.snapshotName());
        }
        try self.provider.restoreSnapshot(t, clean_snapshot);
        errdefer {
            self.provider.stop(t) catch {};
            self.provider.restoreSnapshot(t, clean_snapshot) catch {};
        }
        try self.provider.start(t);
        try self.script(self.lab.setup);
        try self.script(self.lab.fault);
        try self.provider.stop(t);
        try self.provider.createSnapshot(t, self.snapshotName());
    }

    /// Learner flow: restore the broken machine and boot it. Returns once the guest is reachable.
    pub fn begin(self: *Scenario) ScenarioError!void {
        try self.check();
        try self.requireStopped();
        if (self.lab.kind == .script) {
            // A scripting lab has nothing to bake: restore the clean machine, boot it, and write the starter file.
            if (!try self.provider.hasSnapshot(self.vm.target(), clean_snapshot)) return error.NoCleanSnapshot;
            try self.provider.restoreSnapshot(self.vm.target(), clean_snapshot);
            try self.provider.start(self.vm.target());
            try self.script(self.lab.setup);
            return;
        }
        if (!try self.isBuilt()) return error.NoScenario;
        try self.provider.restoreSnapshot(self.vm.target(), self.snapshotName());
        try self.provider.start(self.vm.target());
    }

    /// Runs the lab's validation against the machine as it is now (the final state, not the commands used).
    pub fn validate(self: *Scenario) ScenarioError!Validated {
        // The guest may be restarting (a learner can restart it); wait for it before reading its state.
        _ = self.provider.waitReady(self.vm.target(), 180);
        const r = try self.provider.runInGuest(self.gpa, self.vm.target(), self.lab.validate.script);
        const v = self.lab.validate;
        const exit_ok = r.exit_code == v.expect_exit;
        const out_ok = v.expect_output_contains.len == 0 or std.mem.indexOf(u8, r.output, v.expect_output_contains) != null;
        return .{ .passed = exit_ok and out_ok, .exit_code = r.exit_code, .output = r.output };
    }

    /// Back to the starting problem: stop the VM, restore the scenario snapshot. Not started again.
    pub fn reset(self: *Scenario) ScenarioError!void {
        try self.check();
        const t = self.vm.target();
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
        try self.provider.stop(self.vm.target());
    }
};

// ---- tests -------------------------------------------------------------------

const mock = @import("../vm/mock.zig");

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
    try std.testing.expect(!m.running);
    try std.testing.expectEqualStrings("ok", m.get("dns").?); // clean state restored
    try std.testing.expect(!(try s.isBuilt()));
}
