# Buildlog

Development journal, newest first. Decisions are recorded when they are made — including the ones that turn out wrong. This file is allowed to be embarrassing in hindsight; that is what it is for.

## 2026-08-10 — The macOS shim builds, runs, and gets the mode argument wrong

The structure is in place: replacement functions live in one file (`ops.zig`) with
identical bodies on both platforms, and only the installation differs — `linux.zig`
exports the symbols for `LD_PRELOAD`, `macos.zig` lists them in a `__DATA,__interpose`
table and fills `common.real` from `extern` declarations. The constructor section
switches between `.init_array` and `__DATA,__mod_init_func`; `fdPath` switches between
`/proc/self/fd` and `fcntl(F_GETPATH)`; the engine switches between `LD_PRELOAD` and
`DYLD_INSERT_LIBRARIES`. It builds, injects, and the target completes.

Then the engine failed to snapshot the state, and the reason turned out to be the whole
point of testing on the second platform.

**Every file created under the shim had mode `----------`.** Not a crash, not an error
return — the files existed, held the right bytes, and were unreadable. `open` is a
variadic function, and on arm64 macOS variadic arguments are passed **on the stack**,
while the fixed-arity declaration used here passes them **in registers**. So the third
argument was read from a register the caller never wrote, and `mode` came out zero.
Both directions are affected: the target's `mode` never reaches the replacement, and
the replacement's `mode` never reaches the real `open`.

The same code is correct on Linux, where variadic arguments do go in registers. This is
the class of defect that only appears when the second platform arrives, and the reason
the plan put macOS inside v0.1 rather than after it. Discovering it in v0.3 would have
meant discovering it on top of a codebase built around the wrong assumption.

The fix is real variadic handling — `@cVaStart` / `@cVaArg` in the replacements, and
variadic function-pointer types for the originals — which touches every `open`-family
entry point. Left for the next pass rather than rushed. Linux is unaffected: the full
acceptance suite is still green with seven distinct detectors.

Also corrected while here: `O_CREAT`, `O_APPEND` and `O_CLOEXEC` had Linux's values
compiled into the shim unconditionally. On Darwin those constants differ, and the
failure mode would have been a trace file opened with the wrong semantics — records
missing rather than a bad flag reported.

## 2026-08-10 — macOS, measured: interposition works, the oracle does not

Two things the plan said would be decided by running them rather than by reading about
them. Both are now decided.

**`__DATA,__interpose` works from Zig.** A minimal library exporting one replacement for
`open` gets it called, and the control run without injection does not. Two details:
`@intFromPtr` cannot be evaluated at comptime for a function address, so the table holds
`@ptrCast` pointers; and calling `open` from inside the replacement does **not** recurse.
Same-image calls are not interposed, which means macOS needs no `dlsym(RTLD_NEXT)` dance
at all — the original is simply callable.

`fcntl(fd, F_GETPATH, buf)` supplies what `/proc/self/fd` supplies on Linux, including
the same symlink resolution (`/etc/hosts` comes back as `/private/etc/hosts`).

**`dtruss` is not usable.** SIP is enabled and DTrace refuses: *"DTrace requires
additional privileges"*. `sudo dtruss` may work, but a tool that demands sudo to reach
its own correctness check is not a tool anyone will run in CI. The alternatives —
Endpoint Security and friends — need an entitlement a freely distributed binary cannot
carry. The plan predicted this and built the structural detectors so they would not
depend on an oracle; that decision is now load-bearing rather than precautionary.

### The consequence, and the shape of the answer

Requiring an oracle for PASS — the fix from the first review — would mean **macOS never
produces a PASS at all**. FAIL would still work, so the tool would report bugs and never
report their absence. That is not a usable half.

Branching on the platform was the obvious repair and the wrong one: the whole point of
acceptance check 3 is that the same scenario yields the same verdict on both operating
systems, and a rule that only applies to one of them destroys the comparison.

`--allow-unverified` instead. The caller states the weaker claim deliberately, and the
report carries it:

```
oracle: NOT VERIFIED (--allow-unverified) — nothing checked what the shim reported
```

Two PASSes are now distinguishable by reading them, which is the property that matters.
FAIL is untouched by the flag — a counterexample sitting in front of you does not become
less real because the account of the run was incomplete — and that is asserted rather
than assumed.

Still to build: the macOS shim itself. The mechanism is proven; what remains is the
symbol table and the `F_GETPATH` path resolution.

## 2026-08-10 — L2: the checker, and the requirement that it be shown to work

The domain checker runs after each crash, in a fresh process, and its exit code is the
verdict. On the buggy toy the report now reads:

```
invariant   built-in atomicity, and the checker
earliest    crash point 5 of 5
            after  unlink(/tmp/l2/state/key.json)
            before rename(/tmp/l2/state/key.json.tmp)
checker     falsified before the run (corrupted state -> check failed)
```

with `doctor says 'healthy' but the key is unloadable` on stderr. That is DESIGN §13's
worked example arriving on its own — the diagnostic contradicting reality, in the world
where the key is briefly absent. Both invariants fail in the same world, which is what
they should do when they are describing the same bug from different angles.

**Falsification runs first, and refuses to proceed without it** (DESIGN §14-13). A
checker that cannot tell a corrupted state from a healthy one will call every world
fine, and a PASS built on that is a statement about nothing. `/bin/true` as a checker
is the purest case and is now an acceptance check: it must produce UNKNOWN.

The way the state gets corrupted for that probe took a correction. Emptying the
directory is the obvious method and it is wrong here: `check.sh` compares a diagnostic
against reality, and an empty state is perfectly *consistent* — the diagnostic says
unhealthy, nothing loads, they agree. The probe overwrites each file's contents instead,
keeping the structure. Breaking the agreement is the point, not removing the subject.

**Configuration is `--check <cmd>`, not `sideeye.toml`.** The plan called for the file;
Zig has no toml parser and hand-writing one does not advance the spike. What L2 actually
has to demonstrate — a fresh process after restart, an exit code as the verdict, and the
falsification gate — is fully exercised through the flag. The three-commands-and-a-
directory contract of DESIGN §12 is a v0.2 concern.

Seven distinct detectors now fire across the acceptance suite.

## 2026-08-10 — First outside review: three ways to reach PASS while blind

An adversarial review of the whole branch found six real defects, three of them capable
of producing PASS on a target that had not been fully observed. That is the specific
failure this project exists to avoid, so they are worth recording individually.

**PASS was reachable without any completeness check.** `--oracle` was optional and its
absence only produced a line in the report. The reviewer pointed out the case the toys
did not cover: a target that performs *one* ordinary libc operation and then bypasses
libc for the rest. Something was mutated, so `state_changed_without_ops` stays quiet;
the trace is short but not empty, so nothing looks wrong. Every toy so far was either
entirely visible or entirely invisible, and the gap between those was invisible too.
`spike/toys/toy_mixed.c` now occupies it. PASS requires an oracle; FAIL does not,
because a counterexample is real whether or not the account of it was complete.

**The oracle could not see a raw `clone`.** It was invoked with
`-e trace=%file,%desc` and no `-f`, so process creation was outside its view — the same
blind spot the shim documents for itself. A child touching the state directory while
the parent performs ordinary operations passed everything. Now `-f` and `%process`,
with the check placed *before* the state-directory filter, since the child's work never
mentions the directory in the parent's account.

**`restore()` could delete outside the state directory.** It asked `isDirPath`, which
calls `opendir` and therefore follows symlinks; a link inside the state directory
pointing anywhere else would have had its target's contents deleted, once per explored
world. `assertSafeRoot` never had a chance — it only inspects the root string.
Deletion now decides from `dirent.type`, which has not followed anything yet.

Three smaller ones: a truncated trace was parsed as far as it went and then judged; an
operation whose path could not be resolved was dropped silently (`unresolvable_path`
existed as a value and was never produced); and the acceptance suite ran without an
oracle, so none of the above was pinned.

### Two regressions the fixes introduced, both found by running them

Fixing the oracle's blind spot broke the oracle twice, and neither showed up as an
error — both produced confident wrong answers.

`strace -f -o file` prefixes lines with `13    `, not `[pid 13]`. Only the bracketed
form was handled, so every line failed to yield a syscall name, the oracle's view came
back empty, and it reported that the *shim* had invented operations. And strace's own
`execve` of the target was counted as the target creating a child process, so every run
returned `child_process_detected` — the measuring apparatus flagging the act of
measuring.

Both were caught by running the acceptance suite, not by reading the diff. The first
one is a good illustration of why: the code looked right, the tests for it passed, and
the format it parsed was one that documentation and memory both agree exists.

### Where this leaves the boundary

`spike/acceptance.sh` is green with **six distinct detectors** firing across the
out-of-bounds cases, up from four. Two of them cover the same target from different
sides on purpose: `toy-raw` is caught by the oracle when one is available, and by
`state_changed_without_ops` when it is not. macOS is expected to have no usable oracle,
so the second path has to work alone, and now that is asserted rather than assumed.

## 2026-08-10 — Spike-2: the oracle agrees, and disagrees where it should

The completeness comparison is in. The recording run goes through
`strace -y -e trace=%file,%desc`, its output is normalised to the same `OpClass` the
shim records, and the two class sequences are compared position by position.

On the supported toy:

```
oracle      agreed on 6 operations (61 syscall lines examined, 9 touching the state directory)
```

The scan size is in the report on purpose. "Agreed" over zero examined lines reads
exactly like agreement, and there is no way to tell them apart afterwards.

On `toy-raw` the oracle names what was missed and the run ends UNKNOWN. That target is
already caught by `state_changed_without_ops` without any oracle, so running it *with*
one is how the oracle path itself gets exercised rather than assumed — otherwise the
comparison code would sit there having never fired.

Details worth keeping:

- **strace must not have the shim loaded.** Environment reaches the target through
  strace's `-E`, not through the engine's own `setenv`: `LD_PRELOAD` set on the engine
  side would load the shim into strace, and strace's own file operations would land in
  the trace as if the target had produced them.
- **Read-only syscalls are excluded by name** (`newfstatat`, `read`, `access`, …). They
  cannot be crash points in any meaningful sense, and counting them would make the two
  views disagree for no reason. The exclusion is a fixed list, so a syscall that is
  neither modelled nor listed becomes `unsupported_syscall_observed` — UNKNOWN, not a
  silent skip.
- **The oracle comparison runs before the structural detectors**, because when both can
  catch something the oracle can say *which* operation was missed.
- The oracle's two verdicts got their own reasons (`oracle_missed_operation`,
  `oracle_saw_phantom`) rather than reusing `state_changed_without_ops`. Sharing a name
  would have defeated the acceptance check that requires distinct detectors to fire —
  the check would have passed while proving less.

`spike/acceptance.sh` now covers all of it and is green end to end. What remains for
v0.1: the L2 checker, macOS, the JSON report, and CI.

## 2026-08-10 — The engine judges, and the internal gate is passed

All three v0.1 acceptance checks now run for real, in the container, from
`spike/acceptance.sh`:

```
toy-bug   FAIL  crash point 5 of 5, after unlink(...key.json), before rename(...tmp)
toy-fixed PASS  explored (5) == N (4) + 1
toy-raw / toy-static / fork / thread   all exit 2, four *different* detectors
determinism                            3/3 identical reports
```

The distinctness of the four reasons is the part worth keeping honest about: an
implementation that always answers UNKNOWN passes check 2 on its own, and one that
decides everything from `ldd` gives the same reason four times. Requiring four
different detector names makes both of those visible.

### The engine does not use std.Io

`std.fs` no longer holds `File` or `Dir` in 0.16; spawning a child goes through an
`Io` vtable; `std.process.argsAlloc` is gone. Meanwhile everything the engine needs is
plain POSIX — walk a directory, read a file, fork, exec, wait — and the shim had
already shown that `extern "c"` works fine. So `src/posix.zig` binds libc directly and
the engine sits on that. ADR 0001's retreat condition ("two blocks from standard
library churn moves the engine to Rust") is much less likely to be reached now, because
the churning layer is not in the path.

`std.c.Stat` turned out not to describe Linux's `struct stat` usably here, so entry
kinds come from `dirent.type` instead — same information, no extra syscall, defined
identically on both target platforms, with `opendir` as the fallback for filesystems
that report DT_UNKNOWN.

### A real bug, caught by the tool's own detector

The engine first ran the target through `/bin/sh -c`. Every single run came back
`child_process_detected` — correctly, because the shell *forks* to start the program
and LD_PRELOAD applies to the shell too. Switching to `sh -c "exec …"` only trades the
fork for an exec, which the same detector catches. The target has to be executed
directly, so the engine now splits the command itself and calls `execvp`.

Two things fell out of that. The boundary detector was proven to fire on a real
occurrence rather than a contrived one. And the limitation is now explicit: arguments
cannot contain spaces until the CLI takes an argv instead of a string.

### Tests that were not running

`zig build test` reported 19 passing while five more tests sat uncollected: Zig
analyses declarations reachable from the root module, and a `test` block inside an
imported file is not reachable that way. Naming each file with tests explicitly in
`build.zig` took it to 26. Nothing was red at any point — the count was the only
signal, which is the whole argument for asserting how much was measured rather than
that the result was green.

### An acceptance check that was wrong in the safe direction

The first version asserted the corrected toy would report "crash points 5 + 1". It
reports 4 + 1, because without the `unlink` it has one fewer operation — the
implementation was right and the check was wrong. Rewritten to compare `explored`
against `N + 1` as a relation, so it stays true whatever the toy does.

Still open from the plan: the strace oracle comparison (Spike-2). The structural
detectors carry the load in the meantime, and `toy-raw` shows they carry it — its
trace is 30 bytes of "nothing happened" while the state directory visibly changed.

## 2026-08-10 — Spike-1: the interposition ground holds (Linux)

The biggest risk retired first, as PRD.md promised. Measured, not argued.

**The shim works.** A recording run of the buggy toy produces this, in order:
`shim_ready`, `open`(seq 1), `write`(2), `fsync`(3), `close`(seq 0), `unlink`(4),
`rename`(5). `close` carries seq 0 because it is recorded but never a crash point, so
N = 5. The delete-before-rename window is visible in the trace as the gap between
seq 4 and seq 5.

**The kill lands where it is asked to.** `SIDEEYE_KILL_AT=k` for k = 1..5 exits 137
(SIGKILL) with a `kill_landed` record present; k = 6 — that is N+1 — runs to completion
with no marker, which is the baseline world. At k = 5 the state directory contains
`key.json.tmp` and no `key.json`: the bug, caught in the act. **10/10 repetitions land
in the identical state.** The corrected toy keeps `key.json` present at every k.

**Two recording runs produce byte-identical traces.** The determinism claim is a byte
comparison, not an impression.

**Out-of-bounds targets are visibly out of bounds**, and each for its own reason:

| target | what the shim sees | what makes it detectable |
|---|---|---|
| `toy-raw` (syscall(2) directly) | 30 bytes: `shim_ready` and nothing else | the state changed while zero operations were recorded |
| `toy-static` | no trace file at all | the shim never loaded, so no marker exists |
| `toy-bug` + fork | a `fork` record | the boundary detector fired |
| `toy-bug` + thread | a `thread` record | ditto |

`toy-raw` is the one that justifies the engine carrying detectors that do not depend on
interposition: its trace is indistinguishable from "this program touched no files".

**Rust's standard library did not route around the supported operation set.** The
plan rated that a high risk — `open64`, `statx`, `openat2` were all plausible. The
stand-in target produced *exactly* the same operation sequence as the C toy:
`open`, `write`, `fsync`, `close`, `unlink`, `rename`. One measurement is not a
guarantee for every Rust program, but the expected divergence did not happen here.

### What the `zig` skill got wrong

The skill was adopted the same day to reduce the risk of generated code targeting old
APIs, and the plan required recording the first discrepancy rather than quietly working
around it. Three showed up, all in the same area:

| skill says | 0.16.0 actually has |
|---|---|
| `std.mem.trimRight` | `std.mem.trimEnd` (`trimLeft` → `trimStart`) |
| `std.fs.File` | `std.Io.File` — `std.fs` has no `File` member |
| `file.writer(&buf)` | `file.writer(io, buf)` — a `std.Io` instance is required |

The skill states that every 0.16.0 stable pattern in it still holds; its I/O section is
0.15-era. Worth knowing before the engine, which cannot avoid that API the way the shim
can.

### A design correction found by building it

DESIGN §12 defines the L0 invariant as: after restart the state directory equals the
pre-operation snapshot or the post-operation result, never a hybrid. Implementing that
literally fails the *corrected* toy — an atomic write leaves `key.json.tmp` behind at
several crash points, so the directory equals neither snapshot.

The invariant that separates the two toys is narrower: **for every path present in both
the pre and post snapshots, the crashed state must contain it, with content equal to one
of the two.** Paths belonging to neither snapshot (temporaries) are ignored. Under that
reading the buggy toy fails at k = 5 (`key.json` missing) and the corrected toy passes
everywhere, which is the distinction the tool exists to draw. DESIGN will be amended.

### Also decided

- **No `anyzig`.** The plan called for it to fetch the pinned compiler, but Homebrew's
  `zig` 0.16.0 — the exact version wanted — was already installed, and `anyzig` conflicts
  with it (both provide a `zig` binary). The declaration in `build.zig.zon` is what other
  environments need; the fetching mechanism is interchangeable.
- The link-type check in `build-toys.sh` first used `file`, which is absent from the
  image; grep matched nothing and every binary was reported as wrongly linked. It failed
  loudly, which is the right direction, but the check now reads the ELF program headers
  (`readelf -l | grep INTERP`) so it does not depend on an optional tool.

## 2026-08-10 — Inception

Design finalized after an adversarial review pass over the first draft. Eight axes were settled; together they define what Sideeye is:

1. **Primary battleground: an automatic gate in the coding loop.** Non-interactive operation, machine-readable output, and the exit-code contract are v0 core requirements — not future polish. The caller is often an agent or CI; the reader is a human.
2. **LLM boundary.** The core (exploration, verdicts, shrinking, replay) is deterministic and LLM-free, permanently. LLMs are allowed at the edges only: proposing invariants on the way in, explaining reports on the way out.
3. **Pure black-box, elevated to principle.** Sideeye sees a binary, a state directory, and the execution's observable behavior. Nothing else. Language-agnostic by construction.
4. **Counterexamples are the whole product.** A PASS is a search record, not a badge, and we will not build a badge culture around it.
5. **Power failure / torn writes: out of v0, named as a long-term candidate.** v0's crash model is process crash — the OS survives, completed writes persist. Every report says so.
6. **v0 runs natively on macOS and Linux.** This was chosen knowingly: it pushes the mechanism toward userspace interposition (macOS forces every language through libSystem, which makes one mechanism cover Rust/Go/Python; the cost is that hardened-runtime macOS binaries and statically linked Linux binaries are declared unsupported rather than silently mishandled).
7. **Public design doc, in English.** This repository is the document.
8. **Define converges on built-in invariants.** L0 = zero-config atomicity judged from state-dir snapshots; L1 = the program's own success message on stdout, held against it; L2 = domain checker scripts. The whole user-facing contract is three commands and one directory.

Practical decisions the same day:

- **Name check:** crates.io free, GitHub free of significant collisions (max 3 stars). PyPI and npm are taken by unrelated projects (an eye-tracking library and an actively updated package, respectively). Shipped as `sideeye` anyway — distribution will be a single binary, so those registries matter little.
- **License:** dual MIT OR Apache-2.0.
- **Biggest known risk:** the interposition spike — kill a toy binary deterministically at the k-th file operation, on both OSes. It is deliberately the first milestone task in PRD.md; if it fails, better to learn that in week one.
