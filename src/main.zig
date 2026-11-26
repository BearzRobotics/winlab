const std = @import("std");
const winlab = @import("winlab");
const terminal_host = @import("ui/terminal_host.zig");
const gui = @import("ui/gui.zig");
comptime {
    _ = terminal_host;
    _ = @import("ui/highlight.zig");
}

const usage =
    \\usage: winlab                     open the course (from settings content-path, next to winlab.exe, share/winlab on Linux, or the settings folder %APPDATA%\WinLab / ~/.config/WinLab)
    \\       winlab status              print version and shell capability status
    \\       winlab browse [course-dir] open the course browser
    \\       winlab check <course-dir>  validate lesson manifests, content files and prerequisites
    \\       winlab coverage [exam-id]  show certification domains covered by lessons and labs
    \\       winlab paths               list the learning paths with size and level
    \\       winlab view <file.md>      show one Markdown file in the reader
    \\       winlab terminal <shell>    open a real shell (cmd, powershell, pwsh or bash) in a terminal window
    \\       winlab image list          show installation media WinLab can download
    \\       winlab image fetch <id>    download one (asks first; HTTPS via the system curl.exe)
    \\       winlab vm install <image-id> <vm-id>   build a training VM unattended (runs until the guest is ready)
    \\       winlab vm resume <vm-id>   continue an interrupted install, relaunching QEMU after each restart
    \\       winlab vm list            registered VMs, their state, clean snapshot and built scenarios
    \\       winlab vm remove <vm-id>  delete a training VM WinLab created (asks first)
    \\       winlab vm snapshot|restore|delete-snapshot <vm-id> <name>
    \\       winlab vm autologin <vm-id> <snapshot>   make a saved snapshot log in by itself (boots it)
    \\       winlab lab build <lab.toml> <vm-id> [--rebuild]   bake a broken-machine scenario
    \\       winlab lab start|check|reset|end <lab.toml> <vm-id>   run a scenario as a learner would
    \\       winlab lab verify <lab.toml> <vm-id>   prove a scenario: broken, fixable, and reset restores it
    \\       winlab lab selftest <lab.toml> <vm-id>   run a lab end to end with its authoring solution
    \\
;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len == 2 and std.mem.eql(u8, args[1], "browse")) return browse(init, null);
    if (args.len == 3) {
        const cmd = args[1];
        if (std.mem.eql(u8, cmd, "view")) return view(init, args[2]);
        if (std.mem.eql(u8, cmd, "browse")) return browse(init, args[2]);
        if (std.mem.eql(u8, cmd, "check")) return check(gpa, io, args[2]);
        if (std.mem.eql(u8, cmd, "terminal")) return terminal(init, args[2]);
    }
    if (args.len == 3 and std.mem.eql(u8, args[1], "image") and std.mem.eql(u8, args[2], "list")) return imageList(init);
    if (args.len == 4 and std.mem.eql(u8, args[1], "image") and std.mem.eql(u8, args[2], "fetch")) return imageFetch(init, args[3]);
    if (args.len == 4 and std.mem.eql(u8, args[1], "image") and std.mem.eql(u8, args[2], "editions")) return imageEditions(init, args[3]);
    if ((args.len == 7 or args.len == 8) and std.mem.eql(u8, args[1], "image") and std.mem.eql(u8, args[2], "add")) return imageAdd(init, args);
    if (args.len == 4 and std.mem.eql(u8, args[1], "vm") and std.mem.eql(u8, args[2], "install")) {
        std.debug.print("usage: winlab vm install <image-id> <vm-id>\n", .{});
        std.process.exit(2);
    }
    if (args.len == 5 and std.mem.eql(u8, args[1], "vm") and std.mem.eql(u8, args[2], "install")) return vmInstall(init, args[3], args[4]);
    if (args.len == 5 and std.mem.eql(u8, args[1], "vm") and (std.mem.eql(u8, args[2], "snapshot") or std.mem.eql(u8, args[2], "restore") or std.mem.eql(u8, args[2], "delete-snapshot")))
        return vmSnapshotOp(init, args[2], args[3], args[4]);
    if (args.len == 4 and std.mem.eql(u8, args[1], "vm") and std.mem.eql(u8, args[2], "resume")) return vmResume(init, args[3]);
    if (args.len == 5 and std.mem.eql(u8, args[1], "vm") and std.mem.eql(u8, args[2], "autologin")) return vmAutologin(init, args[3], args[4]);
    if (args.len == 4 and std.mem.eql(u8, args[1], "vm") and std.mem.eql(u8, args[2], "remove")) return vmRemove(init, args[3]);
    if (args.len == 4 and std.mem.eql(u8, args[1], "vm") and std.mem.eql(u8, args[2], "reboot-test")) return vmRebootTest(init, args[3]);
    if (args.len == 3 and std.mem.eql(u8, args[1], "vm") and std.mem.eql(u8, args[2], "list")) return vmList(init);
    if (args.len == 2 and std.mem.eql(u8, args[1], "paths")) return pathsCmd(init);
    if (args.len == 2 and std.mem.eql(u8, args[1], "coverage")) return coverageCmd(init, null);
    if (args.len == 3 and std.mem.eql(u8, args[1], "coverage")) return coverageCmd(init, args[2]);
    if (args.len == 5 and std.mem.eql(u8, args[1], "lab") and std.mem.eql(u8, args[2], "selftest")) return labSelfTest(init, args[3], args[4]);
    if (args.len >= 5 and std.mem.eql(u8, args[1], "lab") and std.mem.eql(u8, args[2], "verify-set")) return labVerifySet(init, args[3], args[4..]);
    if ((args.len == 5 or args.len == 6) and std.mem.eql(u8, args[1], "lab")) {
        const sub = args[2];
        const rebuild = args.len == 6 and std.mem.eql(u8, args[5], "--rebuild");
        if (args.len == 6 and !rebuild) {
            std.debug.print("{s}", .{usage});
            std.process.exit(2);
        }
        if (std.mem.eql(u8, sub, "build")) return scenarioCmd(init, .build, args[3], args[4], rebuild);
        if (!rebuild) {
            if (std.mem.eql(u8, sub, "start")) return scenarioCmd(init, .start, args[3], args[4], false);
            if (std.mem.eql(u8, sub, "check")) return scenarioCmd(init, .check, args[3], args[4], false);
            if (std.mem.eql(u8, sub, "reset")) return scenarioCmd(init, .reset, args[3], args[4], false);
            if (std.mem.eql(u8, sub, "end")) return scenarioCmd(init, .end, args[3], args[4], false);
            if (std.mem.eql(u8, sub, "verify")) return scenarioCmd(init, .verify, args[3], args[4], false);
        }
    }
    if (args.len == 2 and std.mem.eql(u8, args[1], "status")) return status(init);
    if (args.len != 1) {
        std.debug.print("{s}", .{usage});
        std.process.exit(2);
    }
    return browse(init, null);
}

fn status(init: std.process.Init) !void {
    var buf: [2048]u8 = undefined;
    var fw: std.Io.File.Writer = .init(.stdout(), init.io, &buf);
    const out = &fw.interface;

    try out.print("{s} {s} (Zig {s})\n\nShell capability status:\n", .{
        winlab.version.app_name, winlab.version.app_version, winlab.version.pinned_zig,
    });

    const path = init.environ_map.get("PATH") orelse "";
    for (winlab.shell_discovery.here) |sh| {
        const found = winlab.shell_discovery.findOnPath(init.io, path, sh.executable());
        try out.print("  {s}: {s}\n", .{ sh.displayName(), if (found) "found" else if (sh.isOptional()) "not installed (optional)" else "NOT FOUND" });
    }

    var cfg = loadSettings(init);
    defer cfg.deinit();
    try out.writeAll("\nVirtual machine labs (optional):\n");
    if (try winlab.vm_qemu.discover(init.gpa, init.io, path, cfg.settings.qemu_path)) |found| {
        var tools = found;
        defer tools.deinit();
        try out.print("  QEMU: {s}\n  Location: {s}\n  Hardware acceleration ({s}): {s}\n", .{ tools.version, tools.qemu_system, if (winlab.platform.is_windows) "WHPX" else "KVM", if (tools.hw_accel) "available" else "not available (slow software emulation only)" });
    } else {
        try out.print("  QEMU: not found\n  {s}\n", .{winlab.vm_qemu.install_guidance});
    }
    try out.flush();
}

/// A page whose parsed Markdown lives in the caller's arena (freed when the window closes).
fn renderPage(arena: std.mem.Allocator, title: []const u8, markdown: []const u8) !gui.Page {
    // The tree may point into its source text, so it gets its own copy.
    const source = try arena.dupe(u8, markdown);
    const doc = try arena.create(winlab.md.Document);
    doc.* = try winlab.md.Document.parse(arena, source, .{ .extensions = winlab.md.Extensions.gfm });
    return .{ .title = try arena.dupe(u8, title), .root = doc.root, .doc = doc };
}

/// Reads the diagrams a lesson names, from its own folder. One that is missing or not allowed is left out,
/// so the window shows the text version below it; with `problems`, each is also reported and counted.
fn loadDrawings(arena: std.mem.Allocator, io: std.Io, root: std.Io.Dir, lesson_dir: []const u8, doc: *winlab.md.Node, problems: ?*usize) ![]const gui.Drawing {
    var found: std.ArrayList(gui.Drawing) = .empty;
    var next = doc.first_child;
    while (next) |node| : (next = node.next) {
        if (node.kind != .paragraph) continue;
        const path = winlab.diagram.imageOnly(node) orelse continue;
        const rel = if (lesson_dir.len == 0) try arena.dupe(u8, path) else try std.fmt.allocPrint(arena, "{s}/{s}", .{ lesson_dir, path });
        var failure: winlab.diagram.Failure = .{};
        const why: []const u8 = blk: {
            const source = root.readFileAlloc(io, rel, arena, .limited(winlab.diagram.max_bytes + 1)) catch |e| break :blk @errorName(e);
            const parsed = winlab.diagram.parse(arena, source, &failure) catch |e| switch (e) {
                error.InvalidDiagram => break :blk try std.fmt.allocPrint(arena, "line {d}: {s}", .{ failure.line, failure.message }),
                error.OutOfMemory => return error.OutOfMemory,
            };
            const drawing = try arena.create(winlab.diagram.Diagram);
            drawing.* = parsed;
            try found.append(arena, .{ .path = try arena.dupe(u8, path), .drawing = drawing });
            if (winlab.diagram.textFallback(node) == null) break :blk "needs a ```text block right after it (shown in plain text and when copying)";
            continue;
        };
        if (problems) |count| {
            std.debug.print("{s}: {s}\n", .{ rel, why });
            count.* += 1;
        }
    }
    return found.items;
}

/// `%SystemRoot%\Fonts`, where Segoe UI and Consolas live.
fn fontsDir(init: std.process.Init) []const u8 {
    if (!winlab.platform.is_windows) return ""; // DVUI's bundled font is used
    const root = init.environ_map.get("SystemRoot") orelse "C:\\Windows";
    return std.fs.path.join(init.arena.allocator(), &.{ root, "Fonts" }) catch "";
}

const max_lesson_bytes = 8 * 1024 * 1024;

fn view(init: std.process.Init, path: []const u8) !void {
    const gpa = init.gpa;
    const io = init.io;
    var cfg = loadSettings(init);
    const dark = gui.isDark(cfg.settings.theme);
    defer cfg.deinit();
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const source = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(max_lesson_bytes));
    defer gpa.free(source);
    const pages = [_]gui.Page{try renderPage(arena_state.allocator(), path, source)};
    try gui.run(gpa, "WinLab - Reader", &pages, .{ .io = io, .text_scale = cfg.settings.text_scale, .dark = dark, .fonts_dir = fontsDir(init) });
}

fn openCourse(gpa: std.mem.Allocator, io: std.Io, dir: []const u8) !struct { root: std.Io.Dir, catalog: winlab.catalog.Catalog } {
    var root = std.Io.Dir.cwd().openDir(io, dir, .{ .iterate = true }) catch |err| {
        std.debug.print("{s}: cannot open course directory: {t}\n", .{ dir, err });
        std.process.exit(1);
    };
    errdefer root.close(io);
    return .{ .root = root, .catalog = try winlab.catalog.load(gpa, io, root) };
}

/// The Lab button's engine: scenarios from `labs/*.toml` on one registered training VM.
/// `run` is called on a worker thread by the lab window; `fixed` on the UI thread.
/// A usable lab VM and what runs in it.
const LabVm = struct {
    vm: winlab.vm_registry.Vm,
    linux: bool,
    distro: []const u8,
    login: ?winlab.vm_autologin.Login,
};

fn noVmText(lab: winlab.lab.Lab) []const u8 {
    return if (lab.target == .windows)
        "No Windows lab VM is set up. Build one with: winlab vm install windows-server-2022-eval <vm-id>"
    else if (std.mem.eql(u8, lab.distro, "almalinux"))
        "No AlmaLinux lab VM is set up. Build one with: winlab vm install almalinux-9-cloud <vm-id>"
    else if (std.mem.eql(u8, lab.distro, "ubuntu"))
        "No Ubuntu lab VM is set up. Build one with: winlab vm install ubuntu-2404-cloud <vm-id>"
    else
        "No Linux lab VM is set up. Build one with: winlab vm install ubuntu-2404-cloud <vm-id> (or almalinux-9-cloud)";
}

const LabBackend = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    tools: winlab.vm_qemu.Tools,
    q: winlab.vm_qemu.Qemu,
    reg: winlab.vm_registry.Registry,
    /// Every usable training VM; a lab runs on the first one matching its target OS and distribution.
    cands: []const LabVm,
    parsed: []winlab.lab.Parsed,
    texts: [][]u8,
    store: *ProgressStore,
    busy: std.atomic.Value(bool) = .init(false),

    fn deinit(self: *LabBackend) void {
        for (self.parsed, self.texts) |*p, t| {
            p.deinit();
            self.gpa.free(t);
        }
        self.gpa.free(self.parsed);
        self.gpa.free(self.texts);
        self.reg.deinit();
        self.tools.deinit();
    }

    fn pickVm(self: *LabBackend, lab: winlab.lab.Lab) ?winlab.vm_registry.Vm {
        var matching: std.ArrayList(winlab.vm_registry.Vm) = .empty;
        defer matching.deinit(self.gpa);
        for (self.cands) |c| {
            if (c.linux != (lab.target == .linux)) continue;
            if (lab.distro.len > 0 and !std.mem.eql(u8, lab.distro, c.distro)) continue;
            matching.append(self.gpa, c.vm) catch return null;
        }
        return winlab.lab.pickVm(self.gpa, self.q.provider(), matching.items, lab);
    }

    /// The login of the VM this lab runs on, for the lab window. UI thread; the strings live as long as the app.
    fn login(ctx: *anyopaque, idx: usize) ?gui.LabLogin {
        const self: *LabBackend = @ptrCast(@alignCast(ctx));
        const vm = self.pickVm(self.parsed[idx].lab) orelse return null;
        for (self.cands) |c| {
            if (!std.mem.eql(u8, c.vm.id, vm.id)) continue;
            const l = c.login orelse return null;
            return .{ .vm = c.vm.id, .user = l.user, .password = l.password, .linux = c.linux };
        }
        return null;
    }

    fn errorText(e: anyerror) []const u8 {
        return switch (e) {
            error.NoScenario => "This lab has not been prepared yet. Press Start to prepare it.",
            error.NoCleanSnapshot => "The lab VM has no snapshot named winlab-clean. Take one of the freshly installed, stopped VM first.",
            error.NoSymptom => "This lab has no problem description, so it cannot be prepared.",
            error.GuestFailed => "A setup script failed inside the VM.",
            error.VmNotStopped => "The lab VM is already running, perhaps for another lab. Stop it first.",
            error.NotTrainingTarget => "That VM is not marked as a training target.",
            error.MissingCapability => "This VM cannot be controlled (no guest access is set up for it).",
            error.ProviderFailed => "Could not reach the lab VM. Is it running?",
            error.WrongState => "The VM is in the wrong state for that step.",
            else => "The step failed.",
        };
    }

    fn run(ctx: *anyopaque, idx: usize, op: gui.Op) gui.Outcome {
        const self: *LabBackend = @ptrCast(@alignCast(ctx));
        if (self.busy.swap(true, .acquire)) return gui.Outcome.make(false, false, "Another lab step is still running.");
        defer self.busy.store(false, .release);
        const lab = self.parsed[idx].lab;
        const vm = self.pickVm(lab) orelse return gui.Outcome.make(false, false, noVmText(lab));
        var s = winlab.lab.Scenario.init(self.gpa, self.q.provider(), vm, lab);
        switch (op) {
            .start, .prepare => {
                if (op == .prepare) {
                    // The command line may have built it since Start was pressed.
                    s.build(false) catch |e| if (e != error.ScenarioExists) {
                        var failed = prepareFailed(&s, e);
                        failed.needs_prepare = true;
                        return failed;
                    };
                }
                s.begin() catch |e| {
                    if (e != error.NoScenario) return gui.Outcome.make(false, false, errorText(e));
                    var unbuilt = gui.Outcome.make(false, false, prepare_prompt);
                    unbuilt.needs_prepare = true;
                    return unbuilt;
                };
                if (self.parsed[idx].lab.kind == .script) {
                    var buf: [200]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "The lab VM is running. Write your script in the VM and save it as {s}, then press Check.", .{self.parsed[idx].lab.script_path}) catch "The lab VM is running.";
                    return gui.Outcome.make(true, false, msg);
                }
                return gui.Outcome.make(true, false, "The lab VM is running.");
            },
            .check => {
                const r = s.validate() catch |e| return gui.Outcome.make(false, false, errorText(e));
                defer self.gpa.free(r.output);
                if (self.parsed[idx].lab.kind == .script) {
                    // For a script lab the harness output is the feedback (which tests failed and how).
                    const text = trimOut(r.output);
                    return gui.Outcome.make(true, r.passed, text);
                }
                return gui.Outcome.make(true, r.passed, if (r.passed) "Check passed: the machine is in the expected state." else "Check failed: the problem is still there.");
            },
            .reset => {
                s.reset() catch |e| return gui.Outcome.make(false, false, errorText(e));
                return gui.Outcome.make(true, false, "Back at the starting problem.");
            },
            .end => {
                s.end() catch |e| return gui.Outcome.make(false, false, errorText(e));
                return gui.Outcome.make(true, false, "The lab VM is stopped.");
            },
        }
    }

    const prepare_prompt = "This lab needs to be prepared once. Press \"Prepare and start\": WinLab boots the lab VM, " ++
        "sets up the problem and saves a snapshot. It takes a few minutes, and some labs need internet in the VM. " ++
        "As with Start, changes left in the lab VM from earlier are discarded.";

    fn prepareFailed(s: *const winlab.lab.Scenario, e: anyerror) gui.Outcome {
        var buf: [gui.Outcome.max_len]u8 = undefined;
        const msg = if (e == error.GuestFailed)
            std.fmt.bufPrint(&buf, "Preparing failed: a setup script exited with {d} in the VM. {s}", .{ s.guest_exit, s.failedOutput() })
        else
            std.fmt.bufPrint(&buf, "Preparing failed: {s}", .{errorText(e)});
        return gui.Outcome.make(false, false, msg catch "Preparing failed.");
    }

    /// A lab was fixed: record it in the learner's progress (separately from lesson reading).
    fn fixed(ctx: *anyopaque, idx: usize) void {
        const self: *LabBackend = @ptrCast(@alignCast(ctx));
        if (!self.store.enabled) return;
        self.store.progress.setStatus(self.parsed[idx].lab.id, .completed) catch return;
        _ = ProgressStore.save(self.store, &self.store.progress);
    }
};

/// Loads scenario labs and, when a training VM and QEMU are available, a backend for them.
/// Returns the lab list for the window (empty: no Lab button) and sets `note` when labs exist but cannot run.
fn openLabs(init: std.process.Init, cfg: *const winlab.settings.Loaded, root: []const u8, store: *ProgressStore, backend: *LabBackend, backend_ready: *bool, note: *[]const u8) ![]gui.Lab {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();
    const dir_path = try std.fs.path.join(arena, &.{ root, "labs" });
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return &.{};
    defer dir.close(io);

    var parsed: std.ArrayList(winlab.lab.Parsed) = .empty;
    var texts: std.ArrayList([]u8) = .empty;
    var entries: std.ArrayList(gui.Lab) = .empty;
    var it = dir.iterate();
    while (try it.next(io)) |e| {
        if (e.kind != .file or !std.mem.endsWith(u8, e.name, ".toml")) continue;
        const text = dir.readFileAlloc(io, e.name, gpa, .limited(256 * 1024)) catch continue;
        var failure: winlab.lab.Failure = .{};
        const p = winlab.lab.parse(gpa, text, &failure) catch {
            std.debug.print("warning: labs/{s}: invalid lab ({s}: {s}); skipped\n", .{ e.name, failure.field, failure.message });
            gpa.free(text);
            continue;
        };
        if (p.lab.symptom.len == 0) {
            var pp = p;
            pp.deinit();
            gpa.free(text);
            continue; // not a learner scenario
        }
        try parsed.append(gpa, p);
        try texts.append(gpa, text);
    }
    if (parsed.items.len == 0) return &.{};
    // Directory order is arbitrary; a lesson's lab menu is easier to use (and stable) sorted by title.
    {
        const Pair = struct { p: winlab.lab.Parsed, t: []u8 };
        const pairs = try arena.alloc(Pair, parsed.items.len);
        for (parsed.items, texts.items, pairs) |p, t, *slot| slot.* = .{ .p = p, .t = t };
        std.mem.sort(Pair, pairs, {}, struct {
            fn less(_: void, a: Pair, b: Pair) bool {
                return std.mem.lessThan(u8, a.p.lab.title, b.p.lab.title);
            }
        }.less);
        for (pairs, 0..) |pair, i| {
            parsed.items[i] = pair.p;
            texts.items[i] = pair.t;
        }
    }
    // The window keeps these for its whole life, and the parsed labs below may be freed when no VM is
    // available, so every string is copied into the arena (borrowing them was a use-after-free).
    for (parsed.items) |p| {
        const hints = try arena.alloc([]const u8, p.lab.hints.len);
        for (p.lab.hints, hints) |src, *dst| dst.* = try arena.dupe(u8, src);
        try entries.append(arena, .{
            .lesson = try arena.dupe(u8, p.lab.lesson),
            .id = try arena.dupe(u8, p.lab.id),
            .title = try arena.dupe(u8, p.lab.title),
            .symptom = try arena.dupe(u8, p.lab.symptom),
            .hints = hints,
            .task = p.lab.kind == .script,
            .script_path = try arena.dupe(u8, p.lab.script_path),
        });
    }

    const cleanup = struct {
        fn all(g: std.mem.Allocator, ps: *std.ArrayList(winlab.lab.Parsed), ts: *std.ArrayList([]u8)) void {
            for (ps.items, ts.items) |*p, t| {
                p.deinit();
                g.free(t);
            }
            ps.deinit(g);
            ts.deinit(g);
        }
    }.all;

    var reg = winlab.vm_registry.load(gpa, io, try openAppData(init)) catch {
        note.* = "The VM list could not be read. Labs need a registered training VM.";
        cleanup(gpa, &parsed, &texts);
        return try arena.dupe(gui.Lab, entries.items);
    };
    // Every usable training VM (or only the one named in settings). guest.toml says which shell, so
    // which OS, and which distribution each runs; a lab picks the first VM that matches it.
    var cands: std.ArrayList(LabVm) = .empty;
    for (reg.vms) |v| {
        if (!v.training_target or !std.mem.eql(u8, v.provider, "qemu")) continue;
        if (cfg.settings.lab_vm.len > 0 and !std.mem.eql(u8, v.id, cfg.settings.lab_vm)) continue;
        const d = std.fs.path.dirname(v.disk) orelse ".";
        const access = winlab.vm_guest.load(arena, io, d) catch continue;
        try cands.append(arena, .{ .vm = v, .linux = access.shell == .bash, .distro = access.distro, .login = readLogin(arena, io, d) });
    }
    if (cands.items.len == 0) {
        note.* = "No lab VM is set up. Build one with: winlab vm install windows-server-2022-eval <vm-id> (or ubuntu-2404-cloud for Linux labs), then take a snapshot named winlab-clean and build the labs (winlab lab build).";
        reg.deinit();
        cleanup(gpa, &parsed, &texts);
        return try arena.dupe(gui.Lab, entries.items);
    }
    var tools = (winlab.vm_qemu.discover(gpa, io, init.environ_map.get("PATH") orelse "", cfg.settings.qemu_path) catch null) orelse {
        note.* = winlab.vm_qemu.install_guidance;
        reg.deinit();
        cleanup(gpa, &parsed, &texts);
        return try arena.dupe(gui.Lab, entries.items);
    };
    errdefer tools.deinit();
    const ssh_exe = try winlab.platform.tool(arena, init.io, init.environ_map, .ssh);
    backend.* = .{
        .gpa = gpa,
        .io = io,
        .tools = tools,
        .q = undefined,
        .reg = reg,
        .cands = cands.items,
        .parsed = try parsed.toOwnedSlice(gpa),
        .texts = try texts.toOwnedSlice(gpa),
        .store = store,
    };
    backend.q = .{ .gpa = gpa, .io = io, .tools = &backend.tools, .ssh_exe = ssh_exe };
    backend_ready.* = true;
    return try arena.dupe(gui.Lab, entries.items);
}


/// Backs the setup window: runs the same discovery as `winlab status` and records that the window was seen.
const SetupBackend = struct {
    init: std.process.Init,
    settings: winlab.settings.Settings,
    content_dir: []const u8,
    arena: std.heap.ArenaAllocator,

    fn check(ctx: *anyopaque, out: *[gui.setup_max_items]gui.SetupItem) usize {
        const self: *SetupBackend = @ptrCast(@alignCast(ctx));
        _ = self.arena.reset(.retain_capacity);
        const a = self.arena.allocator();
        const io = self.init.io;
        const path = self.init.environ_map.get("PATH") orelse "";
        var n: usize = 0;
        out[n] = .{ .name = "Lessons and quizzes", .ok = true, .optional = false, .detail = std.fmt.allocPrint(a, "Course folder: {s}", .{self.content_dir}) catch "Course folder found." };
        n += 1;
        for (winlab.shell_discovery.here) |sh| {
            if (n < out.len) {
                const found = winlab.shell_discovery.findOnPath(io, path, sh.executable());
                out[n] = .{
                    .name = sh.displayName(),
                    .ok = found,
                    .optional = sh.isOptional(),
                    .detail = if (found) "Offered in the Practice menu for typing commands from the lessons." else "Not installed. Lessons that use it still read fine; install it to practise in the app.",
                };
                n += 1;
            }
        }
        const ssh = winlab.platform.tool(a, io, self.init.environ_map, .ssh) catch "";
        const ssh_ok = ssh.len > 0 and blk: {
            const st = std.Io.Dir.cwd().statFile(io, ssh, .{}) catch break :blk false;
            break :blk st.kind == .file;
        };
        out[n] = .{ .name = "OpenSSH client", .ok = ssh_ok, .optional = true, .detail = if (ssh_ok) "Labs use it to control the virtual machine." else if (winlab.platform.is_windows) "Labs use it to control the virtual machine. It is an optional Windows feature: Settings > System > Optional features > Add a feature > OpenSSH Client." else "Labs use it to control the virtual machine. Install your distribution's OpenSSH client package (openssh-client, openssh-clients or openssh)." };
        n += 1;
        // WINLAB_SETUP_DEMO_NOQEMU=1 pretends QEMU is missing, to see the install choices without uninstalling it.
        const pretend_missing = self.init.environ_map.get("WINLAB_SETUP_DEMO_NOQEMU") != null;
        if (if (pretend_missing) null else winlab.vm_qemu.discover(self.init.gpa, io, path, self.settings.qemu_path) catch null) |found| {
            var tools = found;
            defer tools.deinit();
            out[n] = .{ .name = "QEMU", .ok = true, .optional = true, .detail = std.fmt.allocPrint(a, "{s}. Location: {s}. Hardware acceleration ({s}): {s}.", .{ tools.version, tools.qemu_system, if (winlab.platform.is_windows) "WHPX" else "KVM", if (tools.hw_accel) "available" else if (winlab.platform.is_windows) "not available, so labs run in slow software emulation; turn on Windows Hypervisor Platform in Windows Features" else "not available, so labs run in slow software emulation; /dev/kvm must exist and be readable and writable by you (usually: add yourself to the kvm group, then log in again)" }) catch "Found." };
        } else {
            out[n] = .{ .name = "QEMU", .ok = false, .optional = true, .detail = "Needed only for the hands-on labs. Not found in your settings or PATH (or Program Files and MSYS2 on Windows)." };
        }
        n += 1;
        return n;
    }

    fn finish(ctx: *anyopaque) void {
        const self: *SetupBackend = @ptrCast(@alignCast(ctx));
        if (self.settings.setup_done) return;
        self.settings.setup_done = true;
        const appdata = winlab.platform.configBase(self.init.arena.allocator(), self.init.environ_map) orelse return;
        std.Io.Dir.cwd().createDirPath(self.init.io, appdata) catch {};
        var base = std.Io.Dir.cwd().openDir(self.init.io, appdata, .{}) catch return;
        defer base.close(self.init.io);
        winlab.settings_file.save(self.init.io, base, self.settings) catch |e| std.debug.print("warning: could not save settings: {t}\n", .{e});
    }
};
fn browse(init: std.process.Init, dir_arg: ?[]const u8) !void {
    const gpa = init.gpa;
    const io = init.io;
    var cfg = loadSettings(init);
    const dark = gui.isDark(cfg.settings.theme);
    defer cfg.deinit();
    const dir = dir_arg orelse try defaultCourseDir(init, cfg.settings.content_path);
    var course = try openCourse(gpa, io, dir);
    defer course.root.close(io);
    defer course.catalog.deinit();
    const cat = &course.catalog;

    for (cat.problems) |p| std.debug.print("warning: {s}: {s}\n", .{ p.where, p.message });
    if (cat.entries.len == 0) {
        std.debug.print("{s}: no lessons found\n", .{dir});
        std.process.exit(1);
    }
    // Certification names for the lesson headers (optional).
    var certs_cat = loadCertsNear(gpa, io, dir);
    defer if (certs_cat) |*c| c.deinit();

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const pages = try arena.alloc(gui.Page, cat.entries.len);
    for (cat.entries, pages) |entry, *page| {
        const content_path = try cat.contentPath(arena, entry);
        // A missing content file was already reported as a problem; show a stub instead of failing.
        const body = course.root.readFileAlloc(io, content_path, arena, .limited(max_lesson_bytes)) catch |err|
            try std.fmt.allocPrint(arena, "*Lesson content could not be read: {t}*\n", .{err});
        const markdown = try winlab.lesson_view.buildWith(arena, cat, if (certs_cat) |*c| c else null, entry, body);
        page.* = try renderPage(arena, entry.lesson.title, markdown);
        page.drawings = try loadDrawings(arena, io, course.root, entry.dir, page.root, null);
        page.id = try arena.dupe(u8, entry.lesson.id);
        page.summary = entry.lesson.summary;
        page.body = body;
        page.level = entry.lesson.level;
        page.minutes = entry.lesson.estimated_minutes;
        page.prerequisites = entry.lesson.prerequisites;
    }

    // Learning paths (paths/*.toml), with lesson ids resolved to page indices. A path that names a lesson
    // the course does not have still loads (`winlab check` reports it); the missing lesson is left out.
    var path_set = try openPaths(gpa, io, rootOfCourse(dir));
    defer path_set.deinit();
    for (path_set.problems) |p| std.debug.print("warning: paths/{s}\n", .{p});
    const path_views = try pathViews(arena, &path_set, cat);

    var store = ProgressStore.open(init);
    defer store.close();

    // Offer each real shell that is installed. Nothing is started until the learner picks one.
    var shells: std.ArrayList(gui.ShellChoice) = .empty;
    const path = init.environ_map.get("PATH") orelse "";
    for (winlab.shell_discovery.here) |sh| {
        if (winlab.shell_discovery.findOnPath(io, path, sh.executable())) {
            try shells.append(arena, .{ .name = sh.displayName(), .command = sh.commandLine() });
        }
    }

    // Labs (scenarios): the Lab button appears when labs/*.toml has learner scenarios.
    var lab_backend: LabBackend = undefined;
    var lab_backend_ready = false;
    defer if (lab_backend_ready) lab_backend.deinit();
    var lab_note: []const u8 = "";
    const lab_entries = try openLabs(init, &cfg, rootOfCourse(dir), &store, &lab_backend, &lab_backend_ready, &lab_note);

    var setup_backend: SetupBackend = .{ .init = init, .settings = cfg.settings, .content_dir = dir, .arena = std.heap.ArenaAllocator.init(gpa) };
    defer setup_backend.arena.deinit();
    const settings_path = if (winlab.platform.configBase(init.arena.allocator(), init.environ_map)) |ad| std.fs.path.join(arena, &.{ ad, winlab.settings_file.sub_dir, winlab.settings_file.file_name }) catch "" else "";

    try gui.run(gpa, "WinLab - Course", pages, .{
        .io = io,
        .fonts_dir = fontsDir(init),
        .quizzes = openQuizzes(arena, io, rootOfCourse(dir)),
        .paths = path_views,
        .shells = shells.items,
        .start_dir = winlab.platform.homeDir(init.environ_map),
        .text_scale = cfg.settings.text_scale,
        .dark = dark,
        .tracking = store.tracking(),
        .labs = lab_entries,
        .lab_engine = if (lab_backend_ready) .{ .ctx = &lab_backend, .run = LabBackend.run, .fixed = LabBackend.fixed, .login = LabBackend.login } else null,
        .lab_note = lab_note,
        .badges = cfg.settings.badges,
        .setup = .{ .ctx = &setup_backend, .check = SetupBackend.check, .finish = SetupBackend.finish, .show_first = !cfg.settings.setup_done, .settings_path = settings_path },
    });
}

/// progress.toml under %APPDATA%. If the profile is unavailable or the file is
/// corrupt, tracking is switched off for this run (with a warning) instead of
/// risking an overwrite of the user's data.
const ProgressStore = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    base: ?std.Io.Dir = null,
    progress: winlab.progress.Progress,
    enabled: bool = false,

    fn open(init: std.process.Init) ProgressStore {
        var s: ProgressStore = .{ .gpa = init.gpa, .io = init.io, .progress = winlab.progress.Progress.init(init.gpa) };
        const appdata = winlab.platform.configBase(init.arena.allocator(), init.environ_map) orelse {
            std.debug.print("warning: the settings folder is unknown (APPDATA or HOME is not set); progress tracking is off\n", .{});
            return s;
        };
        std.Io.Dir.cwd().createDirPath(init.io, appdata) catch {};
        var base = std.Io.Dir.cwd().openDir(init.io, appdata, .{}) catch |err| {
            std.debug.print("warning: cannot open {s}: {t}; progress tracking is off\n", .{ appdata, err });
            return s;
        };
        const loaded = winlab.progress_file.load(init.gpa, init.io, base) catch |err| {
            std.debug.print("warning: {s}{c}{s}{c}{s}: {t}; progress tracking is off so the file is not overwritten\n", .{ appdata, winlab.platform.dir_sep, winlab.progress_file.sub_dir, winlab.platform.dir_sep, winlab.progress_file.file_name, err });
            base.close(init.io);
            return s;
        };
        s.progress.deinit();
        s.progress = loaded;
        s.base = base;
        s.enabled = true;
        if (s.progress.dropped != 0) std.debug.print("warning: {d} unusable progress entr(ies) were ignored and will be removed on the next save\n", .{s.progress.dropped});
        return s;
    }

    fn close(self: *ProgressStore) void {
        if (self.base) |*b| b.close(self.io);
        self.progress.deinit();
    }

    fn tracking(self: *ProgressStore) ?gui.Tracking {
        if (!self.enabled) return null;
        return .{ .progress = &self.progress, .save_ctx = self, .save = save };
    }

    fn save(ctx: ?*anyopaque, p: *const winlab.progress.Progress) bool {
        const self: *ProgressStore = @ptrCast(@alignCast(ctx.?));
        winlab.progress_file.save(self.gpa, self.io, self.base.?, p) catch |err| {
            std.debug.print("error: saving progress failed: {t}\n", .{err});
            return false;
        };
        return true;
    }
};

/// `winlab terminal <cmd|powershell|pwsh>`: one real shell in its own window.
fn terminal(init: std.process.Init, which: []const u8) !void {
    const sh: winlab.shell_discovery.Shell = if (std.mem.eql(u8, which, "cmd"))
        .cmd
    else if (std.mem.eql(u8, which, "powershell"))
        .windows_powershell
    else if (std.mem.eql(u8, which, "bash"))
        .bash
    else if (std.mem.eql(u8, which, "pwsh"))
        .powershell_7
    else {
        std.debug.print("{s}", .{usage});
        std.process.exit(2);
    };
    var cfg = loadSettings(init);
    defer cfg.deinit();
    try terminal_host.runStandalone(init.gpa, .{
        .command = sh.commandLine(),
        .shell_name = sh.displayName(),
        .start_dir = winlab.platform.homeDir(init.environ_map),
        .text_scale = cfg.settings.text_scale,
        .dark = gui.isDark(cfg.settings.theme),
    });
}

/// Loads images/catalog.toml from the content root (settings content-path, else the working directory).
fn loadImageCatalog(init: std.process.Init, cfg: *const winlab.settings.Loaded) !winlab.vm_images.Catalog {
    const root = contentRoot(init, cfg.settings.content_path);
    const arena = init.arena.allocator();
    const path = try std.fs.path.join(arena, &.{ root, "images", "catalog.toml" });
    const main_text = std.Io.Dir.cwd().readFileAlloc(init.io, path, arena, .limited(1024 * 1024)) catch |err| {
        std.debug.print("{s}: cannot read the image catalog: {t}\n", .{ path, err });
        std.process.exit(1);
    };
    // Images the learner added with `winlab image add` live in local.toml next to the downloads
    // (only [[image]] blocks); they are appended to the shipped catalog before parsing.
    const local_path = try std.fs.path.join(arena, &.{ try imagesDir(init), "local.toml" });
    const local_text = std.Io.Dir.cwd().readFileAlloc(init.io, local_path, arena, .limited(1024 * 1024)) catch "";
    const text = try std.fmt.allocPrint(arena, "{s}\n{s}\n", .{ main_text, local_text });
    return winlab.vm_images.parse(init.gpa, text) catch |err| {
        std.debug.print("{s} (+ local.toml): invalid image catalog: {t}\n", .{ path, err });
        std.process.exit(1);
    };
}

/// %LOCALAPPDATA%\WinLab\images
fn imagesDir(init: std.process.Init) ![]const u8 {
    const base = winlab.platform.dataBase(init.arena.allocator(), init.environ_map) orelse {
        std.debug.print("the data folder is unknown (LOCALAPPDATA or HOME is not set); cannot choose a download folder\n", .{});
        std.process.exit(1);
    };
    return std.fs.path.join(init.arena.allocator(), &.{ base, "WinLab", "images" });
}

fn imageList(init: std.process.Init) !void {
    var cfg = loadSettings(init);
    defer cfg.deinit();
    var cat = try loadImageCatalog(init, &cfg);
    defer cat.deinit();
    const dir = try imagesDir(init);
    for (cat.entries) |e| {
        const local = if (e.path.len > 0) e.path else try std.fs.path.join(init.arena.allocator(), &.{ dir, e.file });
        const present = if (std.Io.Dir.cwd().statFile(init.io, local, .{})) |st| st.kind == .file else |_| false;
        std.debug.print("{s}\n  {s}\n  {d} bytes, {s}\n", .{ e.id, e.name, e.size_bytes, if (present) "downloaded" else "not downloaded" });
    }
    std.debug.print("\nDownload folder: {s}\nUse: winlab image fetch <id>\n", .{dir});
}

/// PowerShell that mounts an ISO read-only (no elevation needed), reads the editions listed in
/// sources\install.wim (or install.esd) from the WIM's embedded XML, and dismounts it again.
const editions_script =
    \\$ErrorActionPreference = 'Stop'
    \\$iso = $args[0]
    \\$img = Mount-DiskImage -ImagePath $iso -StorageType ISO -PassThru
    \\try {
    \\  $drv = ($img | Get-Volume).DriveLetter
    \\  $wim = Get-ChildItem "${drv}:\sources" -Filter 'install.*' | Where-Object { $_.Extension -in '.wim','.esd' } | Select-Object -First 1
    \\  if (-not $wim) { throw 'no install.wim or install.esd found on this image' }
    \\  $fs = [IO.File]::OpenRead($wim.FullName)
    \\  try {
    \\    $br = New-Object IO.BinaryReader $fs
    \\    $fs.Position = 0x48
    \\    $sizeFlags = $br.ReadUInt64(); $off = $br.ReadUInt64(); $null = $br.ReadUInt64()
    \\    $len = $sizeFlags -band 0x00FFFFFFFFFFFFFF
    \\    $fs.Position = $off
    \\    $bytes = $br.ReadBytes([int]$len)
    \\  } finally { $fs.Close() }
    \\  $xml = [xml][Text.Encoding]::Unicode.GetString($bytes).TrimStart([char]0xFEFF)
    \\  foreach ($i in $xml.WIM.IMAGE) { '{0}{2}{1}' -f $i.INDEX, $i.NAME, [char]9 }
    \\} finally { Dismount-DiskImage -ImagePath $iso | Out-Null }
    \\
;

/// `winlab image editions <file.iso>`: lists the Windows editions inside an ISO and their index numbers
/// (the number `image add` needs). Mounts the ISO read-only for a moment and dismounts it.
fn imageEditions(init: std.process.Init, iso_path: []const u8) !void {
    const gpa = init.gpa;
    const io = init.io;
    if (std.mem.indexOfScalar(u8, iso_path, '"') != null or std.mem.indexOfScalar(u8, iso_path, '\'') != null) {
        std.debug.print("quotes in the path are not supported\n", .{});
        std.process.exit(2);
    }
    const abs = std.Io.Dir.cwd().realPathFileAlloc(io, iso_path, init.arena.allocator()) catch |err| {
        std.debug.print("{s}: {t}\n", .{ iso_path, err });
        std.process.exit(1);
    };
    if (!winlab.platform.is_windows) {
        std.debug.print("Listing the editions inside a Windows ISO needs Windows (it mounts the image). On Linux, give `image add` the edition index you already know.\n", .{});
        std.process.exit(1);
    }
    const system_root = init.environ_map.get("SystemRoot") orelse "C:\\Windows";
    const ps = try std.fs.path.join(init.arena.allocator(), &.{ system_root, "System32", "WindowsPowerShell", "v1.0", "powershell.exe" });
    // The script reads the path from $args[0]; it is passed through -Command as a script block with arguments.
    const command = try std.fmt.allocPrint(init.arena.allocator(), "& {{ {s} }} '{s}'", .{ editions_script, abs });
    const r = std.process.run(gpa, io, .{ .argv = &.{ ps, "-NoProfile", "-NonInteractive", "-Command", command } }) catch |err| {
        std.debug.print("could not run PowerShell: {t}\n", .{err});
        std.process.exit(1);
    };
    defer gpa.free(r.stdout);
    defer gpa.free(r.stderr);
    if (r.term != .exited or r.term.exited != 0) {
        std.debug.print("could not read the image:\n{s}\n", .{std.mem.trim(u8, r.stderr, " \r\n")});
        std.process.exit(1);
    }
    std.debug.print("Editions in {s}:\n  index  name\n", .{abs});
    var lines = std.mem.tokenizeAny(u8, r.stdout, "\r\n");
    while (lines.next()) |line| {
        if (std.mem.indexOfScalar(u8, line, '\t')) |tab| std.debug.print("  {s: >5}  {s}\n", .{ line[0..tab], line[tab + 1 ..] });
    }
}

/// `winlab image add <id> <file.iso> <server|client> <index> [name]`: registers an ISO the learner already
/// has (Windows 10/11 Home and Pro have no stable download link). Nothing is copied or modified.
fn imageAdd(init: std.process.Init, args: []const [:0]const u8) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const id = args[3];
    const iso_in = args[4];
    const kind = args[5];
    const index = std.fmt.parseInt(u32, args[6], 10) catch 0;
    if (!winlab.vm_registry.validId(id) or index == 0 or index > 64 or !(std.mem.eql(u8, kind, "server") or std.mem.eql(u8, kind, "client"))) {
        std.debug.print("usage: winlab image add <id> <file.iso> <server|client> <index> [name]   (id: lowercase letters, digits, '-'; see: winlab image editions)\n", .{});
        std.process.exit(2);
    }
    const abs = std.Io.Dir.cwd().realPathFileAlloc(io, iso_in, arena) catch |err| {
        std.debug.print("{s}: {t}\n", .{ iso_in, err });
        std.process.exit(1);
    };
    const name = if (args.len > 7) args[7] else id;
    var cfg = loadSettings(init);
    defer cfg.deinit();
    var existing = try loadImageCatalog(init, &cfg);
    defer existing.deinit();
    if (existing.find(id) != null) {
        std.debug.print("an image with id '{s}' already exists\n", .{id});
        std.process.exit(1);
    }
    const dir = try imagesDir(init);
    try std.Io.Dir.cwd().createDirPath(io, dir);
    var folder = try std.Io.Dir.cwd().openDir(io, dir, .{});
    defer folder.close(io);
    const old = folder.readFileAlloc(io, "local.toml", arena, .limited(1024 * 1024)) catch "";
    var out: std.Io.Writer.Allocating = .init(arena);
    try out.writer.writeAll(old);
    try out.writer.print("\n[[image]]\nid = \"{s}\"\nname = '{s}'\nos = \"{s}\"\npath = '{s}'\nunattend = \"{s}\"\nimage_index = {d}\nnote = \"Supplied by the learner; WinLab does not download or license it.\"\n", .{
        id,
        name,
        if (std.mem.eql(u8, kind, "server")) "windows-server" else "windows-client",
        abs,
        kind,
        index,
    });
    // Validate the result before writing it, so a bad entry never breaks the catalog.
    const check_text = try std.fmt.allocPrint(arena, "schema_version = 1\n{s}\n", .{out.written()});
    var probe = winlab.vm_images.parse(init.gpa, check_text) catch |err| {
        std.debug.print("that entry is not valid ({t}); nothing was saved\n", .{err});
        std.process.exit(1);
    };
    probe.deinit();
    try folder.writeFile(io, .{ .sub_path = "local.toml", .data = out.written() });
    std.debug.print("Added '{s}' ({s}, edition index {d}). Install a VM from it with: winlab vm install {s} <vm-id>\n", .{ id, abs, index, id });
}

fn imageFetch(init: std.process.Init, id: []const u8) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();
    var cfg = loadSettings(init);
    defer cfg.deinit();
    var cat = try loadImageCatalog(init, &cfg);
    defer cat.deinit();
    const e = cat.find(id) orelse {
        std.debug.print("unknown image id '{s}' (see: winlab image list)\n", .{id});
        std.process.exit(1);
    };
    const dir = try imagesDir(init);
    const curl = try winlab.platform.tool(arena, init.io, init.environ_map, .curl);
    if (std.Io.Dir.cwd().statFile(io, curl, .{})) |_| {} else |_| {
        std.debug.print("curl.exe was not found at {s}\n", .{curl});
        std.process.exit(1);
    }
    try std.Io.Dir.cwd().createDirPath(io, dir);

    const free = winlab.vm_images.freeBytes(gpa, dir);
    std.debug.print(
        \\About to download:
        \\  {s}
        \\  from:    {s}
        \\  to:      {s}{c}{s}
        \\  size:    {d} bytes
        \\  free:    {s}
        \\  note:    {s}
        \\
    , .{ e.name, e.url, dir, winlab.platform.dir_sep, e.file, e.size_bytes, if (free) |f| try std.fmt.allocPrint(arena, "{d} bytes", .{f}) else "unknown", e.note });
    if (free) |f| if (e.size_bytes > 0 and f < e.size_bytes + 1024 * 1024 * 1024) {
        std.debug.print("Not enough free space (need the image plus 1 GiB of headroom).\n", .{});
        std.process.exit(1);
    };
    std.debug.print("Download it now? Type yes to continue: ", .{});
    var rbuf: [64]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &rbuf);
    const answer = stdin_reader.interface.takeDelimiterExclusive('\n') catch "";
    if (!std.mem.eql(u8, std.mem.trim(u8, answer, " \r\t"), "yes")) {
        std.debug.print("Cancelled; nothing was downloaded.\n", .{});
        return;
    }

    const part_name = try std.fmt.allocPrint(arena, "{s}.part", .{e.file});
    const part_path = try std.fs.path.join(arena, &.{ dir, part_name });
    const argv = try winlab.vm_images.curlArgs(arena, curl, e.url, part_path);
    var child = try std.process.spawn(io, .{ .argv = argv }); // curl's own progress meter shows on this console
    const term = try child.wait(io);
    switch (term) {
        .exited => |c| if (c != 0) {
            std.debug.print("\ncurl failed (exit code {d}). The partial file is kept; run the command again to resume.\n", .{c});
            std.process.exit(1);
        },
        else => {
            std.debug.print("\ncurl did not finish normally.\n", .{});
            std.process.exit(1);
        },
    }

    var folder = try std.Io.Dir.cwd().openDir(io, dir, .{});
    defer folder.close(io);
    const st = try folder.statFile(io, part_name, .{});
    if (e.size_bytes != 0 and st.size != e.size_bytes) {
        std.debug.print("Size mismatch: expected {d} bytes, got {d}. The file was not accepted.\n", .{ e.size_bytes, st.size });
        std.process.exit(1);
    }
    std.debug.print("Computing SHA-256...\n", .{});
    const hex = try winlab.vm_images.hashFile(io, folder, part_name);
    if (e.sha256.len != 0 and !std.mem.eql(u8, e.sha256, &hex)) {
        std.debug.print("SHA-256 mismatch.\n  expected {s}\n  got      {s}\nThe file was not accepted.\n", .{ e.sha256, hex });
        std.process.exit(1);
    }
    if (e.sums_url.len > 0) {
        // The publisher's own SHA256SUMS (fetched over HTTPS) decides: a mismatch means a corrupt or tampered download.
        const sums_argv = [_][]const u8{ curl, "--disable", "--fail", "--silent", "--location", "--proto", "=https", "--proto-redir", "=https", "--max-time", "60", e.sums_url };
        const sums = std.process.run(gpa, io, .{ .argv = &sums_argv, .stdout_limit = .limited(1024 * 1024) }) catch |err| {
            std.debug.print("could not fetch the checksum list: {t}. The file was not accepted.\n", .{err});
            std.process.exit(1);
        };
        defer gpa.free(sums.stdout);
        defer gpa.free(sums.stderr);
        const published = winlab.vm_images.findSum(sums.stdout, e.file) orelse {
            std.debug.print("{s} is not listed in {s}. The file was not accepted.\n", .{ e.file, e.sums_url });
            std.process.exit(1);
        };
        if (!std.mem.eql(u8, &published, &hex)) {
            std.debug.print("SHA-256 does not match the publisher's list.\n  published {s}\n  got       {s}\nThe file was not accepted.\n", .{ published, hex });
            std.process.exit(1);
        }
        std.debug.print("SHA-256 matches the publisher's checksum list.\n", .{});
    }
    try std.Io.Dir.rename(folder, part_name, folder, e.file, io);
    const sidecar = try std.fmt.allocPrint(arena, "{s}.sha256", .{e.file});
    const line = try std.fmt.allocPrint(arena, "{s}  {s}\n", .{ hex, e.file });
    try folder.writeFile(io, .{ .sub_path = sidecar, .data = line });
    std.debug.print("Done.\n  file:   {s}{c}{s}\n  sha256: {s}{s}\n", .{ dir, winlab.platform.dir_sep, e.file, hex, if (e.sha256.len == 0) "  (recorded; compare it with a trusted source if you can)" else "  (matches the catalog)" });
}

/// `winlab vm install <cloud-image-id> <vm-id>`: a Linux VM from an official cloud image. There is no installer:
/// the image is copied to a new qcow2 disk and configured on first boot by a small cloud-init seed CD
/// (lab user, per-VM SSH key, console password). Then, like Windows installs, QEMU is supervised until SSH answers.
fn vmInstallCloud(init: std.process.Init, cfg: *const winlab.settings.Loaded, entry: winlab.vm_images.Entry, vm_id: []const u8) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    const base = try std.fs.path.join(arena, &.{ try imagesDir(init), entry.file });
    if (std.Io.Dir.cwd().statFile(io, base, .{})) |_| {} else |_| {
        std.debug.print("{s} is not downloaded; run: winlab image fetch {s}\n", .{ entry.file, entry.id });
        std.process.exit(1);
    }
    var tools = (try winlab.vm_qemu.discover(gpa, io, init.environ_map.get("PATH") orelse "", cfg.settings.qemu_path)) orelse {
        std.debug.print("{s}\n", .{winlab.vm_qemu.install_guidance});
        std.process.exit(1);
    };
    defer tools.deinit();
    const local = winlab.platform.dataBase(init.arena.allocator(), init.environ_map) orelse {
        std.debug.print("the data folder is unknown (LOCALAPPDATA or HOME is not set)\n", .{});
        std.process.exit(1);
    };
    const vm_dir = try std.fs.path.join(arena, &.{ local, "WinLab", "vms", vm_id });
    if (std.Io.Dir.cwd().statFile(io, vm_dir, .{})) |_| {
        std.debug.print("{s} already exists; choose another vm-id or remove it with: winlab vm remove {s}\n", .{ vm_dir, vm_id });
        std.process.exit(1);
    } else |_| {}
    try std.Io.Dir.cwd().createDirPath(io, vm_dir);
    var vm_folder = try std.Io.Dir.cwd().openDir(io, vm_dir, .{});
    defer vm_folder.close(io);

    // Console password (for the VM window); SSH uses the key only.
    const alphabet = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    var raw: [16]u8 = undefined;
    io.random(&raw);
    var password: [16]u8 = undefined;
    for (raw, &password) |r, *p| p.* = alphabet[r % alphabet.len];

    // Per-VM SSH key.
    const keygen = try winlab.platform.tool(arena, init.io, init.environ_map, .ssh_keygen);
    const key_path = try std.fs.path.join(arena, &.{ vm_dir, winlab.vm_guest.key_file });
    const comment = try std.fmt.allocPrint(arena, "winlab-{s}", .{vm_id});
    const keygen_run = std.process.run(gpa, io, .{ .argv = &.{ keygen, "-q", "-t", "ed25519", "-N", "", "-C", comment, "-f", key_path } }) catch |err| {
        std.debug.print("cannot run {s}: {t} (the Windows OpenSSH client is required for lab control)\n", .{ keygen, err });
        std.process.exit(1);
    };
    defer gpa.free(keygen_run.stdout);
    defer gpa.free(keygen_run.stderr);
    if (keygen_run.term != .exited or keygen_run.term.exited != 0) {
        std.debug.print("ssh-keygen failed:\n{s}\n", .{keygen_run.stderr});
        std.process.exit(1);
    }
    const pub_text = std.mem.trim(u8, try vm_folder.readFileAlloc(io, "id_ed25519.pub", arena, .limited(4096)), " \r\n");

    // The cloud-init seed: a CD labelled CIDATA with user-data and meta-data.
    const opts: winlab.vm_cloud_init.Options = .{ .hostname = vm_id, .password = &password, .ssh_public_key = pub_text, .instance_id = vm_id };
    var user_data: std.Io.Writer.Allocating = .init(gpa);
    defer user_data.deinit();
    var meta_data: std.Io.Writer.Allocating = .init(gpa);
    defer meta_data.deinit();
    try winlab.vm_cloud_init.writeUserData(opts, &user_data.writer);
    try winlab.vm_cloud_init.writeMetaData(opts, &meta_data.writer);
    const seed = try winlab.vm_iso9660.build(gpa, "CIDATA", &.{
        .{ .name = "user-data", .data = user_data.written() },
        .{ .name = "meta-data", .data = meta_data.written() },
    });
    defer gpa.free(seed);
    try vm_folder.writeFile(io, .{ .sub_path = "seed.iso", .data = seed });
    const seed_path = try std.fs.path.join(arena, &.{ vm_dir, "seed.iso" });

    // The disk: a full copy of the image (so the VM does not depend on the download), grown to 20 GB.
    const disk = try std.fs.path.join(arena, &.{ vm_dir, "disk.qcow2" });
    const convert = try std.process.run(gpa, io, .{ .argv = &.{ tools.qemu_img, "convert", "-O", "qcow2", base, disk } });
    defer gpa.free(convert.stdout);
    defer gpa.free(convert.stderr);
    if (convert.term != .exited or convert.term.exited != 0) {
        std.debug.print("qemu-img could not copy the image:\n{s}\n", .{convert.stderr});
        std.process.exit(1);
    }
    const resize = try std.process.run(gpa, io, .{ .argv = &.{ tools.qemu_img, "resize", disk, "20G" } });
    defer gpa.free(resize.stdout);
    defer gpa.free(resize.stderr);
    if (resize.term != .exited or resize.term.exited != 0) {
        std.debug.print("qemu-img could not resize the disk:\n{s}\n", .{resize.stderr});
        std.process.exit(1);
    }

    const ssh_port = try winlab.vm_qemu.pickLoopbackPort(io);
    // guest.toml: how WinLab reaches the guest. `cpu` and `distro` come from the image catalog.
    const cpu_line = if (entry.cpu.len > 0) try std.fmt.allocPrint(arena, "cpu = \"{s}\"\n", .{entry.cpu}) else "";
    const distro_line = if (entry.distro.len > 0) try std.fmt.allocPrint(arena, "distro = \"{s}\"\n", .{entry.distro}) else "";
    const guest_toml = try std.fmt.allocPrint(arena, "ssh_port = {d}\nssh_user = \"labadmin\"\nshell = \"bash\"\n{s}{s}", .{ ssh_port, cpu_line, distro_line });
    try vm_folder.writeFile(io, .{ .sub_path = winlab.vm_guest.guest_file, .data = guest_toml });
    const creds = try std.fmt.allocPrint(arena, "Throwaway lab VM '{s}' (built from {s}).\nUser: labadmin\nConsole password: {s}\nSSH uses a key (id_ed25519 in this folder); password logins over SSH are off.\nThis file holds a clear-text password for a disposable VM on this PC only.\n", .{ vm_id, entry.name, &password });
    try vm_folder.writeFile(io, .{ .sub_path = "credentials.txt", .data = creds });

    var reg = try winlab.vm_registry.load(gpa, io, try openAppData(init));
    defer reg.deinit();
    var vms: std.ArrayList(winlab.vm_registry.Vm) = .empty;
    try vms.appendSlice(arena, reg.vms);
    const vm: winlab.vm_registry.Vm = .{ .id = vm_id, .name = vm_id, .provider = "qemu", .disk = disk, .memory_mb = 2048, .cpus = 2, .training_target = true };
    try vms.append(arena, vm);
    try winlab.vm_registry.save(gpa, io, try openAppData(init), vms.items);

    std.debug.print(
        \\Linux VM '{s}' created and registered as a training target.
        \\  folder:      {s}
        \\  credentials: {s}{c}credentials.txt  (user labadmin, console password {s})
        \\  First boot configures the VM (about a minute). Keep this command running: it finishes
        \\  when the guest answers over SSH.
        \\
    , .{ vm_id, vm_dir, vm_dir, winlab.platform.dir_sep, &password });
    try superviseUntilReady(init, &tools, vm, null, seed_path, 30);
}

/// A per-VM lab password and SSH key pair, as for the cloud-image VMs. The key goes in the VM folder.
const VmCredentials = struct { password: [16]u8, pub_text: []const u8 };

fn makeVmCredentials(init: std.process.Init, vm_folder: std.Io.Dir, vm_dir: []const u8, vm_id: []const u8) !VmCredentials {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();
    const alphabet = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    var raw: [16]u8 = undefined;
    io.random(&raw);
    var password: [16]u8 = undefined;
    for (raw, &password) |r, *p| p.* = alphabet[r % alphabet.len];

    const keygen = try winlab.platform.tool(arena, init.io, init.environ_map, .ssh_keygen);
    const key_path = try std.fs.path.join(arena, &.{ vm_dir, winlab.vm_guest.key_file });
    const comment = try std.fmt.allocPrint(arena, "winlab-{s}", .{vm_id});
    const run = std.process.run(gpa, io, .{ .argv = &.{ keygen, "-q", "-t", "ed25519", "-N", "", "-C", comment, "-f", key_path } }) catch |err| {
        std.debug.print("cannot run {s}: {t} (the Windows OpenSSH client is required for lab control)\n", .{ keygen, err });
        std.process.exit(1);
    };
    defer gpa.free(run.stdout);
    defer gpa.free(run.stderr);
    if (run.term != .exited or run.term.exited != 0) {
        std.debug.print("ssh-keygen failed:\n{s}\n", .{run.stderr});
        std.process.exit(1);
    }
    const pub_text = std.mem.trim(u8, try vm_folder.readFileAlloc(io, "id_ed25519.pub", arena, .limited(4096)), " \r\n");
    return .{ .password = password, .pub_text = pub_text };
}

/// Ends QEMU if the serial conversation takes longer than `limit_s` seconds. Killing the process closes the
/// serial socket, which unblocks the reader (reads have no timeout of their own).
const InstallWatchdog = struct {
    child: *std.process.Child,
    io: std.Io,
    limit_s: u32,
    cancel: std.atomic.Value(bool) = .init(false),
    fired: std.atomic.Value(bool) = .init(false),

    fn run(self: *InstallWatchdog) void {
        var s: u32 = 0;
        while (s < self.limit_s and !self.cancel.load(.acquire)) : (s += 1) std.Io.sleep(self.io, .fromSeconds(1), .real) catch {};
        if (self.cancel.load(.acquire)) return;
        self.fired.store(true, .release);
        self.child.kill(self.io);
    }
};

/// `winlab vm install <image-id> <vm-id>` for media with an `installer` recipe (Chimera Linux, which publishes no
/// cloud image). QEMU boots the live ISO's own kernel with a serial console; WinLab logs in over the serial socket,
/// has the live system run the install script from a seed CD (the official procedure: partition, chimera-bootstrap,
/// chimera-chroot, GRUB), powers it off, and then boots the new disk like any other Linux lab VM until SSH answers.
fn vmInstallLive(init: std.process.Init, cfg: *const winlab.settings.Loaded, entry: winlab.vm_images.Entry, vm_id: []const u8) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();
    if (!std.mem.eql(u8, entry.installer, "chimera")) {
        std.debug.print("unknown installer recipe '{s}' for {s}\n", .{ entry.installer, entry.id });
        std.process.exit(1);
    }
    const iso = try std.fs.path.join(arena, &.{ try imagesDir(init), entry.file });
    if (std.Io.Dir.cwd().statFile(io, iso, .{})) |_| {} else |_| {
        std.debug.print("{s} is not downloaded; run: winlab image fetch {s}\n", .{ entry.file, entry.id });
        std.process.exit(1);
    }
    var tools = (try winlab.vm_qemu.discover(gpa, io, init.environ_map.get("PATH") orelse "", cfg.settings.qemu_path)) orelse {
        std.debug.print("{s}\n", .{winlab.vm_qemu.install_guidance});
        std.process.exit(1);
    };
    defer tools.deinit();
    const local = winlab.platform.dataBase(init.arena.allocator(), init.environ_map) orelse {
        std.debug.print("the data folder is unknown (LOCALAPPDATA or HOME is not set)\n", .{});
        std.process.exit(1);
    };
    const vm_dir = try std.fs.path.join(arena, &.{ local, "WinLab", "vms", vm_id });
    if (std.Io.Dir.cwd().statFile(io, vm_dir, .{})) |_| {
        std.debug.print("{s} already exists; choose another vm-id or remove it with: winlab vm remove {s}\n", .{ vm_dir, vm_id });
        std.process.exit(1);
    } else |_| {}
    const live_dir = try std.fs.path.join(arena, &.{ vm_dir, "live" });
    try std.Io.Dir.cwd().createDirPath(io, live_dir);
    var vm_folder = try std.Io.Dir.cwd().openDir(io, vm_dir, .{});
    defer vm_folder.close(io);

    const creds = try makeVmCredentials(init, vm_folder, vm_dir, vm_id);

    // The ISO's own kernel and initrd, so the live system can be started with a serial console. Windows 10 and
    // later ship tar.exe (bsdtar), which reads ISO 9660 images.
    std.debug.print("Extracting the live kernel from {s} ...\n", .{entry.file});
    const tar = try winlab.platform.tool(arena, init.io, init.environ_map, .tar);
    const extract = std.process.run(gpa, io, .{ .argv = &.{ tar, "-xf", iso, "-C", live_dir, winlab.vm_chimera.iso_kernel, winlab.vm_chimera.iso_initrd } }) catch |err| {
        std.debug.print("cannot run {s}: {t}\n", .{ tar, err });
        std.process.exit(1);
    };
    defer gpa.free(extract.stdout);
    defer gpa.free(extract.stderr);
    if (extract.term != .exited or extract.term.exited != 0) {
        std.debug.print("could not read the kernel out of the ISO:\n{s}\n", .{extract.stderr});
        std.process.exit(1);
    }
    const kernel = try std.fs.path.join(arena, &.{ live_dir, "live", "vmlinuz" });
    const initrd = try std.fs.path.join(arena, &.{ live_dir, "live", "initrd" });

    // The seed CD: install.sh, chroot.sh and wl.conf (host name, lab user, password, public key).
    const seed = winlab.vm_chimera.buildSeed(gpa, .{ .hostname = vm_id, .password = &creds.password, .ssh_public_key = creds.pub_text }) catch |err| {
        std.debug.print("could not build the seed CD: {t}\n", .{err});
        std.process.exit(1);
    };
    defer gpa.free(seed);
    try vm_folder.writeFile(io, .{ .sub_path = "seed.iso", .data = seed });
    const seed_path = try std.fs.path.join(arena, &.{ vm_dir, "seed.iso" });

    const disk = try std.fs.path.join(arena, &.{ vm_dir, "disk.qcow2" });
    const created = try std.process.run(gpa, io, .{ .argv = &.{ tools.qemu_img, "create", "-q", "-f", "qcow2", disk, "12G" } });
    defer gpa.free(created.stdout);
    defer gpa.free(created.stderr);
    if (created.term != .exited or created.term.exited != 0) {
        std.debug.print("qemu-img could not create the disk:\n{s}\n", .{created.stderr});
        std.process.exit(1);
    }

    const ssh_port = try winlab.vm_qemu.pickLoopbackPort(io);
    const cpu_line = if (entry.cpu.len > 0) try std.fmt.allocPrint(arena, "cpu = \"{s}\"\n", .{entry.cpu}) else "";
    const distro_line = if (entry.distro.len > 0) try std.fmt.allocPrint(arena, "distro = \"{s}\"\n", .{entry.distro}) else "";
    const guest_toml = try std.fmt.allocPrint(arena, "ssh_port = {d}\nssh_user = \"labadmin\"\nshell = \"bash\"\n{s}{s}", .{ ssh_port, cpu_line, distro_line });
    try vm_folder.writeFile(io, .{ .sub_path = winlab.vm_guest.guest_file, .data = guest_toml });
    const cred_text = try std.fmt.allocPrint(arena, "Throwaway lab VM '{s}' (built from {s}).\nUser: labadmin (administrator through doas; Chimera has no sudo). root has the same password.\nConsole password: {s}\nSSH uses a key (id_ed25519 in this folder); password logins over SSH are off.\nThis file holds a clear-text password for a disposable VM on this PC only.\n", .{ vm_id, entry.name, &creds.password });
    try vm_folder.writeFile(io, .{ .sub_path = "credentials.txt", .data = cred_text });

    var reg = try winlab.vm_registry.load(gpa, io, try openAppData(init));
    defer reg.deinit();
    var vms: std.ArrayList(winlab.vm_registry.Vm) = .empty;
    try vms.appendSlice(arena, reg.vms);
    const vm: winlab.vm_registry.Vm = .{ .id = vm_id, .name = vm_id, .provider = "qemu", .disk = disk, .memory_mb = 2048, .cpus = 2, .training_target = true };
    try vms.append(arena, vm);
    try winlab.vm_registry.save(gpa, io, try openAppData(init), vms.items);

    std.debug.print(
        \\Chimera VM '{s}' registered as a training target.
        \\  folder: {s}
        \\Installing from the live ISO (about a minute; the screen is not shown, progress is read from the serial console).
        \\
    , .{ vm_id, vm_dir });

    // ---- run the live system and drive it over the serial port ----
    const serial_port = try winlab.vm_qemu.pickLoopbackPort(io);
    const argv = try winlab.vm_qemu.buildArgv(arena, &tools, .{
        .disk = disk,
        .iso = iso,
        .answer_iso = seed_path,
        .accel = if (tools.hw_accel) winlab.vm_qemu.hw_accel_kind else .tcg,
        .cpu = if (entry.cpu.len > 0) entry.cpu else "max",
        .show_display = false,
        .no_reboot = true,
        .kernel = kernel,
        .initrd = initrd,
        .append = winlab.vm_chimera.live_cmdline,
        .serial_port = serial_port,
    });
    var child = std.process.spawn(io, .{ .argv = argv, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore }) catch |err| {
        std.debug.print("could not start QEMU: {t}\n", .{err});
        std.process.exit(1);
    };
    var dog: InstallWatchdog = .{ .child = &child, .io = io, .limit_s = 20 * 60 };
    const dog_thread = try std.Thread.spawn(.{}, InstallWatchdog.run, .{&dog});

    const result = driveLiveInstall(gpa, io, serial_port);

    // Let the live system finish powering off (QEMU exits by itself), then make sure it is gone.
    if (result.ok) {
        var waited: u32 = 0;
        while (waited < 90 and winlab.vm_qemu.diskInUse(gpa, disk)) : (waited += 1) std.Io.sleep(io, .fromSeconds(1), .real) catch {};
    }
    dog.cancel.store(true, .release);
    dog_thread.join();
    if (!dog.fired.load(.acquire)) child.kill(io);

    if (!result.ok) {
        std.debug.print("\nThe Chimera install did not finish: {s}\n", .{result.why});
        if (dog.fired.load(.acquire)) std.debug.print("(it ran longer than 20 minutes, so QEMU was stopped)\n", .{});
        if (result.tail.len > 0) std.debug.print("Last output from the guest:\n{s}\n", .{result.tail});
        std.debug.print("The VM folder was left in place for inspection: {s}\nRemove it with: winlab vm remove {s}\n", .{ vm_dir, vm_id });
        std.process.exit(1);
    }
    std.debug.print("\nInstalled. Booting the new system until SSH answers ...\n", .{});
    try superviseUntilReady(init, &tools, vm, null, null, 10);
}

const LiveInstallResult = struct { ok: bool, why: []const u8 = "", tail: []const u8 = "" };

/// Connects to the guest's serial port and runs the conversation in `winlab.vm_chimera.Driver` until it finishes
/// or the connection ends. Progress lines ("WL: ...") are printed as they arrive.
fn driveLiveInstall(gpa: std.mem.Allocator, io: std.Io, port: u16) LiveInstallResult {
    const addr = std.Io.net.IpAddress.parseIp4("127.0.0.1", port) catch return .{ .ok = false, .why = "internal: bad serial address" };
    var stream: std.Io.net.Stream = undefined;
    var tries: u32 = 0;
    while (true) : (tries += 1) {
        if (addr.connect(io, .{ .mode = .stream })) |s| {
            stream = s;
            break;
        } else |_| {
            if (tries >= 100) return .{ .ok = false, .why = "could not connect to the guest's serial port" };
            std.Io.sleep(io, .fromMilliseconds(100), .real) catch {};
        }
    }
    defer stream.close(io);

    var drv = winlab.vm_chimera.Driver.init(gpa);
    defer drv.deinit();
    var reply: std.ArrayList(u8) = .empty;
    defer reply.deinit(gpa);
    var progress: std.ArrayList(u8) = .empty;
    defer progress.deinit(gpa);
    var wbuf: [512]u8 = undefined;
    var w = stream.writer(io, &wbuf);
    var buf: [4096]u8 = undefined;
    std.debug.print("  (waiting for the live system to boot and show its login prompt)\n", .{});
    while (!drv.done()) {
        var iov = [_][]u8{&buf};
        const n = stream.read(io, &iov) catch break;
        if (n == 0) break;
        reply.clearRetainingCapacity();
        progress.clearRetainingCapacity();
        drv.feed(buf[0..n], &reply, &progress) catch return .{ .ok = false, .why = "out of memory" };
        if (progress.items.len > 0) std.debug.print("  {s}", .{progress.items});
        if (reply.items.len > 0) {
            w.interface.writeAll(reply.items) catch break;
            w.interface.flush() catch break;
        }
    }
    // Give the guest a moment to read the final command ("poweroff") before the socket closes.
    std.Io.sleep(io, .fromSeconds(2), .real) catch {};

    if (drv.step == .finished_ok) return .{ .ok = true };
    const why: []const u8 = if (drv.failure.len > 0) drv.failure else if (drv.step == .running) "the connection ended while the install was running" else "the live system never reached a login prompt, or the connection ended early";
    // The last 30 lines of what the install printed, copied into memory that outlives the driver.
    var lines: usize = 0;
    var start: usize = drv.log.items.len;
    while (start > 0 and lines < 30) : (start -= 1) {
        if (drv.log.items[start - 1] == '\n') lines += 1;
    }
    const tail = gpa.dupe(u8, drv.log.items[start..]) catch "";
    return .{ .ok = false, .why = why, .tail = tail };
}

/// `winlab vm install <image-id> <vm-id>`: creates a new training VM from downloaded
/// media with an unattended install, registers it as a training target and starts QEMU
/// (the window shows the install). The install runs in the VM; nothing on this host changes
/// except the new files under %LOCALAPPDATA%\WinLab\vms\<vm-id> and vms.toml.
fn vmInstall(init: std.process.Init, image_id: []const u8, vm_id: []const u8) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();
    if (!winlab.vm_registry.validId(vm_id)) {
        std.debug.print("vm-id must be lowercase letters, digits and '-' (max 48)\n", .{});
        std.process.exit(2);
    }
    var cfg = loadSettings(init);
    defer cfg.deinit();
    var cat = try loadImageCatalog(init, &cfg);
    defer cat.deinit();
    const entry = cat.find(image_id) orelse {
        std.debug.print("unknown image id '{s}' (see: winlab image list)\n", .{image_id});
        std.process.exit(1);
    };
    if (entry.cloud_image) return vmInstallCloud(init, &cfg, entry, vm_id);
    if (entry.installer.len > 0) return vmInstallLive(init, &cfg, entry, vm_id);
    const kind = entry.unattend orelse {
        std.debug.print("'{s}' cannot be installed unattended by WinLab\n", .{image_id});
        std.process.exit(1);
    };
    const images = try imagesDir(init);
    const iso = if (entry.path.len > 0) entry.path else try std.fs.path.join(arena, &.{ images, entry.file });
    if (std.Io.Dir.cwd().statFile(io, iso, .{})) |_| {} else |_| {
        std.debug.print("{s} is not downloaded; run: winlab image fetch {s}\n", .{ entry.file, image_id });
        std.process.exit(1);
    }

    const path = init.environ_map.get("PATH") orelse "";
    var tools = (try winlab.vm_qemu.discover(gpa, io, path, cfg.settings.qemu_path)) orelse {
        std.debug.print("{s}\n", .{winlab.vm_qemu.install_guidance});
        std.process.exit(1);
    };
    defer tools.deinit();

    const local = winlab.platform.dataBase(init.arena.allocator(), init.environ_map) orelse {
        std.debug.print("the data folder is unknown (LOCALAPPDATA or HOME is not set)\n", .{});
        std.process.exit(1);
    };
    const vm_dir = try std.fs.path.join(arena, &.{ local, "WinLab", "vms", vm_id });
    if (std.Io.Dir.cwd().statFile(io, vm_dir, .{})) |_| {
        std.debug.print("{s} already exists; choose another vm-id or remove it yourself\n", .{vm_dir});
        std.process.exit(1);
    } else |_| {}
    const answer_iso = try std.fs.path.join(arena, &.{ vm_dir, "answer.iso" });
    try std.Io.Dir.cwd().createDirPath(io, vm_dir);

    // Throwaway lab credentials: random, written next to the VM, shown once here.
    const alphabet = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    var raw: [20]u8 = undefined;
    io.random(&raw);
    var password: [20]u8 = undefined;
    for (raw, &password) |r, *p| p.* = alphabet[r % alphabet.len];
    // Computer names are limited to 15 characters; derive one from the vm id.
    var name_buf: [15]u8 = undefined;
    var name_len: usize = 0;
    for (vm_id) |c| {
        if (name_len == name_buf.len) break;
        name_buf[name_len] = std.ascii.toUpper(if (c == '-') '-' else c);
        name_len += 1;
    }
    const computer_name = std.mem.trimEnd(u8, name_buf[0..name_len], "-");

    var xml: std.Io.Writer.Allocating = .init(gpa);
    defer xml.deinit();
    try winlab.vm_unattend.write(.{ .kind = kind, .image_index = entry.image_index, .computer_name = computer_name, .password = &password, .first_logon_script = true }, &xml.writer);
    var vm_folder = try std.Io.Dir.cwd().openDir(io, vm_dir, .{});
    defer vm_folder.close(io);
    const creds = try std.fmt.allocPrint(arena, "Throwaway lab VM '{s}' (built from {s}).\nUser: {s}\nPassword: {s}\nThis file holds a clear-text password for a disposable VM on this PC only.\n", .{ vm_id, entry.name, if (kind == .server) "Administrator" else "labadmin", &password });
    try vm_folder.writeFile(io, .{ .sub_path = "credentials.txt", .data = creds });

    // Guest control: a per-VM SSH key (the private half never leaves the VM folder), the guest-side
    // setup script and the public key on the answer drive, and a loopback-only port forward.
    const keygen = try winlab.platform.tool(arena, init.io, init.environ_map, .ssh_keygen);
    const key_path = try std.fs.path.join(arena, &.{ vm_dir, winlab.vm_guest.key_file });
    const comment = try std.fmt.allocPrint(arena, "winlab-{s}", .{vm_id});
    const keygen_run = std.process.run(gpa, io, .{ .argv = &.{ keygen, "-q", "-t", "ed25519", "-N", "", "-C", comment, "-f", key_path } }) catch |err| {
        std.debug.print("cannot run {s}: {t} (the Windows OpenSSH client is required for lab control)\n", .{ keygen, err });
        std.process.exit(1);
    };
    defer gpa.free(keygen_run.stdout);
    defer gpa.free(keygen_run.stderr);
    if (keygen_run.term != .exited or keygen_run.term.exited != 0) {
        std.debug.print("ssh-keygen failed:\n{s}\n", .{keygen_run.stderr});
        std.process.exit(1);
    }
    const pub_text = try vm_folder.readFileAlloc(io, "id_ed25519.pub", arena, .limited(4096));
    // The answer media is an ordinary CD-ROM image (a USB drive made from a folder sometimes
    // left the BIOS spinning after the first reboot).
    const answer_bytes = try winlab.vm_iso9660.build(gpa, "WINLAB_ANSWERS", &.{
        .{ .name = "Autounattend.xml", .data = xml.written() },
        .{ .name = "winlab_firstlogon.ps1", .data = winlab.vm_unattend.first_logon_script },
        .{ .name = "authorized_key.pub", .data = pub_text },
    });
    defer gpa.free(answer_bytes);
    try vm_folder.writeFile(io, .{ .sub_path = "answer.iso", .data = answer_bytes });
    const ssh_port = try winlab.vm_qemu.pickLoopbackPort(io);
    // Windows 11 24H2 needs SSE4.2/POPCNT, which the default `qemu64` CPU model lacks (untested here).
    const cpu_line: []const u8 = if (kind == .client) "cpu = \"max\"\n" else "";
    const guest_toml = try std.fmt.allocPrint(arena, "ssh_port = {d}\nssh_user = \"{s}\"\n{s}", .{ ssh_port, if (kind == .server) "Administrator" else "labadmin", cpu_line });
    try vm_folder.writeFile(io, .{ .sub_path = winlab.vm_guest.guest_file, .data = guest_toml });

    const disk = try std.fs.path.join(arena, &.{ vm_dir, "disk.qcow2" });
    const made = try std.process.run(gpa, io, .{ .argv = &.{ tools.qemu_img, "create", "-f", "qcow2", disk, "48G" } });
    defer gpa.free(made.stdout);
    defer gpa.free(made.stderr);
    if (made.term != .exited or made.term.exited != 0) {
        std.debug.print("qemu-img could not create the disk:\n{s}\n", .{made.stderr});
        std.process.exit(1);
    }

    // Register as a training target (this command is the explicit action creating a VM meant for labs).
    var reg = try winlab.vm_registry.load(gpa, io, try openAppData(init));
    defer reg.deinit();
    var vms: std.ArrayList(winlab.vm_registry.Vm) = .empty;
    try vms.appendSlice(arena, reg.vms);
    try vms.append(arena, .{ .id = vm_id, .name = vm_id, .provider = "qemu", .disk = disk, .memory_mb = 4096, .cpus = 2, .training_target = true });
    try winlab.vm_registry.save(gpa, io, try openAppData(init), vms.items);

    std.debug.print(
        \\VM '{s}' created and registered as a training target.
        \\  folder:      {s}
        \\  credentials: {s}{c}credentials.txt  (user {s}, password {s})
        \\  The installer runs unattended and the guest restarts several times. Keep this command
        \\  running: it relaunches QEMU after each restart and finishes when the guest answers over SSH.
        \\
    , .{ vm_id, vm_dir, vm_dir, winlab.platform.dir_sep, if (kind == .server) "Administrator" else "labadmin", &password });
    try superviseUntilReady(init, &tools, .{ .id = vm_id, .name = vm_id, .provider = "qemu", .disk = disk, .training_target = true }, iso, answer_iso, 120);
}

/// `winlab vm list`: registered VMs, whether each is running, and which snapshots/scenarios exist.
fn vmList(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();
    var cfg = loadSettings(init);
    defer cfg.deinit();
    var reg = try winlab.vm_registry.load(gpa, io, try openAppData(init));
    defer reg.deinit();
    if (reg.vms.len == 0) {
        std.debug.print("No VMs are registered. Build one with: winlab vm install <image-id> <vm-id>\n", .{});
        return;
    }
    var tools = try winlab.vm_qemu.discover(gpa, io, init.environ_map.get("PATH") orelse "", cfg.settings.qemu_path);
    defer if (tools) |*t| t.deinit();
    var q: ?winlab.vm_qemu.Qemu = null;
    if (tools) |*t| q = .{ .gpa = gpa, .io = io, .tools = t };

    // Scenario labs (id list), to show which are built.
    var lab_ids: std.ArrayList([]const u8) = .empty;
    const root = contentRoot(init, cfg.settings.content_path);
    if (std.Io.Dir.cwd().openDir(io, try std.fs.path.join(arena, &.{ root, "labs" }), .{ .iterate = true })) |d| {
        var dir = d;
        defer dir.close(io);
        var it = dir.iterate();
        while (try it.next(io)) |e| {
            if (e.kind != .file or !std.mem.endsWith(u8, e.name, ".toml")) continue;
            const text = dir.readFileAlloc(io, e.name, arena, .limited(256 * 1024)) catch continue;
            var p = winlab.lab.parse(gpa, text, null) catch continue;
            defer p.deinit();
            if (p.lab.symptom.len > 0) try lab_ids.append(arena, try arena.dupe(u8, p.lab.id));
        }
    } else |_| {}

    for (reg.vms) |vm| {
        const running = winlab.vm_qemu.diskInUse(gpa, vm.disk);
        std.debug.print("{s}  ({s}, {s}{s})\n  disk: {s}\n", .{ vm.id, vm.provider, if (running) "RUNNING" else "stopped", if (vm.training_target) ", training target" else ", NOT a training target", vm.disk });
        if (q) |*qq| {
            const prov = qq.provider();
            if (!running) {
                const clean = prov.hasSnapshot(vm.target(), winlab.lab.clean_snapshot) catch false;
                std.debug.print("  clean snapshot ({s}): {s}\n", .{ winlab.lab.clean_snapshot, if (clean) "yes" else "NO" });
                for (lab_ids.items) |id| {
                    const name = try std.fmt.allocPrint(arena, "winlab-scenario-{s}", .{id});
                    const built = prov.hasSnapshot(vm.target(), name) catch false;
                    std.debug.print("  scenario {s}: {s}\n", .{ id, if (built) "built" else "not built" });
                }
            } else std.debug.print("  (snapshots are not listed while the VM is running)\n", .{});
        }
    }
}

/// `winlab vm remove <vm-id>`: deletes a training VM's folder and registry entry. Refuses if the VM is
/// running, is not a training target, or its folder is not under %LOCALAPPDATA%\WinLab\vms. Asks first.
fn vmRemove(init: std.process.Init, vm_id: []const u8) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();
    var reg = try winlab.vm_registry.load(gpa, io, try openAppData(init));
    defer reg.deinit();
    const vm = reg.find(vm_id) orelse {
        std.debug.print("'{s}' is not a registered VM\n", .{vm_id});
        std.process.exit(1);
    };
    if (!vm.training_target) {
        std.debug.print("'{s}' is not marked as a training target; refusing to delete it\n", .{vm_id});
        std.process.exit(1);
    }
    const local = winlab.platform.dataBase(init.arena.allocator(), init.environ_map) orelse {
        std.debug.print("the data folder is unknown (LOCALAPPDATA or HOME is not set)\n", .{});
        std.process.exit(1);
    };
    const expected = try std.fs.path.join(arena, &.{ local, "WinLab", "vms", vm_id });
    const folder = std.fs.path.dirname(vm.disk) orelse "";
    if (!std.ascii.eqlIgnoreCase(folder, expected)) {
        std.debug.print("the VM's disk is not in {s}; WinLab only deletes VMs it created there. Remove it by hand.\n", .{expected});
        std.process.exit(1);
    }
    if (winlab.vm_qemu.diskInUse(gpa, vm.disk)) {
        std.debug.print("the VM is running (its disk is open); stop it first\n", .{});
        std.process.exit(1);
    }
    std.debug.print("This permanently deletes the VM '{s}' and everything in {s}. Type yes to continue: ", .{ vm_id, folder });
    var rbuf: [64]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &rbuf);
    const answer = stdin_reader.interface.takeDelimiterExclusive('\n') catch "";
    if (!std.mem.eql(u8, std.mem.trim(u8, answer, " \r\t"), "yes")) {
        std.debug.print("Cancelled; nothing was deleted.\n", .{});
        return;
    }
    // Registry first: if the delete then fails, no entry points at half a VM.
    var keep: std.ArrayList(winlab.vm_registry.Vm) = .empty;
    for (reg.vms) |v| {
        if (!std.mem.eql(u8, v.id, vm_id)) try keep.append(arena, v);
    }
    try winlab.vm_registry.save(gpa, io, try openAppData(init), keep.items);
    std.Io.Dir.cwd().deleteTree(io, folder) catch |err| {
        std.debug.print("removed from the registry, but deleting {s} failed: {t}\n", .{ folder, err });
        std.process.exit(1);
    };
    std.debug.print("Removed '{s}'.\n", .{vm_id});
}

/// `winlab vm reboot-test <vm-id>`: proves a guest restart does not end the session. Starts the VM,
/// restarts Windows from inside, waits for the supervisor to bring it back, checks the boot time
/// changed, and stops the VM.
fn vmRebootTest(init: std.process.Init, vm_id: []const u8) !void {
    const gpa = init.gpa;
    const io = init.io;
    var cfg = loadSettings(init);
    defer cfg.deinit();
    var reg = try winlab.vm_registry.load(gpa, io, try openAppData(init));
    defer reg.deinit();
    const vm = reg.find(vm_id) orelse {
        std.debug.print("'{s}' is not a registered VM\n", .{vm_id});
        std.process.exit(1);
    };
    if (!vm.training_target) {
        std.debug.print("'{s}' is not a training target\n", .{vm_id});
        std.process.exit(1);
    }
    var tools = (try winlab.vm_qemu.discover(gpa, io, init.environ_map.get("PATH") orelse "", cfg.settings.qemu_path)) orelse {
        std.debug.print("{s}\n", .{winlab.vm_qemu.install_guidance});
        std.process.exit(1);
    };
    defer tools.deinit();
    const ssh_exe = try winlab.platform.tool(init.arena.allocator(), init.io, init.environ_map, .ssh);
    var q: winlab.vm_qemu.Qemu = .{ .gpa = gpa, .io = io, .tools = &tools, .ssh_exe = ssh_exe };
    const prov = q.provider();
    const t = vm.target();
    const boot_query = "(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('o')";

    std.debug.print("[1] start the VM\n", .{});
    prov.start(t) catch |e| {
        std.debug.print("start failed: {t}\n", .{e});
        std.process.exit(1);
    };
    const before = prov.runInGuest(gpa, t, boot_query) catch |e| {
        std.debug.print("could not read the boot time: {t}\n", .{e});
        _ = prov.stop(t) catch {};
        std.process.exit(1);
    };
    defer gpa.free(before.output);
    std.debug.print("[2] boot time: {s}\n", .{trimOut(before.output)});
    std.debug.print("[3] restart Windows from inside the guest\n", .{});
    if (prov.runInGuest(gpa, t, "Restart-Computer -Force")) |r| gpa.free(r.output) else |_| {}
    std.Io.sleep(io, .fromSeconds(20), .real) catch {};
    std.debug.print("[4] waiting for the supervisor to bring the guest back...\n", .{});
    if (!winlab.vm_qemu.waitReady(&q, t, 300)) {
        std.debug.print("the guest did not come back\n", .{});
        _ = prov.stop(t) catch {};
        std.process.exit(1);
    }
    const after = prov.runInGuest(gpa, t, boot_query) catch |e| {
        std.debug.print("could not read the boot time after the restart: {t}\n", .{e});
        _ = prov.stop(t) catch {};
        std.process.exit(1);
    };
    defer gpa.free(after.output);
    std.debug.print("[5] boot time: {s}\n", .{trimOut(after.output)});
    prov.stop(t) catch |e| std.debug.print("stop failed: {t}\n", .{e});
    const ok = !std.mem.eql(u8, trimOut(before.output), trimOut(after.output)) and trimOut(after.output).len > 0;
    std.debug.print("\nREBOOT-TEST {s}\n", .{if (ok) "PASSED: the session survived a guest restart" else "FAILED: the boot time did not change"});
    if (!ok) std.process.exit(1);
}

/// `winlab vm resume <vm-id>`: continue an unattended install that was interrupted (for example by
/// closing the terminal that ran `vm install`), supervising restarts until the guest answers over SSH.
fn vmResume(init: std.process.Init, vm_id: []const u8) !void {
    const gpa = init.gpa;
    const io = init.io;
    var cfg = loadSettings(init);
    defer cfg.deinit();
    var reg = try winlab.vm_registry.load(gpa, io, try openAppData(init));
    defer reg.deinit();
    const vm = reg.find(vm_id) orelse {
        std.debug.print("'{s}' is not a registered VM\n", .{vm_id});
        std.process.exit(1);
    };
    if (!vm.training_target) {
        std.debug.print("'{s}' is not marked as a training target\n", .{vm_id});
        std.process.exit(1);
    }
    var tools = (try winlab.vm_qemu.discover(gpa, io, init.environ_map.get("PATH") orelse "", cfg.settings.qemu_path)) orelse {
        std.debug.print("{s}\n", .{winlab.vm_qemu.install_guidance});
        std.process.exit(1);
    };
    defer tools.deinit();
    const dir = std.fs.path.dirname(vm.disk) orelse ".";
    const answer = try std.fs.path.join(init.arena.allocator(), &.{ dir, "answer.iso" });
    const have_answer = if (std.Io.Dir.cwd().statFile(io, answer, .{})) |_| true else |_| false;
    try superviseUntilReady(init, &tools, vm, null, if (have_answer) answer else null, 120);
}

/// Runs QEMU for `vm` and keeps it running across guest restarts until the guest answers over SSH
/// (or `max_minutes` pass). A guest restart inside one QEMU process leaves the BIOS spinning forever
/// under WHPX (seen repeatedly), so QEMU runs with -no-reboot and is relaunched after each restart.
fn superviseUntilReady(init: std.process.Init, tools: *const winlab.vm_qemu.Tools, vm: winlab.vm_registry.Vm, iso: ?[]const u8, answer_iso: ?[]const u8, max_minutes: u32) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const dir = std.fs.path.dirname(vm.disk) orelse ".";
    const access = try winlab.vm_guest.load(arena, io, dir);
    const ssh_exe = try winlab.platform.tool(arena, init.io, init.environ_map, .ssh);

    var run: u32 = 0;
    var waited_s: u32 = 0;
    while (run < 12 and waited_s < max_minutes * 60) : (run += 1) {
        const qmp = try winlab.vm_qemu.pickLoopbackPort(io);
        const argv = try winlab.vm_qemu.buildArgv(arena, tools, .{
            .disk = vm.disk,
            // Installer media only until Windows is installed; once the disk boots, nothing else is needed.
            .iso = iso,
            .answer_iso = answer_iso,
            .accel = if (tools.hw_accel) winlab.vm_qemu.hw_accel_kind else .tcg,
            .qmp_port = qmp,
            .ssh_port = access.port,
            .cpu = access.cpu,
            .no_reboot = true,
        });
        _ = std.process.spawn(io, .{ .argv = argv, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore }) catch |err| {
            std.debug.print("could not start QEMU: {t}\n", .{err});
            std.process.exit(1);
        };
        std.debug.print("[{d} min] QEMU run {d} started (QMP 127.0.0.1:{d}, SSH 127.0.0.1:{d})\n", .{ waited_s / 60, run + 1, qmp, access.port });
        std.Io.sleep(io, .fromSeconds(5), .real) catch {};
        waited_s += 5;
        while (waited_s < max_minutes * 60) {
            if (winlab.vm_guest.exec(gpa, io, ssh_exe, dir, access, "exit 0")) |r| {
                gpa.free(r.output);
                std.debug.print("[{d} min] guest is ready: SSH answers on 127.0.0.1:{d}. VM left running.\n", .{ waited_s / 60, access.port });
                // Before the learner takes the clean snapshot, so every lab made from it logs in by itself.
                applyAutologin(init, ssh_exe, dir, access) catch |e| std.debug.print("auto-login was not turned on ({t}); log in with the password in credentials.txt\n", .{e});
                return;
            } else |_| {}
            if (!winlab.vm_qemu.diskInUse(gpa, vm.disk)) {
                std.debug.print("[{d} min] the guest restarted (QEMU exited); relaunching\n", .{waited_s / 60});
                break;
            }
            std.Io.sleep(io, .fromSeconds(10), .real) catch {};
            waited_s += 10;
        }
    }
    std.debug.print("gave up waiting for the guest after {d} minutes; it may still be installing (try: winlab vm resume {s})\n", .{ waited_s / 60, vm.id });
    std.process.exit(1);
}

/// The VM's own login from its `credentials.txt`, copied into `arena`; null if the file or a line is missing.
fn readLogin(arena: std.mem.Allocator, io: std.Io, vm_dir: []const u8) ?winlab.vm_autologin.Login {
    const path = std.fs.path.join(arena, &.{ vm_dir, "credentials.txt" }) catch return null;
    const text = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(16 * 1024)) catch return null;
    return winlab.vm_autologin.parseCredentials(text);
}

/// Turns on automatic logon in a running guest. It takes effect at the guest's next boot.
fn applyAutologin(init: std.process.Init, ssh_exe: []const u8, vm_dir: []const u8, access: winlab.vm_guest.Access) !void {
    const arena = init.arena.allocator();
    const login = readLogin(arena, init.io, vm_dir) orelse return error.NoCredentials;
    const text = try winlab.vm_autologin.script(arena, access.shell, access.distro, login);
    const r = try winlab.vm_guest.exec(init.gpa, init.io, ssh_exe, vm_dir, access, text);
    defer init.gpa.free(r.output);
    if (r.exit_code != 0) {
        std.debug.print("{s}\n", .{r.output});
        return error.GuestFailed;
    }
    std.debug.print("auto-login is on for user {s} from the guest's next boot\n", .{login.user});
}

/// `winlab vm autologin <vm-id> <snapshot>`: turns on automatic logon inside one saved snapshot: restore it,
/// boot, change the setting, shut down, and save it again under the same name. The VM's current disk state is
/// discarded. If anything fails before saving, the snapshot is left as it was.
fn vmAutologin(init: std.process.Init, vm_id: []const u8, snap: []const u8) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();
    var cfg = loadSettings(init);
    defer cfg.deinit();
    var reg = try winlab.vm_registry.load(gpa, io, try openAppData(init));
    defer reg.deinit();
    const vm = reg.find(vm_id) orelse {
        std.debug.print("'{s}' is not a registered VM\n", .{vm_id});
        std.process.exit(1);
    };
    if (!vm.training_target) {
        std.debug.print("'{s}' is not marked as a training target; refusing to change it\n", .{vm_id});
        std.process.exit(1);
    }
    if (!winlab.vm_provider.validSnapshotName(snap)) {
        std.debug.print("that is not a valid snapshot name\n", .{});
        std.process.exit(2);
    }
    var tools = (try winlab.vm_qemu.discover(gpa, io, init.environ_map.get("PATH") orelse "", cfg.settings.qemu_path)) orelse {
        std.debug.print("{s}\n", .{winlab.vm_qemu.install_guidance});
        std.process.exit(1);
    };
    defer tools.deinit();
    const ssh_exe = try winlab.platform.tool(arena, io, init.environ_map, .ssh);
    var q: winlab.vm_qemu.Qemu = .{ .gpa = gpa, .io = io, .tools = &tools, .ssh_exe = ssh_exe };
    const prov = q.provider();
    const t = vm.target();
    const dir = std.fs.path.dirname(vm.disk) orelse ".";
    const access = try winlab.vm_guest.load(arena, io, dir);

    if ((try prov.state(t)) != .stopped) {
        std.debug.print("the VM is running; stop it first\n", .{});
        std.process.exit(1);
    }
    if (!try prov.hasSnapshot(t, snap)) {
        std.debug.print("'{s}' has no snapshot named {s}\n", .{ vm_id, snap });
        std.process.exit(1);
    }
    std.debug.print("restoring '{s}' and booting {s} ...\n", .{ snap, vm_id });
    try prov.restoreSnapshot(t, snap);
    {
        errdefer {
            prov.stop(t) catch {};
            prov.restoreSnapshot(t, snap) catch {};
        }
        try prov.start(t);
        try applyAutologin(init, ssh_exe, dir, access);
        std.debug.print("shutting down ...\n", .{});
        try prov.stop(t);
    }
    // The disk now holds the changed state, so a failure between these two steps loses no data: take it again
    // with `winlab vm snapshot`.
    try prov.deleteSnapshot(t, snap);
    prov.createSnapshot(t, snap) catch |e| {
        std.debug.print("could not save the snapshot again ({t}). Do not start the VM; run: winlab vm snapshot {s} {s}\n", .{ e, vm_id, snap });
        std.process.exit(1);
    };
    std.debug.print("saved '{s}' with auto-login on\n", .{snap});
}

/// `winlab vm snapshot|restore|delete-snapshot <vm-id> <name>` on a registered training target.
/// Refuses unregistered VMs and VMs that are running (the provider checks the disk is not open).
fn vmSnapshotOp(init: std.process.Init, op: []const u8, vm_id: []const u8, snap: []const u8) !void {
    const gpa = init.gpa;
    const io = init.io;
    var cfg = loadSettings(init);
    defer cfg.deinit();
    var reg = try winlab.vm_registry.load(gpa, io, try openAppData(init));
    defer reg.deinit();
    const vm = reg.find(vm_id) orelse {
        std.debug.print("'{s}' is not a registered VM (see %APPDATA%\\WinLab\\vms.toml)\n", .{vm_id});
        std.process.exit(1);
    };
    if (!vm.training_target) {
        std.debug.print("'{s}' is registered but not marked as a training target; refusing to change it\n", .{vm_id});
        std.process.exit(1);
    }
    if (!winlab.vm_provider.validSnapshotName(snap)) {
        std.debug.print("snapshot names may use letters, digits, '-', '_' and '.' (not starting with '-')\n", .{});
        std.process.exit(2);
    }
    var tools = (try winlab.vm_qemu.discover(gpa, io, init.environ_map.get("PATH") orelse "", cfg.settings.qemu_path)) orelse {
        std.debug.print("{s}\n", .{winlab.vm_qemu.install_guidance});
        std.process.exit(1);
    };
    defer tools.deinit();
    var q: winlab.vm_qemu.Qemu = .{ .gpa = gpa, .io = io, .tools = &tools };
    const prov = q.provider();
    const target = vm.target();
    std.debug.print("VM '{s}' ({s}), disk {s}\n", .{ vm.id, vm.name, vm.disk });
    const result = if (std.mem.eql(u8, op, "snapshot"))
        prov.createSnapshot(target, snap)
    else if (std.mem.eql(u8, op, "restore"))
        prov.restoreSnapshot(target, snap)
    else
        prov.deleteSnapshot(target, snap);
    result catch |err| {
        const why = switch (err) {
            error.WrongState => "the VM is running (its disk is open); shut it down first",
            error.SnapshotExists => "a snapshot with that name already exists",
            error.SnapshotNotFound => "no snapshot with that name",
            else => "the provider failed",
        };
        std.debug.print("{s} failed: {s}\n", .{ op, why });
        std.process.exit(1);
    };
    std.debug.print("{s} '{s}': done\n", .{ op, snap });
}

/// `winlab lab verify-set <vm-id> <lab.toml>...`: proves several SCRIPTING labs in a single boot. For each
/// lab: write the starter file, Check must fail; install the reference solution, Check must pass.
/// The VM is restored to its clean snapshot afterwards. (State-fixing scenarios need `lab verify`,
/// because their broken state is baked into a snapshot.)
fn labVerifySet(init: std.process.Init, vm_id: []const u8, lab_paths: []const [:0]const u8) !void {
    const gpa = init.gpa;
    const io = init.io;
    var cfg = loadSettings(init);
    defer cfg.deinit();
    var reg = try winlab.vm_registry.load(gpa, io, try openAppData(init));
    defer reg.deinit();
    const vm = reg.find(vm_id) orelse {
        std.debug.print("'{s}' is not a registered VM\n", .{vm_id});
        std.process.exit(1);
    };
    const access = winlab.vm_guest.load(init.arena.allocator(), io, std.fs.path.dirname(vm.disk) orelse ".") catch {
        std.debug.print("'{s}' has no guest.toml; it cannot be controlled\n", .{vm_id});
        std.process.exit(1);
    };
    var tools = (try winlab.vm_qemu.discover(gpa, io, init.environ_map.get("PATH") orelse "", cfg.settings.qemu_path)) orelse {
        std.debug.print("{s}\n", .{winlab.vm_qemu.install_guidance});
        std.process.exit(1);
    };
    defer tools.deinit();
    const ssh_exe = try winlab.platform.tool(init.arena.allocator(), init.io, init.environ_map, .ssh);
    var q: winlab.vm_qemu.Qemu = .{ .gpa = gpa, .io = io, .tools = &tools, .ssh_exe = ssh_exe };
    const prov = q.provider();
    const t = vm.target();

    // Load every lab first, so a typo is found before a VM boots.
    var texts: std.ArrayList([]u8) = .empty;
    var parsed: std.ArrayList(winlab.lab.Parsed) = .empty;
    defer {
        for (parsed.items) |*p| p.deinit();
        parsed.deinit(gpa);
        for (texts.items) |x| gpa.free(x);
        texts.deinit(gpa);
    }
    for (lab_paths) |path| {
        const text = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(256 * 1024)) catch |err| {
            std.debug.print("{s}: cannot read: {t}\n", .{ path, err });
            std.process.exit(1);
        };
        try texts.append(gpa, text);
        var failure: winlab.lab.Failure = .{};
        const p = winlab.lab.parse(gpa, text, &failure) catch |err| {
            std.debug.print("{s}: invalid lab ({t}) {s}: {s}\n", .{ path, err, failure.field, failure.message });
            std.process.exit(1);
        };
        if (p.lab.kind != .script or (p.lab.target == .linux) != (access.shell == .bash)) {
            std.debug.print("{s}: not a scripting lab for this VM's OS\n", .{path});
            std.process.exit(1);
        }
        try parsed.append(gpa, p);
    }

    std.debug.print("restore the clean snapshot and boot {s}...\n", .{vm_id});
    prov.restoreSnapshot(t, winlab.lab.clean_snapshot) catch |e| scenarioFail("restore", e);
    prov.start(t) catch |e| scenarioFail("start", e);
    var failed: usize = 0;
    for (parsed.items, lab_paths) |p, path| {
        const lab = p.lab;
        var ok = true;
        const setup = prov.runInGuest(gpa, t, lab.setup) catch |e| {
            std.debug.print("  {s}: could not write the starter file: {t}\n", .{ lab.id, e });
            failed += 1;
            continue;
        };
        gpa.free(setup.output);
        const before = prov.runInGuest(gpa, t, lab.validate.script) catch |e| {
            std.debug.print("  {s}: the check could not run: {t}\n", .{ lab.id, e });
            failed += 1;
            continue;
        };
        defer gpa.free(before.output);
        const before_pass = std.mem.indexOf(u8, before.output, lab.validate.expect_output_contains) != null;
        if (before_pass) {
            ok = false;
            std.debug.print("  {s}: the STARTER already passes (it should not)\n", .{lab.id});
        }
        const sol = prov.runInGuest(gpa, t, lab.solution) catch |e| {
            std.debug.print("  {s}: could not install the solution: {t}\n", .{ lab.id, e });
            failed += 1;
            continue;
        };
        gpa.free(sol.output);
        const after = prov.runInGuest(gpa, t, lab.validate.script) catch |e| {
            std.debug.print("  {s}: the check could not run after the solution: {t}\n", .{ lab.id, e });
            failed += 1;
            continue;
        };
        defer gpa.free(after.output);
        if (std.mem.indexOf(u8, after.output, lab.validate.expect_output_contains) == null) {
            ok = false;
            std.debug.print("  {s}: the reference SOLUTION does not pass:\n{s}\n", .{ lab.id, trimOut(after.output) });
        }
        std.debug.print("{s} {s} ({s}; starter: {s})\n", .{ if (ok) "PASS" else "FAIL", lab.id, path, trimOut(before.output)[0..@min(trimOut(before.output).len, 60)] });
        if (!ok) failed += 1;
    }
    std.debug.print("stop the VM and restore the clean snapshot\n", .{});
    prov.stop(t) catch |e| std.debug.print("stop failed: {t}\n", .{e});
    prov.restoreSnapshot(t, winlab.lab.clean_snapshot) catch |e| std.debug.print("restore failed: {t}\n", .{e});
    std.debug.print("\nVERIFY-SET {s}: {d} lab(s), {d} failed\n", .{ if (failed == 0) "PASSED" else "FAILED", parsed.items.len, failed });
    if (failed != 0) std.process.exit(1);
}

const ScenarioOp = enum { build, start, check, reset, end, verify };

/// Everything a scenario command needs, opened in place so internal pointers stay valid.
const LabCtx = struct {
    gpa: std.mem.Allocator,
    text: []u8,
    parsed: winlab.lab.Parsed,
    reg: winlab.vm_registry.Registry,
    vm: winlab.vm_registry.Vm,
    tools: winlab.vm_qemu.Tools,
    q: winlab.vm_qemu.Qemu,

    fn open(self: *LabCtx, init: std.process.Init, lab_path: []const u8, vm_id: []const u8) !void {
        const gpa = init.gpa;
        const io = init.io;
        self.gpa = gpa;
        var cfg = loadSettings(init);
        defer cfg.deinit();
        self.text = std.Io.Dir.cwd().readFileAlloc(io, lab_path, gpa, .limited(256 * 1024)) catch |err| {
            std.debug.print("{s}: cannot read lab: {t}\n", .{ lab_path, err });
            std.process.exit(1);
        };
        var failure: winlab.lab.Failure = .{};
        self.parsed = winlab.lab.parse(gpa, self.text, &failure) catch |err| {
            std.debug.print("{s}: invalid lab ({t}) {s}: {s}\n", .{ lab_path, err, failure.field, failure.message });
            std.process.exit(1);
        };
        self.reg = try winlab.vm_registry.load(gpa, io, try openAppData(init));
        self.vm = self.reg.find(vm_id) orelse {
            std.debug.print("'{s}' is not a registered VM\n", .{vm_id});
            std.process.exit(1);
        };
        // A lab only runs on a VM of the right OS (guest.toml says which shell the guest uses).
        if (winlab.vm_guest.load(init.arena.allocator(), io, std.fs.path.dirname(self.vm.disk) orelse ".")) |access| {
            const is_linux = access.shell == .bash;
            if (is_linux != (self.parsed.lab.target == .linux)) {
                std.debug.print("lab {s} targets {s}, but VM '{s}' is a {s} VM\n", .{ self.parsed.lab.id, @tagName(self.parsed.lab.target), vm_id, if (is_linux) "linux" else "windows" });
                std.process.exit(1);
            }
        } else |_| {}
        self.tools = (try winlab.vm_qemu.discover(gpa, io, init.environ_map.get("PATH") orelse "", cfg.settings.qemu_path)) orelse {
            std.debug.print("{s}\n", .{winlab.vm_qemu.install_guidance});
            std.process.exit(1);
        };
        const ssh_exe = try winlab.platform.tool(init.arena.allocator(), init.io, init.environ_map, .ssh);
        self.q = .{ .gpa = gpa, .io = io, .tools = &self.tools, .ssh_exe = ssh_exe };
    }

    fn deinit(self: *LabCtx) void {
        self.tools.deinit();
        self.reg.deinit();
        self.parsed.deinit();
        self.gpa.free(self.text);
    }

    fn scenario(self: *LabCtx) winlab.lab.Scenario {
        return winlab.lab.Scenario.init(self.gpa, self.q.provider(), self.vm, self.parsed.lab);
    }
};

fn scenarioFail(op: []const u8, err: anyerror) noreturn {
    const why = switch (err) {
        error.NoSymptom => "the lab has no symptom text, so it cannot be a scenario",
        error.NoCleanSnapshot => "the VM has no 'winlab-clean' snapshot (take one on a freshly installed, stopped VM)",
        error.ScenarioExists => "the scenario is already built (use --rebuild to replace it)",
        error.NoScenario => "the scenario has not been built yet (run: winlab lab build ...)",
        error.NotTrainingTarget => "the VM is not marked as a training target",
        error.VmNotStopped => "the VM is running; end the session first (winlab lab end ...)",
        error.MissingCapability => "the provider cannot start/snapshot/run commands in this VM",
        error.GuestFailed => "a script in the guest failed",
        error.WrongState => "the VM is in the wrong state for that (running or stopped)",
        else => @errorName(err),
    };
    std.debug.print("{s} failed: {s}\n", .{ op, why });
    std.process.exit(1);
}

fn trimOut(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \r\n\t");
}

/// Learner-facing commands for baked scenarios (decision record 0006).
fn scenarioCmd(init: std.process.Init, op: ScenarioOp, lab_path: []const u8, vm_id: []const u8, rebuild: bool) !void {
    var ctx: LabCtx = undefined;
    try ctx.open(init, lab_path, vm_id);
    defer ctx.deinit();
    var s = ctx.scenario();
    const lab = ctx.parsed.lab;
    const gpa = init.gpa;
    switch (op) {
        .build => {
            std.debug.print("Building scenario '{s}' on {s}: restore the clean snapshot, boot, set up, break it, shut down, snapshot.\n", .{ lab.id, ctx.vm.id });
            s.build(rebuild) catch |e| scenarioFail("build", e);
            std.debug.print("built: snapshot '{s}'\n", .{s.snapshotName()});
        },
        .start => {
            s.begin() catch |e| scenarioFail("start", e);
            std.debug.print("\nScenario: {s}\n\nReported problem:\n  {s}\n\nThe VM is running (its window is open). Fix it, then run:\n  winlab lab check {s} {s}\n", .{ lab.title, lab.symptom, lab_path, vm_id });
        },
        .check => {
            const r = s.validate() catch |e| scenarioFail("check", e);
            defer gpa.free(r.output);
            std.debug.print("{s}\n", .{if (r.passed) "FIXED: the machine is in the expected state." else "NOT FIXED YET: the problem is still there."});
        },
        .reset => {
            s.reset() catch |e| scenarioFail("reset", e);
            std.debug.print("reset: the VM is stopped and back at the starting problem (run lab start to boot it)\n", .{});
        },
        .end => {
            s.end() catch |e| scenarioFail("end", e);
            std.debug.print("the VM is stopped\n", .{});
        },
        .verify => {
            // Author check: the baked machine must be broken, the solution must fix it, and a reset must break it again.
            if (lab.solution.len == 0) {
                std.debug.print("verify needs a `solution` in the lab file\n", .{});
                std.process.exit(1);
            }
            std.debug.print("[1] start the baked scenario\n", .{});
            s.begin() catch |e| scenarioFail("start", e);
            const before = s.validate() catch |e| scenarioFail("validate (before)", e);
            defer gpa.free(before.output);
            std.debug.print("[2] validation before the fix: {s} ({s})\n", .{ if (before.passed) "PASSED (unexpected!)" else "failed, as it should", trimOut(before.output) });
            // A solution that restarts Windows may drop the connection, or may return first and restart a while
            // later (slower with a user signed in). So remember the boot time and wait for it to change.
            const restarts = std.mem.indexOf(u8, lab.solution, "Restart-Computer") != null;
            const boot_before: ?[]u8 = if (restarts) bootTime(gpa, ctx.q.provider(), ctx.vm.target()) else null;
            defer if (boot_before) |b| gpa.free(b);
            if (restarts and boot_before == null) {
                std.debug.print("solution failed: could not read the guest's boot time\n", .{});
                std.process.exit(1);
            }
            if (ctx.q.provider().runInGuest(gpa, ctx.vm.target(), lab.solution)) |fixed| {
                gpa.free(fixed.output);
            } else |e| switch (e) {
                error.ProviderFailed => if (!restarts) std.Io.sleep(init.io, .fromSeconds(30), .real) catch {},
                else => scenarioFail("solution", e),
            }
            if (boot_before) |old| waitForNewBoot(init.io, gpa, ctx.q.provider(), ctx.vm.target(), old);
            const after = s.validate() catch |e| scenarioFail("validate (after)", e);
            defer gpa.free(after.output);
            std.debug.print("[3] validation after the solution: {s} ({s})\n", .{ if (after.passed) "PASSED" else "FAILED", trimOut(after.output) });
            std.debug.print("[4] reset, start again\n", .{});
            s.reset() catch |e| scenarioFail("reset", e);
            s.begin() catch |e| scenarioFail("restart", e);
            const again = s.validate() catch |e| scenarioFail("validate (after reset)", e);
            defer gpa.free(again.output);
            std.debug.print("[5] validation after reset: {s} ({s})\n", .{ if (again.passed) "PASSED (the reset did not restore the problem!)" else "failed, as it should", trimOut(again.output) });
            s.end() catch |e| scenarioFail("end", e);
            const ok = !before.passed and after.passed and !again.passed;
            std.debug.print("\nVERIFY {s}: {s}\n", .{ if (ok) "PASSED" else "FAILED", lab.id });
            if (!ok) std.process.exit(1);
        },
    }
}

/// The Windows guest's last boot time as text, or null if it cannot be asked right now. Caller frees.
fn bootTime(gpa: std.mem.Allocator, prov: winlab.vm_provider.Provider, t: winlab.vm_provider.Target) ?[]u8 {
    const r = prov.runInGuest(gpa, t, "(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.Ticks") catch return null;
    defer gpa.free(r.output);
    const text = trimOut(r.output);
    if (r.exit_code != 0 or text.len == 0) return null;
    for (text) |c| if (!std.ascii.isDigit(c)) return null;
    return gpa.dupe(u8, text) catch null;
}

/// Waits up to five minutes for the guest to answer with a boot time other than `old`; exits if it never does.
fn waitForNewBoot(io: std.Io, gpa: std.mem.Allocator, prov: winlab.vm_provider.Provider, t: winlab.vm_provider.Target, old: []const u8) void {
    var tries: u32 = 0;
    while (tries < 60) : (tries += 1) {
        std.Io.sleep(io, .fromSeconds(5), .real) catch {};
        const now = bootTime(gpa, prov, t) orelse continue;
        defer gpa.free(now);
        if (!std.mem.eql(u8, now, old)) return;
    }
    std.debug.print("solution failed: the guest did not restart within five minutes\n", .{});
    std.process.exit(1);
}

/// `winlab lab selftest <lab.toml> <vm-id>`: runs a lab end to end on a registered training VM
/// with its authoring `solution`, proving the fault is injected, the fix passes validation and
/// the snapshot rollback completes. This is an explicit action; it starts and stops the VM.
fn labSelfTest(init: std.process.Init, lab_path: []const u8, vm_id: []const u8) !void {
    const gpa = init.gpa;
    const io = init.io;
    var cfg = loadSettings(init);
    defer cfg.deinit();

    const text = std.Io.Dir.cwd().readFileAlloc(io, lab_path, gpa, .limited(256 * 1024)) catch |err| {
        std.debug.print("{s}: cannot read lab: {t}\n", .{ lab_path, err });
        std.process.exit(1);
    };
    defer gpa.free(text);
    var failure: winlab.lab.Failure = .{};
    var parsed = winlab.lab.parse(gpa, text, &failure) catch |err| {
        std.debug.print("{s}: invalid lab ({t}) {s}: {s}\n", .{ lab_path, err, failure.field, failure.message });
        std.process.exit(1);
    };
    defer parsed.deinit();
    const lab = parsed.lab;

    var reg = try winlab.vm_registry.load(gpa, io, try openAppData(init));
    defer reg.deinit();
    const vm = reg.find(vm_id) orelse {
        std.debug.print("'{s}' is not a registered VM\n", .{vm_id});
        std.process.exit(1);
    };
    var tools = (try winlab.vm_qemu.discover(gpa, io, init.environ_map.get("PATH") orelse "", cfg.settings.qemu_path)) orelse {
        std.debug.print("{s}\n", .{winlab.vm_qemu.install_guidance});
        std.process.exit(1);
    };
    defer tools.deinit();
    const ssh_exe = try winlab.platform.tool(init.arena.allocator(), init.io, init.environ_map, .ssh);
    var q: winlab.vm_qemu.Qemu = .{ .gpa = gpa, .io = io, .tools = &tools, .ssh_exe = ssh_exe };

    std.debug.print(
        \\Lab:    {s} ({s})
        \\Target: {s} ({s})  disk {s}
        \\Changes: {s}
        \\
    , .{ lab.title, lab.id, vm.id, vm.name, vm.disk, lab.expected_changes[0] });

    var runner = winlab.lab.Runner.init(gpa, q.provider(), vm, lab);
    const fail = struct {
        fn at(step: []const u8, err: anyerror) noreturn {
            std.debug.print("FAILED at {s}: {t}\n", .{ step, err });
            std.process.exit(1);
        }
    }.at;

    std.debug.print("[1] prepare: snapshot, then start the VM (waits for guest control)...\n", .{});
    runner.prepare() catch |e| fail("prepare", e);
    std.debug.print("[2] setup\n", .{});
    runner.setup() catch |e| {
        _ = runner.reset();
        fail("setup", e);
    };
    std.debug.print("[3] inject fault\n", .{});
    runner.injectFault() catch |e| {
        _ = runner.reset();
        fail("fault", e);
    };
    const failed_check = runner.validate() catch |e| {
        _ = runner.reset();
        fail("validate (before fix)", e);
    };
    defer gpa.free(failed_check.output);
    std.debug.print("[4] validation before the fix: {s} (output: {s})\n", .{ if (failed_check.passed) "PASSED (unexpected!)" else "failed, as it should", std.mem.trim(u8, failed_check.output, " \r\n") });
    const before_failed = !failed_check.passed;

    if (lab.solution.len > 0) {
        std.debug.print("[5] apply the authoring solution\n", .{});
        const fixed = q.provider().runInGuest(gpa, vm.target(), lab.solution) catch |e| {
            _ = runner.reset();
            fail("solution", e);
        };
        gpa.free(fixed.output);
    }
    const after = runner.validate() catch |e| {
        _ = runner.reset();
        fail("validate (after fix)", e);
    };
    defer gpa.free(after.output);
    std.debug.print("[6] validation after the fix: {s} (output: {s})\n", .{ if (after.passed) "PASSED" else "FAILED", std.mem.trim(u8, after.output, " \r\n") });

    std.debug.print("[7] reset: stop the VM and restore the pre-lab snapshot\n", .{});
    const rep = runner.reset();
    std.debug.print("    restored={}, snapshot removed={}, complete={}{s}{s}\n", .{ rep.restored, rep.snapshot_removed, rep.complete, if (rep.problem.len > 0) ": " else "", rep.problem });
    const ok = before_failed and after.passed and rep.complete;
    std.debug.print("\nSELFTEST {s}\n", .{if (ok) "PASSED" else "FAILED"});
    if (!ok) std.process.exit(1);
}

/// Opens %APPDATA% (where settings, progress and the VM registry live).
fn openAppData(init: std.process.Init) !std.Io.Dir {
    const appdata = winlab.platform.configBase(init.arena.allocator(), init.environ_map) orelse return error.NoAppData;
    std.Io.Dir.cwd().createDirPath(init.io, appdata) catch {};
    return std.Io.Dir.cwd().openDir(init.io, appdata, .{});
}

/// `winlab coverage [exam-id]`: for each certification domain, the lessons and labs tagged as supporting it.
/// Domains with nothing are flagged, so the report doubles as a to-do list for the course.
fn coverageCmd(init: std.process.Init, exam_filter: ?[]const u8) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();
    var cfg = loadSettings(init);
    defer cfg.deinit();
    const root = contentRoot(init, cfg.settings.content_path);
    const course_dir = try std.fs.path.join(arena, &.{ root, "course" });

    var certs_cat = loadCertsNear(gpa, io, course_dir) orelse {
        std.debug.print("no certs/catalog.toml found under {s}\n", .{root});
        std.process.exit(1);
    };
    defer certs_cat.deinit();
    var course = try openCourse(gpa, io, course_dir);
    defer course.root.close(io);
    defer course.catalog.deinit();

    // Labs: id, title and tags.
    const LabInfo = struct { id: []const u8, title: []const u8, tags: []const []const u8 };
    var labs: std.ArrayList(LabInfo) = .empty;
    if (std.Io.Dir.cwd().openDir(io, try std.fs.path.join(arena, &.{ root, "labs" }), .{ .iterate = true })) |d| {
        var dir = d;
        defer dir.close(io);
        var it = dir.iterate();
        while (try it.next(io)) |e| {
            if (e.kind != .file or !std.mem.endsWith(u8, e.name, ".toml")) continue;
            const text = dir.readFileAlloc(io, e.name, arena, .limited(256 * 1024)) catch continue;
            // Parsed into the arena on purpose: the strings must outlive this loop.
            const p = winlab.lab.parse(arena, text, null) catch continue;
            try labs.append(arena, .{ .id = p.lab.id, .title = p.lab.title, .tags = p.lab.certifications });
        }
    } else |_| {}

    var any = false;
    for (certs_cat.exams) |exam| {
        if (exam_filter) |f| if (!std.mem.eql(u8, f, exam.id)) continue;
        any = true;
        std.debug.print("\n{s} ({s} {s})\n  objectives: {s}\n", .{ exam.name, exam.vendor, exam.code, exam.url });
        var covered: usize = 0;
        for (exam.domains) |dom| {
            const tag = try std.fmt.allocPrint(arena, "{s}/{s}", .{ exam.id, dom.id });
            var n_lessons: usize = 0;
            var n_labs: usize = 0;
            for (course.catalog.entries) |entry| {
                for (entry.lesson.certifications) |t| if (std.mem.eql(u8, t, tag)) {
                    n_lessons += 1;
                    break;
                };
            }
            for (labs.items) |l| {
                for (l.tags) |t| if (std.mem.eql(u8, t, tag)) {
                    n_labs += 1;
                    break;
                };
            }
            if (n_lessons + n_labs > 0) covered += 1;
            std.debug.print("  {s}: {d} lesson(s), {d} lab(s){s}\n", .{ dom.title, n_lessons, n_labs, if (n_lessons + n_labs == 0) "   <-- not covered yet" else "" });
            if (exam_filter != null) {
                for (course.catalog.entries) |entry| {
                    for (entry.lesson.certifications) |t| if (std.mem.eql(u8, t, tag)) {
                        std.debug.print("      lesson  {s}\n", .{entry.lesson.id});
                        break;
                    };
                }
                for (labs.items) |l| {
                    for (l.tags) |t| if (std.mem.eql(u8, t, tag)) {
                        std.debug.print("      lab     {s}\n", .{l.id});
                        break;
                    };
                }
            }
        }
        std.debug.print("  -> {d} of {d} domains have material\n", .{ covered, exam.domains.len });
    }
    if (!any) {
        std.debug.print("unknown exam id. Known ids:", .{});
        for (certs_cat.exams) |e| std.debug.print(" {s}", .{e.id});
        std.debug.print("\n", .{});
        std.process.exit(1);
    }
    std.debug.print("\nTags mean \"supports this domain\", not \"passes this exam\". Check each vendor's current objectives.\n", .{});
}

/// Validates the lab files next to the course (`<course-dir>/../labs`): each must parse, ids must be
/// unique, the lesson each one names must exist, and a lab with a symptom (a learner scenario) must have a
/// solution (so `winlab lab verify` can prove it) and at least one hint. Returns the number of problems.
fn checkLabs(gpa: std.mem.Allocator, io: std.Io, course_dir: []const u8, cat: *const winlab.catalog.Catalog, certs_cat: ?*const winlab.certs.Catalog) !usize {
    const labs_path = try std.fs.path.join(gpa, &.{ course_dir, "..", "labs" });
    defer gpa.free(labs_path);
    var dir = std.Io.Dir.cwd().openDir(io, labs_path, .{ .iterate = true }) catch return 0;
    defer dir.close(io);
    var problems: usize = 0;
    var seen: std.ArrayList([]u8) = .empty;
    defer {
        for (seen.items) |s| gpa.free(s);
        seen.deinit(gpa);
    }
    var count: usize = 0;
    var it = dir.iterate();
    while (try it.next(io)) |e| {
        if (e.kind != .file or !std.mem.endsWith(u8, e.name, ".toml")) continue;
        count += 1;
        const text = dir.readFileAlloc(io, e.name, gpa, .limited(256 * 1024)) catch |err| {
            std.debug.print("labs/{s}: cannot read: {t}\n", .{ e.name, err });
            problems += 1;
            continue;
        };
        defer gpa.free(text);
        var failure: winlab.lab.Failure = .{};
        var p = winlab.lab.parse(gpa, text, &failure) catch |err| {
            std.debug.print("labs/{s}: invalid ({t}) {s}: {s}\n", .{ e.name, err, failure.field, failure.message });
            problems += 1;
            continue;
        };
        defer p.deinit();
        const lab = p.lab;
        for (seen.items) |s| if (std.mem.eql(u8, s, lab.id)) {
            std.debug.print("labs/{s}: duplicate lab id {s}\n", .{ e.name, lab.id });
            problems += 1;
        };
        try seen.append(gpa, try gpa.dupe(u8, lab.id));
        if (lab.lesson.len > 0) {
            var found = false;
            for (cat.entries) |entry| {
                if (std.mem.eql(u8, entry.lesson.id, lab.lesson)) found = true;
            }
            if (!found) {
                std.debug.print("labs/{s}: lesson '{s}' does not exist\n", .{ e.name, lab.lesson });
                problems += 1;
            }
        }
        if (lab.symptom.len > 0 and lab.solution.len == 0) {
            std.debug.print("labs/{s}: a scenario needs a `solution` so it can be verified\n", .{e.name});
            problems += 1;
        }
        for (lab.certifications) |tag| {
            const ok = if (certs_cat) |c| c.resolve(tag) != null else false;
            if (!ok) {
                std.debug.print("labs/{s}: certification tag '{s}' is not in certs/catalog.toml\n", .{ e.name, tag });
                problems += 1;
            }
        }
        if (lab.symptom.len > 0 and lab.hints.len == 0) {
            std.debug.print("labs/{s}: a scenario needs at least one hint\n", .{e.name});
            problems += 1;
        }
    }
    std.debug.print("{d} lab(s), {d} problem(s)\n", .{ count, problems });
    return problems;
}

/// Validates `<root>/quizzes/*.toml`: each parses, is named for its lesson, the lesson exists, every
/// certification tag exists, and every `review` hint names text that is really in the lesson.
fn checkQuizzes(gpa: std.mem.Allocator, io: std.Io, course_dir: []const u8, root: std.Io.Dir, cat: *const winlab.catalog.Catalog, certs_cat: ?*const winlab.certs.Catalog) !usize {
    const quiz_path = try std.fs.path.join(gpa, &.{ course_dir, "..", "quizzes" });
    defer gpa.free(quiz_path);
    var dir = std.Io.Dir.cwd().openDir(io, quiz_path, .{ .iterate = true }) catch return 0;
    defer dir.close(io);
    var problems: usize = 0;
    var files: usize = 0;
    var questions: usize = 0;
    var it = dir.iterate();
    while (try it.next(io)) |e| {
        if (e.kind != .file or !std.mem.endsWith(u8, e.name, ".toml")) continue;
        files += 1;
        const text = dir.readFileAlloc(io, e.name, gpa, .limited(1024 * 1024)) catch |err| {
            std.debug.print("quizzes/{s}: cannot read: {t}\n", .{ e.name, err });
            problems += 1;
            continue;
        };
        defer gpa.free(text);
        var failure: winlab.quiz.Failure = .{};
        var q = winlab.quiz.parse(gpa, text, &failure) catch |err| {
            std.debug.print("quizzes/{s}: invalid ({t}) question {d} {s}: {s}\n", .{ e.name, err, failure.question, failure.key, failure.message });
            problems += 1;
            continue;
        };
        defer q.deinit();
        questions += q.questions.len;
        const expect_name = try std.fmt.allocPrint(gpa, "{s}.toml", .{q.lesson});
        defer gpa.free(expect_name);
        if (!std.mem.eql(u8, expect_name, e.name)) {
            std.debug.print("quizzes/{s}: file must be named {s} after its lesson\n", .{ e.name, expect_name });
            problems += 1;
        }
        var lesson_text: ?[]u8 = null;
        defer if (lesson_text) |t| gpa.free(t);
        for (cat.entries) |entry| {
            if (!std.mem.eql(u8, entry.lesson.id, q.lesson)) continue;
            const content_path = try cat.contentPath(gpa, entry);
            defer gpa.free(content_path);
            lesson_text = root.readFileAlloc(io, content_path, gpa, .limited(max_lesson_bytes)) catch null;
        }
        if (lesson_text == null) {
            std.debug.print("quizzes/{s}: lesson '{s}' does not exist or cannot be read\n", .{ e.name, q.lesson });
            problems += 1;
        }
        for (q.questions) |qq| {
            for (qq.certifications) |tag| {
                const ok = if (certs_cat) |c| c.resolve(tag) != null else false;
                if (!ok) {
                    std.debug.print("quizzes/{s}: question {s}: certification tag '{s}' is not in certs/catalog.toml\n", .{ e.name, qq.id, tag });
                    problems += 1;
                }
            }
            if (qq.review.len > 0 and lesson_text != null and std.ascii.findIgnoreCase(lesson_text.?, qq.review) == null) {
                std.debug.print("quizzes/{s}: question {s}: review '{s}' does not appear in the lesson\n", .{ e.name, qq.id, qq.review });
                problems += 1;
            }
        }
    }
    std.debug.print("{d} quiz file(s), {d} question(s), {d} problem(s)\n", .{ files, questions, problems });
    return problems;
}

/// Loads `<root>/quizzes/*.toml` for the window. Bad files are skipped with a warning; `winlab check` is
/// where they are reported properly. Everything is allocated from `arena`.
fn openQuizzes(arena: std.mem.Allocator, io: std.Io, root: []const u8) []winlab.quiz.Quiz {
    const path = std.fs.path.join(arena, &.{ root, "quizzes" }) catch return &.{};
    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return &.{};
    defer dir.close(io);
    var list: std.ArrayList(winlab.quiz.Quiz) = .empty;
    var it = dir.iterate();
    while (it.next(io) catch null) |e| {
        if (e.kind != .file or !std.mem.endsWith(u8, e.name, ".toml")) continue;
        const text = dir.readFileAlloc(io, e.name, arena, .limited(1024 * 1024)) catch continue;
        var failure: winlab.quiz.Failure = .{};
        const q = winlab.quiz.parse(arena, text, &failure) catch {
            std.debug.print("warning: quizzes/{s}: invalid ({s}: {s}); skipped\n", .{ e.name, failure.key, failure.message });
            continue;
        };
        list.append(arena, q) catch continue;
    }
    return list.items;
}

/// Ids of the labs in `<root>/labs/*.toml`. Unreadable or invalid files are left out (check reports them).
fn labIds(arena: std.mem.Allocator, io: std.Io, root: []const u8) []const []const u8 {
    const path = std.fs.path.join(arena, &.{ root, "labs" }) catch return &.{};
    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return &.{};
    defer dir.close(io);
    var ids: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (it.next(io) catch null) |e| {
        if (e.kind != .file or !std.mem.endsWith(u8, e.name, ".toml")) continue;
        const text = dir.readFileAlloc(io, e.name, arena, .limited(256 * 1024)) catch continue;
        const p = winlab.lab.parse(arena, text, null) catch continue;
        ids.append(arena, p.lab.id) catch continue;
    }
    return ids.items;
}

/// Learning paths from `<root>/paths`. A missing folder gives an empty set.
fn openPaths(gpa: std.mem.Allocator, io: std.Io, root: []const u8) !winlab.paths.Set {
    const dir_path = try std.fs.path.join(gpa, &.{ root, "paths" });
    defer gpa.free(dir_path);
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch {
        var arena = std.heap.ArenaAllocator.init(gpa);
        const none = try arena.allocator().alloc(winlab.paths.Path, 0);
        _ = none;
        return .{ .gpa = gpa, .paths = try gpa.alloc(winlab.paths.Path, 0), .problems = &.{}, .arena = arena };
    };
    defer dir.close(io);
    return winlab.paths.loadDir(gpa, io, dir);
}

/// Index of the lesson `id` in `cat.entries` (the same order as the GUI pages), or null.
fn entryIndex(cat: *const winlab.catalog.Catalog, id: []const u8) ?usize {
    for (cat.entries, 0..) |e, i| if (std.mem.eql(u8, e.lesson.id, id)) return i;
    return null;
}

/// Converts loaded paths for the window. Lessons are page indices; a lesson never appears twice on a path
/// (an optional lesson already listed as required, or earlier, is dropped).
fn pathViews(arena: std.mem.Allocator, set: *const winlab.paths.Set, cat: *const winlab.catalog.Catalog) ![]const gui.PathView {
    const views = try arena.alloc(gui.PathView, set.paths.len);
    for (set.paths, views) |*p, *v| {
        var seen: std.ArrayList(usize) = .empty;
        const stages = try arena.alloc(gui.PathStage, p.stages.len);
        // Required lessons first, so an optional repeat in an earlier stage never hides a required one.
        for (p.stages) |st| for (st.lessons) |id| if (entryIndex(cat, id)) |i| try seen.append(arena, i);
        var listed: std.ArrayList(usize) = .empty;
        for (p.stages, stages) |st, *out| {
            var req: std.ArrayList(usize) = .empty;
            for (st.lessons) |id| {
                const i = entryIndex(cat, id) orelse continue;
                try req.append(arena, i);
                try listed.append(arena, i);
            }
            var opt: std.ArrayList(usize) = .empty;
            for (st.optional) |id| {
                const i = entryIndex(cat, id) orelse continue;
                if (std.mem.indexOfScalar(usize, seen.items, i) != null or std.mem.indexOfScalar(usize, listed.items, i) != null) continue;
                try opt.append(arena, i);
                try listed.append(arena, i);
            }
            out.* = .{ .title = st.title, .entry_hint = st.entry_hint, .pages = req.items, .optional = opt.items, .labs = st.labs };
        }
        const s = winlab.paths.summarize(p, cat);
        v.* = .{ .id = p.id, .title = p.title, .goal = p.goal, .audience = p.audience, .stages = stages, .minutes = s.minutes, .level_min = s.level_min, .level_max = s.level_max };
    }
    return views;
}

/// Validates `<root>/paths/*.toml` against the course: every lesson and lab exists, nothing repeats, tags
/// exist. A lesson that recommends something not earlier on its path is a warning, not a failure.
fn checkPaths(gpa: std.mem.Allocator, io: std.Io, course_dir: []const u8, cat: *const winlab.catalog.Catalog, certs_cat: ?*const winlab.certs.Catalog) !usize {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const root = rootOfCourse(course_dir);
    var set = try openPaths(gpa, io, root);
    defer set.deinit();
    var problems: usize = 0;
    for (set.problems) |p| {
        std.debug.print("paths/{s}\n", .{p});
        problems += 1;
    }
    const labs = labIds(arena, io, root);
    var warnings: usize = 0;
    for (set.paths) |*p| {
        var findings: std.ArrayList(winlab.paths.Finding) = .empty;
        try winlab.paths.validate(arena, p, cat, labs, &findings);
        for (findings.items) |f| switch (f.severity) {
            .problem => {
                std.debug.print("paths/{s}.toml: {s}\n", .{ f.path_id, f.message });
                problems += 1;
            },
            .warning => {
                std.debug.print("paths/{s}.toml: warning: {s}\n", .{ f.path_id, f.message });
                warnings += 1;
            },
        };
        for (p.certifications) |tag| {
            const ok = if (certs_cat) |c| c.resolve(tag) != null else false;
            if (!ok) {
                std.debug.print("paths/{s}.toml: certification tag '{s}' is not in certs/catalog.toml\n", .{ p.id, tag });
                problems += 1;
            }
        }
    }
    std.debug.print("{d} path(s), {d} problem(s), {d} warning(s)\n", .{ set.paths.len, problems, warnings });
    return problems;
}

/// `winlab paths`: the learning paths, with size and level range.
fn pathsCmd(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();
    var cfg = loadSettings(init);
    defer cfg.deinit();
    const root = contentRoot(init, cfg.settings.content_path);
    const course_dir = try std.fs.path.join(arena, &.{ root, "course" });
    var course = try openCourse(gpa, io, course_dir);
    defer course.root.close(io);
    defer course.catalog.deinit();
    var set = try openPaths(gpa, io, root);
    defer set.deinit();
    if (set.paths.len == 0) {
        std.debug.print("no learning paths found under {s}\\paths\n", .{root});
        return;
    }
    for (set.paths) |*p| {
        const s = winlab.paths.summarize(p, &course.catalog);
        std.debug.print("{s}\n  {s}\n  {d} lessons, about {d}.{d} h, level {d}-{d}, {d} stage(s)\n", .{ p.id, p.title, s.lessons, s.minutes / 60, (s.minutes % 60) * 10 / 60, s.level_min, s.level_max, p.stages.len });
    }
}

fn check(gpa: std.mem.Allocator, io: std.Io, dir: []const u8) !void {
    var course = try openCourse(gpa, io, dir);
    defer course.root.close(io);
    defer course.catalog.deinit();
    const cat = &course.catalog;
    for (cat.problems) |p| std.debug.print("{s}: {s}\n", .{ p.where, p.message });
    std.debug.print("{d} lesson(s), {d} problem(s)\n", .{ cat.entries.len, cat.problems.len });

    // Certification tags must name an exam and domain that exist in certs/catalog.toml (if there is one).
    var cert_problems: usize = 0;
    var certs_cat = loadCertsNear(gpa, io, dir);
    defer if (certs_cat) |*c| c.deinit();
    for (cat.entries) |entry| {
        for (entry.lesson.certifications) |tag| {
            const ok = if (certs_cat) |*c| c.resolve(tag) != null else false;
            if (!ok) {
                std.debug.print("{s}: certification tag '{s}' is not in certs/catalog.toml\n", .{ entry.lesson.id, tag });
                cert_problems += 1;
            }
        }
    }
    const lab_problems = try checkLabs(gpa, io, dir, cat, if (certs_cat) |*c| c else null);
    const quiz_problems = try checkQuizzes(gpa, io, dir, course.root, cat, if (certs_cat) |*c| c else null);
    const path_problems = try checkPaths(gpa, io, dir, cat, if (certs_cat) |*c| c else null);
    // Every diagram a lesson names must load, be inside the supported subset and have its text version.
    var diagram_problems: usize = 0;
    var diagram_count: usize = 0;
    for (cat.entries) |entry| {
        var lesson_arena = std.heap.ArenaAllocator.init(gpa);
        defer lesson_arena.deinit();
        const a = lesson_arena.allocator();
        const body = course.root.readFileAlloc(io, try cat.contentPath(a, entry), a, .limited(max_lesson_bytes)) catch continue; // already reported
        const doc = try winlab.md.Document.parse(a, body, .{ .extensions = winlab.md.Extensions.gfm });
        const drawings = try loadDrawings(a, io, course.root, entry.dir, doc.root, &diagram_problems);
        diagram_count += drawings.len;
    }
    std.debug.print("{d} diagram(s), {d} problem(s)\n", .{ diagram_count, diagram_problems });
    if (cat.problems.len != 0 or lab_problems != 0 or cert_problems != 0 or quiz_problems != 0 or path_problems != 0 or diagram_problems != 0) std.process.exit(1);
}

/// certs/catalog.toml next to the course folder, or null if absent or unreadable.
fn loadCertsNear(gpa: std.mem.Allocator, io: std.Io, course_dir: []const u8) ?winlab.certs.Catalog {
    const path = std.fs.path.join(gpa, &.{ course_dir, "..", "certs", "catalog.toml" }) catch return null;
    defer gpa.free(path);
    const text = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024)) catch return null;
    defer gpa.free(text);
    return winlab.certs.parse(gpa, text) catch |err| {
        std.debug.print("{s}: invalid certification catalog: {t}\n", .{ path, err });
        return null;
    };
}

/// Settings from %APPDATA%\WinLab\settings.toml. Never fails: a missing file gives
/// defaults; an unreadable or invalid file is reported and defaults are used for
/// this run. The file is never rewritten here, so a hand-edited file is not lost.
fn loadSettings(init: std.process.Init) winlab.settings.Loaded {
    const defaults = winlab.settings.parse(init.gpa, "", null) catch @panic("out of memory");
    const appdata = winlab.platform.configBase(init.arena.allocator(), init.environ_map) orelse return defaults;
    var base = std.Io.Dir.cwd().openDir(init.io, appdata, .{}) catch |err| {
        if (err == error.FileNotFound) return defaults; // first run: nothing saved yet
        std.debug.print("warning: cannot open {s}: {t}; using default settings\n", .{ appdata, err });
        return defaults;
    };
    defer base.close(init.io);
    const loaded = winlab.settings_file.load(init.gpa, init.io, base) catch |err| {
        std.debug.print("warning: {s}{c}{s}{c}{s}: {t}; using default settings for this run\n", .{ appdata, winlab.platform.dir_sep, winlab.settings_file.sub_dir, winlab.platform.dir_sep, winlab.settings_file.file_name, err });
        return defaults;
    };
    var d = defaults;
    d.deinit();
    for (loaded.ignored) |key| std.debug.print("warning: settings key '{s}' is invalid and was ignored\n", .{key});
    return loaded;
}

/// True if `<root>/course` can be opened as a directory.
fn hasCourse(arena: std.mem.Allocator, io: std.Io, root: []const u8) bool {
    const p = std.fs.path.join(arena, &.{ root, "course" }) catch return false;
    var d = std.Io.Dir.cwd().openDir(io, p, .{}) catch return false;
    d.close(io);
    return true;
}

/// True when `root` is a source checkout: it has `course/` and `build.zig`.
fn isSourceTree(arena: std.mem.Allocator, io: std.Io, root: []const u8) bool {
    if (!hasCourse(arena, io, root)) return false;
    const p = std.fs.path.join(arena, &.{ root, "build.zig" }) catch return false;
    var f = std.Io.Dir.cwd().openFile(io, p, .{}) catch return false;
    f.close(io);
    return true;
}

/// The folder that holds `course/`, `labs/`, `certs/`, `quizzes/` and `images/`. First match wins:
///   1. the source tree around the exe (`zig-out\bin\winlab.exe` -> `..\..` when it holds `build.zig`
///      and `course/`), so a development build never picks up an installed copy
///   2. `content-path` in settings.toml (an explicit choice)
///   3. the folder of winlab.exe (an installed copy that ships its content beside it)
///   4. Linux: `<exe folder>/../share/winlab`, `/usr/share/winlab`, `/usr/local/share/winlab`
///   5. the settings folder (`%APPDATA%\WinLab`, `~/.config/WinLab`)
///   6. the working directory
/// When nothing has a `course/`, the working directory is returned so later errors name a real path.
fn contentRoot(init: std.process.Init, content_path: []const u8) []const u8 {
    const arena = init.arena.allocator();
    const io = init.io;
    const exe_dir: ?[]const u8 = std.process.executableDirPathAlloc(io, arena) catch null;
    if (exe_dir) |dir| {
        if (std.fs.path.join(arena, &.{ dir, "..", ".." })) |up| {
            if (isSourceTree(arena, io, up)) return up;
        } else |_| {}
    }
    if (content_path.len > 0) return content_path;
    if (exe_dir) |dir| {
        if (hasCourse(arena, io, dir)) return dir;
    }
    if (!winlab.platform.is_windows) {
        // A packaged install: <prefix>/bin/winlab with the content in <prefix>/share/winlab, or the usual prefixes.
        if (exe_dir) |dir| {
            if (std.fs.path.join(arena, &.{ dir, "..", "share", "winlab" })) |share| {
                if (hasCourse(arena, io, share)) return share;
            } else |_| {}
        }
        for ([_][]const u8{ "/usr/share/winlab", "/usr/local/share/winlab" }) |share| {
            if (hasCourse(arena, io, share)) return share;
        }
    }
    if (winlab.platform.configBase(init.arena.allocator(), init.environ_map)) |appdata| {
        if (std.fs.path.join(arena, &.{ appdata, winlab.settings_file.sub_dir })) |dir| {
            if (hasCourse(arena, io, dir)) return dir;
        } else |_| {}
    }
    return ".";
}

/// Where the course lives when none is given on the command line.
fn defaultCourseDir(init: std.process.Init, content_path: []const u8) ![]const u8 {
    return std.fs.path.join(init.arena.allocator(), &.{ contentRoot(init, content_path), "course" });
}

/// The content root that goes with a course folder: its parent (`winlab browse D:\x\course` -> `D:\x`).
fn rootOfCourse(course_dir: []const u8) []const u8 {
    return std.fs.path.dirname(course_dir) orelse ".";
}
