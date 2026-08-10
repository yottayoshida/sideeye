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
            // The engine talks to the operating system through libc directly rather
            // than through std.Io — see src/posix.zig for why.
            .link_libc = true,
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

    // Each file that carries tests is named explicitly.
    //
    // Testing through the executable's root module alone is not enough: Zig analyses
    // declarations reachable from the root, and a `test` block in an imported file is
    // not reachable that way. Doing that silently ran 19 tests while five more sat
    // uncollected — green, and measuring less than it appeared to.
    const test_sources = [_][]const u8{
        "src/engine.zig",
        "src/posix.zig",
        "src/oracle.zig",
        "src/main.zig",
    };

    const contract_tests = b.addTest(.{ .root_module = contract });
    test_step.dependOn(&b.addRunArtifact(contract_tests).step);

    for (test_sources) |src| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(src),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .imports = &.{.{ .name = "contract", .module = contract }},
            }),
        });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    const run_step = b.step("run", "Run sideeye");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);
}
