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

    // Test apparatus (#324), generation-gated the way `-Dtest-seq-gap` is below:
    // `-Dtest-trace-cap` ADDITIONALLY builds `sideeye-testtracecap`, an engine whose
    // trace-read ceiling is a few bytes instead of 64 MiB. The shipped cap cannot be
    // reached by any fixture — the engine unlinks the trace before every run, so none
    // can be planted, and the only writer is the shim — so without these artifacts the
    // refusal is unreachable in acceptance, and no unit test can stand in: the check
    // lives in main.zig, whose refusals exit the process. The shipped engine's value is
    // a literal below, not this flag's default, so no invocation of this build can lower
    // the cap of a released binary.
    const test_trace_cap = b.option(bool, "test-trace-cap", "also build sideeye-testtracecap, an engine with a tiny trace-read cap used only by acceptance (#324)") orelse false;

    // `-Dtest-ancestor-probe` ADDITIONALLY builds `sideeye-ancprobe`, an engine whose
    // denied-tree list carries one synthetic entry under /tmp. That makes the entry's
    // parent an ancestor deep enough to pass the depth rule, which is the only shape
    // #358's outward read refuses and nothing else does — and unlike the real ancestor
    // (`/private/var`, root-owned and macOS-only) acceptance can create it and delete
    // into it with no privilege.
    //
    // CI greps the binaries rather than comparing their shas. The mutation that motivates
    // it is **an edit to the shipped literal below**, not a flipped default here — the
    // default cannot reach a shipped build, exactly as the trace cap's cannot, and this
    // comment claimed otherwise until review measured both: flipping this `orelse` leaves
    // the shipped binary clean, editing `engineOptions(b, 0, 0, false)` puts the entry in
    // it. A sha comparison is blind to that edit because it lands in both arms; a grep
    // of the shipped artifact is not.
    const test_ancestor_probe = b.option(bool, "test-ancestor-probe", "also build sideeye-ancprobe, an engine with a synthetic denied entry under /tmp used only by acceptance (#358)") orelse false;

    // Every options module handed to a build of src/main.zig must carry the same field
    // set — engine.zig and main.zig read them unconditionally, so a module missing one
    // fails to compile that variant and only that variant. Adding `ancestor_probe` to
    // three of the four modules by hand broke `-Dtest-trace-cap` while `zig build`,
    // `zig build test` and the new option all stayed green; the sibling variant was not
    // in the measurement. Built here instead, a module cannot be short a field.
    const engineOptions = struct {
        fn make(bld: *std.Build, trace_cap: usize, trace_cap_world: usize, ancestor_probe: bool) *std.Build.Step.Options {
            const o = bld.addOptions();
            o.addOption(usize, "trace_cap_override", trace_cap);
            o.addOption(usize, "trace_cap_override_world", trace_cap_world);
            o.addOption(bool, "ancestor_probe", ancestor_probe);
            return o;
        }
    }.make;

    // The shipped values. Each is a literal here, not a flag's default, so no invocation
    // of any build option below can change what a released binary carries.
    const exe_opts = engineOptions(b, 0, 0, false);
    const exe = b.addExecutable(.{
        .name = "sideeye",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            // The engine talks to the operating system through libc directly rather
            // than through std.Io — see src/posix.zig for why.
            .link_libc = true,
            .imports = &.{
                .{ .name = "contract", .module = contract },
                .{ .name = "engine_build_options", .module = exe_opts.createModule() },
            },
        }),
    });
    // `sideeye demo` carries its own target: the planted-bug toy and its checker are
    // embedded at compile time and materialized on the visitor's machine. These are the
    // same files the acceptance suite drives, so the demo cannot drift from what CI
    // proves — and both are listed in build.zig.zon's `.paths`, or a fetched package
    // would fail to build.
    exe.root_module.addAnonymousImport("toy_c", .{ .root_source_file = b.path("spike/toys/toy.c") });
    exe.root_module.addAnonymousImport("check_sh", .{ .root_source_file = b.path("spike/check.sh") });
    b.installArtifact(exe);

    if (test_ancestor_probe) {
        const probe_opts = engineOptions(b, 0, 0, true);
        const exe_probe = b.addExecutable(.{
            .name = "sideeye-ancprobe",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .imports = &.{
                    .{ .name = "contract", .module = contract },
                    .{ .name = "engine_build_options", .module = probe_opts.createModule() },
                },
            }),
        });
        exe_probe.root_module.addAnonymousImport("toy_c", .{ .root_source_file = b.path("spike/toys/toy.c") });
        exe_probe.root_module.addAnonymousImport("check_sh", .{ .root_source_file = b.path("spike/check.sh") });
        b.installArtifact(exe_probe);
    }

    if (test_trace_cap) {
        // 64 bytes: over the trace header, under any real recording, so the cap breaks
        // on an ordinary toy run instead of needing a million operations.
        // Two artifacts, because the two read sites cannot both fire in one run: the
        // recording read happens first and exits, so a binary that caps both can only
        // ever demonstrate the first branch. The second caps the world read alone,
        // leaving the recording read at the shipped ceiling.
        const cap_opts = engineOptions(b, 64, 0, false);
        const exe_cap = b.addExecutable(.{
            .name = "sideeye-testtracecap",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .imports = &.{
                    .{ .name = "contract", .module = contract },
                    .{ .name = "engine_build_options", .module = cap_opts.createModule() },
                },
            }),
        });
        exe_cap.root_module.addAnonymousImport("toy_c", .{ .root_source_file = b.path("spike/toys/toy.c") });
        exe_cap.root_module.addAnonymousImport("check_sh", .{ .root_source_file = b.path("spike/check.sh") });
        b.installArtifact(exe_cap);

        const world_opts = engineOptions(b, 0, 64, false);
        const exe_cap_world = b.addExecutable(.{
            .name = "sideeye-testtracecap-world",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .imports = &.{
                    .{ .name = "contract", .module = contract },
                    .{ .name = "engine_build_options", .module = world_opts.createModule() },
                },
            }),
        });
        exe_cap_world.root_module.addAnonymousImport("toy_c", .{ .root_source_file = b.path("spike/toys/toy.c") });
        exe_cap_world.root_module.addAnonymousImport("check_sh", .{ .root_source_file = b.path("spike/check.sh") });
        b.installArtifact(exe_cap_world);
    }

    // The shim is only built for targets whose interposition mechanism exists.
    // v0.1 covers Linux (LD_PRELOAD); macOS (DYLD_INSERT_LIBRARIES + __DATA,__interpose)
    // arrives after the Linux ground is proven, so building for macOS today would
    // install a library that cannot do its job. Say so instead of shipping it.
    // Both platforms now have an interposition mechanism: LD_PRELOAD on Linux,
    // DYLD_INSERT_LIBRARIES with a __DATA,__interpose table on macOS.
    // Test apparatus (#270), generation-gated: `-Dtest-seq-gap` ADDITIONALLY builds
    // libsideeye_shim_testgap, a shim whose numbering skips one — the one shape the
    // sequence_numbering_broken refusal exists for. The shipped libsideeye_shim is
    // hardcoded false below and never reads this flag, so its bytes cannot depend on
    // it (acceptance asserts that by checksum). Gating GENERATION rather than
    // installation is what keeps the variant out of releases: brew builds from
    // source with plain `zig build`, where the variant does not exist at all.
    const test_seq_gap = b.option(bool, "test-seq-gap", "also build libsideeye_shim_testgap, a numbering-gap shim used only by acceptance (#270)") orelse false;

    if (target.result.os.tag == .linux or target.result.os.tag == .macos) {
        // One options module per artifact, each with a literal value: the shipped
        // shim's `false` is not the flag's default but a constant, so no invocation
        // of this build can produce a shipped shim that skips numbers.
        const shim_opts = b.addOptions();
        shim_opts.addOption(bool, "test_seq_gap", false);
        const shim = b.addLibrary(.{
            .name = "sideeye_shim",
            .linkage = .dynamic,
            // The vfork wrapper is a guaranteed tail call (`@call(.always_tail)`), which
            // Zig's self-hosted x86_64 backend — the default for Debug builds — refuses:
            // "does not support tail calls on target architecture 'x86_64'". The guarantee
            // is the point (an ordinary call there corrupts the target's stack, see
            // shim/src/ops.zig), so the shim pins the backend that can honour it.
            .use_llvm = true,
            .root_module = b.createModule(.{
                .root_source_file = b.path("shim/src/shim.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .imports = &.{
                    .{ .name = "contract", .module = contract },
                    .{ .name = "shim_build_options", .module = shim_opts.createModule() },
                },
            }),
        });
        // Mach-O only, and it is packaging rather than function: sideeye locates
        // the shim by real path and injects that path with
        // DYLD_INSERT_LIBRARIES, so its own lookup does not depend on the
        // dylib's install name. Package managers do rewrite it. Homebrew
        // rewrote this one to an absolute path under its prefix, and without
        // padding in the Mach-O header the longer name does not fit: `brew
        // install` reported "Failed to fix install linkage" and exited 1 on a
        // build that otherwise ran. Measured against v0.12.0's released dylib,
        // whose ID is `@rpath/libsideeye_shim.dylib` and cannot be lengthened.
        if (target.result.os.tag == .macos) shim.headerpad_max_install_names = true;
        b.installArtifact(shim);

        if (test_seq_gap) {
            const gap_opts = b.addOptions();
            gap_opts.addOption(bool, "test_seq_gap", true);
            const shim_gap = b.addLibrary(.{
                .name = "sideeye_shim_testgap",
                .linkage = .dynamic,
                .use_llvm = true,
                .root_module = b.createModule(.{
                    .root_source_file = b.path("shim/src/shim.zig"),
                    .target = target,
                    .optimize = optimize,
                    .link_libc = true,
                    .imports = &.{
                        .{ .name = "contract", .module = contract },
                        .{ .name = "shim_build_options", .module = gap_opts.createModule() },
                    },
                }),
            });
            if (target.result.os.tag == .macos) shim_gap.headerpad_max_install_names = true;
            b.installArtifact(shim_gap);
        }
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
        "src/config.zig",
        "src/mcp.zig",
        // The shim's own logic. It had no unit tests at all, which is backwards: it is
        // the half that runs inside somebody else's process, and every defect found in
        // it so far produced a plausible value rather than an error.
        "shim/src/common.zig",
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
                .imports = &.{
                    .{ .name = "contract", .module = contract },
                    // engine.zig reads this for the ancestor-probe entry (#358), so the
                    // test build of engine.zig has to resolve it too. Always the shipped
                    // values: the unit tests assert what a released binary does, and a
                    // probe entry visible to them would make the denied lists they check
                    // differ from the ones users get.
                    .{ .name = "engine_build_options", .module = exe_opts.createModule() },
                },
            }),
        });
        // The package manifest, so a test can hold the version it declares against the
        // one the binary prints. They are two hand-written strings for one number.
        t.root_module.addAnonymousImport("build_zon", .{ .root_source_file = b.path("build.zig.zon") });
        // The demo's embedded assets: main.zig references them at module scope, so the
        // test build of main.zig must resolve them too.
        t.root_module.addAnonymousImport("toy_c", .{ .root_source_file = b.path("spike/toys/toy.c") });
        t.root_module.addAnonymousImport("check_sh", .{ .root_source_file = b.path("spike/check.sh") });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    const run_step = b.step("run", "Run sideeye");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);
}
