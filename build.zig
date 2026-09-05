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
    // trace-read ceiling is a few bytes instead of 64 MiB. No committed fixture reaches the
    // shipped cap. That used to be stated as "cannot be reached" on the grounds that the
    // engine unlinks the trace before every run and the only writer is the shim; the pair
    // stops being an argument at the SECOND shim'd process, which opens the same name with
    // no unlink in front of it (#488), and a link planted there points the read at a file
    // of any size — until #489 gave the trace read `O_NOFOLLOW` too, which shuts the
    // symlink road. Two roads stay open and neither is closed by a flag: a **hard link**,
    // which `O_NOFOLLOW` does not see, and the target itself, which holds the trace path in
    // its environment and can write the work directory (README says so). So the claim here
    // is still the weak one — no committed fixture aims anything at a large file — rather
    // than the structural one it was before #488.
    // So without these artifacts the
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
    // the shipped binary clean, editing `engineOptions(b, 0, 0, 0, false)` puts the entry in
    // it. A sha comparison is blind to that edit because it lands in both arms; a grep
    // of the shipped artifact is not.
    const test_ancestor_probe = b.option(bool, "test-ancestor-probe", "also build sideeye-ancprobe, an engine with a synthetic denied entry under /tmp used only by acceptance (#358)") orelse false;

    // `-Dtest-trace-budget` ADDITIONALLY builds `sideeye-testtracebudget`, an engine whose
    // WHOLE-TRACE ceiling is a few kilobytes instead of 512 MiB (#377). Unlike the two
    // cap artifacts above there is only one of these, and it does not name a read site:
    // the ceiling is a property of the sum, so what a leg needs is two reads live at once
    // rather than a chosen one of them to break. `preflight --twice` is that shape.
    //
    // No committed fixture reaches the shipped ceiling, for the same reason and with the
    // same correction as the caps above: the unlink-plus-single-writer argument holds only
    // until the second shim'd process (#488), and what keeps the ceiling out of reach is
    // that no fixture aims a planted link at a large file. The shipped value is a literal
    // below rather than this flag's default.
    const test_trace_budget = b.option(bool, "test-trace-budget", "also build sideeye-testtracebudget, an engine with a tiny whole-trace ceiling used only by acceptance (#377)") orelse false;
    // Not an engine variant: a reader for the shim's trace, used by
    // `spike/fsevents/survey.sh`'s L7a to ask what was recorded ABOUT a path rather than
    // whether the path appears at all (#344). Gated the same way for the same reason —
    // it is apparatus, and the tarball has no use for it.
    const trace_ops = b.option(bool, "trace-ops", "also build trace-ops, a reader that prints one <op> <path> line per shim trace record, used only by spike/fsevents (#344)") orelse false;

    // Every options module handed to a build of src/main.zig must carry the same field
    // set — engine.zig and main.zig read them unconditionally, so a module missing one
    // fails to compile that variant and only that variant. Adding `ancestor_probe` to
    // three of the four modules by hand broke `-Dtest-trace-cap` while `zig build`,
    // `zig build test` and the new option all stayed green; the sibling variant was not
    // in the measurement. Built here instead, a module cannot be short a field.
    const engineOptions = struct {
        fn make(bld: *std.Build, trace_cap: usize, trace_cap_world: usize, trace_budget: usize, ancestor_probe: bool) *std.Build.Step.Options {
            const o = bld.addOptions();
            o.addOption(usize, "trace_cap_override", trace_cap);
            o.addOption(usize, "trace_cap_override_world", trace_cap_world);
            o.addOption(usize, "trace_budget_override", trace_budget);
            o.addOption(bool, "ancestor_probe", ancestor_probe);
            return o;
        }
    }.make;

    // The half the unit tests cannot reach (#365). Those tests assert the VALUES inside
    // the shipped options modules; nothing in them says a released artifact is built with
    // one. Pointing an artifact's import at a freshly made options module is a single
    // edit that leaves `zig build test` green and CI's sha comparison green while the
    // shipped binary carries whatever literal that edit chose — the shape #365 filed, one
    // level further out. Measured before this assertion existed: swapping the engine's
    // import for `engineOptions(b, 128 * 1024 * 1024, 0, false).createModule()` passed the
    // whole suite and produced a shipped engine byte-identical to the one an edit to the
    // literal produces.
    //
    // Checked at configure time, so every `zig build` sees it. `import_table` is a public
    // field of std.Build.Module (std/Build/Module.zig:7); a rename there fails the build
    // loudly rather than silently skipping the check.
    const assertBuiltWith = struct {
        fn check(m: *std.Build.Module, name: []const u8, want: *std.Build.Module, artifact: []const u8) void {
            const got = m.import_table.get(name) orelse std.debug.panic(
                "{s} has no `{s}` import: its shipped build values are held by nothing (#365)",
                .{ artifact, name },
            );
            if (got != want) std.debug.panic(
                "{s} is built with a different `{s}` than the one the unit tests assert (#365)",
                .{ artifact, name },
            );
        }
    }.check;

    // The shipped values. Each is a literal here, not a flag's default, so no invocation
    // of any build option below can change what a released binary carries. What that
    // sentence never covered is an edit to the literal itself (#365): the sha comparison
    // in CI puts such an edit in both arms and stays green. The unit tests below assert
    // these values, so the literal is held by a check rather than by the sentence.
    const exe_opts = engineOptions(b, 0, 0, 0, false);

    // ONE module object, handed to both the shipped executable and the unit tests.
    // `createModule` returns a fresh Module on every call, and calling it separately in
    // the two places left them joined by nothing but "the same variable is read twice" —
    // an invariant nothing asserted. Pointing the test's import at a different options
    // module and then editing the literal above is two edits no test could see, which is
    // #365's own shape (a differential check cannot see a change present on both sides)
    // one level up. Sharing the object makes them the same THING rather than the same
    // value, the way `contract` above is already shared by the engine, shim and tests.
    const shipped_engine_opts = exe_opts.createModule();
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
                .{ .name = "engine_build_options", .module = shipped_engine_opts },
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
    assertBuiltWith(exe.root_module, "engine_build_options", shipped_engine_opts, "the shipped engine");
    b.installArtifact(exe);

    if (test_ancestor_probe) {
        const probe_opts = engineOptions(b, 0, 0, 0, true);
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

    if (trace_ops) {
        const exe_trace_ops = b.addExecutable(.{
            .name = "trace-ops",
            .root_module = b.createModule(.{
                .root_source_file = b.path("spike/fsevents/trace-ops.zig"),
                .target = target,
                .optimize = optimize,
                // It reads one file through libc, so it has to say so. macOS links libc
                // by default and Linux does not: this built clean on the machine it was
                // written on and failed on the runner with "dependency on libc must be
                // explicitly specified" — caught by the CI step added in the same change,
                // which is the only place this apparatus is compiled for Linux at all.
                .link_libc = true,
                .imports = &.{
                    .{ .name = "contract", .module = contract },
                },
            }),
        });
        b.installArtifact(exe_trace_ops);
    }

    if (test_trace_cap) {
        // 64 bytes: over the trace header, under any real recording, so the cap breaks
        // on an ordinary toy run instead of needing a million operations.
        // Two artifacts, because the recording and world reads cannot both fire in one
        // run: the recording read happens first and exits, so a binary that caps both
        // can only ever demonstrate the first branch. The second caps the world read
        // alone, leaving the recording read at the shipped ceiling.
        //
        // This said "the two read sites" until #377 counted them and found three. The
        // third — `preflight --twice`'s second observation — shares `trace_cap` with the
        // recording read, so neither artifact can reach it: run A's read fires first.
        const cap_opts = engineOptions(b, 64, 0, 0, false);
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

        const world_opts = engineOptions(b, 0, 64, 0, false);
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

    if (test_trace_budget) {
        // Sized so that ONE toy trace fits and TWO do not, which is the only shape that
        // separates this refusal from `trace_too_large`: every trace involved is well
        // under the per-read cap, and what runs out is the sum. The value is read off a
        // measured toy trace rather than guessed — see BUILDLOG for the run.
        const budget_opts = engineOptions(b, 0, 0, 3 * 1024, false);
        const exe_budget = b.addExecutable(.{
            .name = "sideeye-testtracebudget",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .imports = &.{
                    .{ .name = "contract", .module = contract },
                    .{ .name = "engine_build_options", .module = budget_opts.createModule() },
                },
            }),
        });
        exe_budget.root_module.addAnonymousImport("toy_c", .{ .root_source_file = b.path("spike/toys/toy.c") });
        exe_budget.root_module.addAnonymousImport("check_sh", .{ .root_source_file = b.path("spike/check.sh") });
        b.installArtifact(exe_budget);
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

    // Declared outside the platform branch below because the unit tests import it too and
    // `test_step` lives out here. One options module and one module object, shared by the
    // shipped shim and the tests — the same reason `shipped_engine_opts` above is shared
    // (#365). The shipped `false` is a literal, not the flag's default, so no invocation
    // of this build can produce a shipped shim that skips numbers; the literal itself is
    // held by a test in shim/src/common.zig rather than by this comment.
    const shim_opts = b.addOptions();
    shim_opts.addOption(bool, "test_seq_gap", false);
    const shipped_shim_opts = shim_opts.createModule();

    if (target.result.os.tag == .linux or target.result.os.tag == .macos) {
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
                    .{ .name = "shim_build_options", .module = shipped_shim_opts },
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
        assertBuiltWith(shim.root_module, "shim_build_options", shipped_shim_opts, "the shipped shim");
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

    // Each file that carries tests is named explicitly, and the reason is narrower than
    // this comment used to say.
    //
    // Zig analyses lazily: a `test` block in an imported file is collected only when a
    // test in the root reaches a declaration of that file. It is not "imported files are
    // never collected" — the engine root runs posix.zig's tests, because engine's tests
    // reach posix — and not "always collected" either: mcp.zig imports engine.zig and its
    // root runs none of engine's, because mcp's tests reach nothing in it (measured
    // 2026-09-05 at `b7d1c72`, the tree before the first seam of #491: posix 22,
    // engine 102).
    // The first version of this build measured 19 tests run and five sitting uncollected,
    // green and measuring less than it appeared to — almost certainly this same effect on
    // a posix.zig that main's tests did not reach, though the tree that measured it has
    // no engine.zig to re-run (#491 re-read the per-root counts and found the condition).
    // Naming each file makes collection independent of which test happens to mention
    // what.
    //
    // Files under src/engine/ cannot be named here: as a root, their `../posix.zig`
    // falls outside the module path. engine.zig references them with `refAllDecls`
    // instead: collection is unconditional either way, though a name here also proves the
    // file builds as a root on its own, which the files under src/engine/ cannot.
    const test_sources = [_][]const u8{
        "src/engine.zig",
        "src/posix.zig",
        "src/oracle.zig",
        "src/fsusage.zig",
        "src/main.zig",
        "src/config.zig",
        "src/mcp.zig",
        "src/image.zig",
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
                    // differ from the ones users get. It is the SAME module object the
                    // shipped executable gets (#365), not a second one built from the
                    // same literal — nothing would have held those two together.
                    .{ .name = "engine_build_options", .module = shipped_engine_opts },
                    // The shim's shipped options, for the same reason. shim/src/common.zig
                    // imports this module, and until #365 it was absent here: the import
                    // resolved only because no test reached a declaration that used it.
                    .{ .name = "shim_build_options", .module = shipped_shim_opts },
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
