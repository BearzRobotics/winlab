const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("winlab", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "md", .module = b.dependency("md", .{ .target = target, .optimize = optimize }).module("md") },
            .{ .name = "toml", .module = b.dependency("toml", .{ .target = target, .optimize = optimize }).module("toml") },
            .{ .name = "pdf", .module = b.dependency("pdf", .{ .target = target, .optimize = optimize }).module("pdf") },
        },
    });

    // GUI: DVUI on its Direct3D 11 backend on Windows (ADR 0002); on every other OS the SDL2 backend
    // (system SDL2 with -fsys=sdl2, which is what distro packages should use, or SDL2 built from source).
    const is_windows = target.result.os.tag == .windows;
    const dvui_dep = if (is_windows)
        b.dependency("dvui", .{ .target = target, .optimize = optimize, .backend = .dx11 })
    else
        b.dependency("dvui", .{ .target = target, .optimize = optimize, .backend = .sdl2 });

    const exe = b.addExecutable(.{
        .name = "winlab",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "winlab", .module = mod },
                .{ .name = "dvui", .module = dvui_dep.module(if (is_windows) "dvui_dx11" else "dvui_sdl2") },
                .{ .name = "backend", .module = dvui_dep.module(if (is_windows) "dx11" else "sdl2") },
            },
        }),
    });
    if (is_windows) exe.win32_manifest = dvui_dep.path("src/main.manifest");
    b.installArtifact(exe);

    // A development build reads the source tree (`zig-out/bin/../..`), so nothing is copied beside the exe
    // by default. `-Dbundle-content=true` makes a self-contained folder to hand to someone.
    const bundle_content = b.option(bool, "bundle-content", "Copy course, labs, certs, images and quizzes next to winlab.exe") orelse false;
    if (bundle_content) {
        for ([_][]const u8{ "course", "labs", "certs", "images", "quizzes" }) |dir| {
            b.installDirectory(.{ .source_dir = b.path(dir), .install_dir = .bin, .install_subdir = dir });
        }
    }

    const run_step = b.step("run", "Run WinLab");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const check_step = b.step("check-content", "Validate all lesson manifests under course/");
    const check_cmd = b.addRunArtifact(exe);
    check_cmd.addArgs(&.{ "check", "course" });
    check_step.dependOn(&check_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = mod })).step);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = exe.root_module })).step);
}
