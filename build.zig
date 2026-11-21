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

    // GUI: DVUI on its Direct3D 11 backend (ADR 0002). Windows-only, like the terminal and the VM tools.
    const dvui_dep = b.dependency("dvui", .{ .target = target, .optimize = optimize, .backend = .dx11 });

    const exe = b.addExecutable(.{
        .name = "winlab",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "winlab", .module = mod },
                .{ .name = "dvui", .module = dvui_dep.module("dvui_dx11") },
                .{ .name = "dx11-backend", .module = dvui_dep.module("dx11") },
            },
        }),
    });
    exe.win32_manifest = dvui_dep.path("src/main.manifest");
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
