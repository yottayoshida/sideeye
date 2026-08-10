const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The contract both halves agree on. One module, imported by the engine and by
    // the shim, so the trace format cannot drift between writer and reader.
    const contract = b.addModule("contract", .{
        .root_source_file = b.path("src/contract.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "sideeye",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "contract", .module = contract }},
        }),
    });
    b.installArtifact(exe);

    // The shim is only built for targets whose interposition mechanism exists.
    // v0.1 covers Linux (LD_PRELOAD); macOS (DYLD_INSERT_LIBRARIES + __DATA,__interpose)
    // arrives after the Linux ground is proven, so building for macOS today would
    // install a library that cannot do its job. Say so instead of shipping it.
    if (target.result.os.tag == .linux) {
        const shim = b.addLibrary(.{
            .name = "sideeye_shim",
            .linkage = .dynamic,
            .root_module = b.createModule(.{
                .root_source_file = b.path("shim/src/shim.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .imports = &.{.{ .name = "contract", .module = contract }},
            }),
        });
        b.installArtifact(shim);
    }

    const test_step = b.step("test", "Run tests");

    const contract_tests = b.addTest(.{ .root_module = contract });
    test_step.dependOn(&b.addRunArtifact(contract_tests).step);

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);

    const run_step = b.step("run", "Run sideeye");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);
}
