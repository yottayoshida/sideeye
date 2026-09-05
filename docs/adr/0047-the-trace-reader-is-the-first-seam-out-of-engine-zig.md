# 0047 — The trace reader is the first seam out of `engine.zig`

Status: Accepted (2026-09-05)

## Context

`src/engine.zig` had grown to 6,043 lines holding five parts of the product with different
semantic and trust boundaries: the snapshot types with their diff and reconciliation, the
walk that takes a snapshot and its caps, the destructive restore and its root vets, the
trace reader, and the classification and judges. #491 asks for those to be extracted one
seam per change, with the file kept as the exploration facade, under constraints it states:
no behaviour change, no change to report / case / CLI / MCP / contract, tests move with the
implementation they hold, and stop rather than continue if the extraction produces a cycle,
a duplicated contract type, or adapter glue larger than the coupling it removes.

#488 and #489, shipped the same day, had just touched the trace's writer and reader. #489 in
particular split `readWhole` — one helper serving both the engine's own trace and the
target's state files — along a `LinkPolicy` parameter, which is the shape #491 cites as the
reason the boundaries have started to matter for correctness.

## Decision

**The trace reader goes first**, to `src/engine/trace.zig`: `Op`, `TraceInfo`,
`TraceReadError`, `max_trace_bytes`, `max_trace_bytes_total`, `TraceBudget`,
`unboundedBudget`, `readTrace`, `readTraceCapped`, the decode loop, and the nineteen tests
and four fixtures that belong to them.

Measured reasons, in the order they decided it:

- It is the only region `engine.zig` fenced off itself — the two separator rules at 2305
  and 2843 were the only two in the file.
- Its code referenced exactly two things outside the region: the private `readWhole` (one
  call) and `TraceReadError` (three mentions, in the error-set block).
- Nothing in the judge or corruption regions referenced it back. The one reverse edge is
  `reconcile` taking `Op` as an argument, with 27 tests spelling `Op` literals.
- Its tests used trace identifiers, `readWhole` and `joinZ`, and nothing from snapshot,
  restore or judge.
- The next candidate, restore with the corruption probe, crosses about 23 private helpers
  and is named by four ADRs (0011, 0022, 0042, 0046). The classifier has a reverse edge from
  the snapshot region (`scratchMatches`).

**`readWhole` goes to `src/engine/read.zig`** with `LinkPolicy` and `ReadWholeError`, imported
by both `engine.zig` and `engine/trace.zig`. It is the one helper both sides need; inside
either file it would be a cycle, which is the stop condition.

**`Op` goes to `trace.zig`** and `engine.zig` re-exports it. `TraceInfo.ops` is an
`ArrayList(Op)`, so leaving `Op` behind would be the same cycle from the other side.

**`engine.zig` re-exports every public declaration of `trace.zig`**, and a test walks
`std.meta.declarations(trace)` to check that it does — walked rather than listed, because
two of the nine (`readTrace`, `unboundedBudget`) are referenced by nothing outside
`engine.zig`, so forgetting a re-export would otherwise leave every build, test and
acceptance leg green with the module map false. `main.zig` and `mcp.zig` are unchanged.

**The two new files are not in `build.zig`'s `test_sources`, because they cannot be**: as a
root, their `../posix.zig` falls outside the module path. Their tests are collected through
the engine and main roots, and `engine.zig` carries
`test { std.testing.refAllDecls(trace); std.testing.refAllDecls(read); }` to make that
collection unconditional. This is where the plan was wrong twice. `build.zig`'s comment said
an imported file's tests are not reachable from a root; the step-by-step counts said they
are (engine root 124 = engine 102 + posix 22); the same counts held the counterexample (mcp
root 28 = mcp 6 + posix 22, with `engine.zig` imported and none of its 102 running). Zig
analyses lazily: an imported file's tests are collected only when a test in the root reaches
a declaration of that file. `build.zig`'s comment now says so.

## Alternatives considered

- **All four seams in one change.** #491 rules it out, and the measurement above says the
  seams are not equally clean.
- **The restore region first.** Largest coupling, and four ADRs to rewrite.
- **`src/trace.zig`, flat.** The first plan, on the strength of a minimal experiment that
  made `trace.zig` a test root and saw `../posix.zig` refused. That experiment measured the
  wrong thing: `trace.zig` is not a root.
- **`readWhole` into `posix.zig`.** Argued from `posix.zig` already using allocators in
  seventeen places; the count is twelve, all inside the sidecar's start-and-stop region, and
  `posix.zig`'s first line calls itself "direct libc bindings". The promise of this change
  names `trace.zig` and `engine.zig`, so a layering decision in `posix.zig` was being made
  outside it.
- **`readWhole` into `trace.zig`, with the walk importing `trace`.** Wrong name for what the
  walk depends on, and the `/dev/zero` test — a snapshot-side property — would land in the
  trace file.
- **Two copies of `readWhole`.** Two `ReadWholeError` sets, and the test that pins the three
  error sets' sizes could not say which one it counts. The repository already refused a
  hand-copied second definition of a set (#280).
- **`Op` into `contract.zig`.** `contract` is the module the shim shares; a type the shim
  never uses does not belong in it.
- **Rewriting `main.zig`'s 22 sites to `engine.trace.*`.** Wider diff, same boundary.
- **A hand-written list of nine names in the facade test.** Goes quiet on the tenth.

## Consequences

- `engine.zig` is 4,745 lines (4,692 straight after the move, plus the module map, the
  facade test, the `refAllDecls` block and the comments review asked for). `trace.zig` is 1,251 including tests; `read.zig` 162.
- `main.zig`'s 22 references and `mcp.zig`'s one are unchanged. The report, the case format,
  the CLI and the MCP surface are untouched; acceptance is the same 282 checks.
- `zig build test` runs 546 (was 544): the facade test is collected in both the engine and
  main roots. The `refAllDecls` block has no name and adds nothing to the count.
- Comments in `trace.zig` name declarations that live elsewhere: in `engine.zig`
  (`max_state_file_bytes`, `max_state_tree_bytes`, `SnapshotError`, `takeSnapshotCapped`),
  in `main.zig` (`snapshotDetail`, `readTraceOrRefuse`), in `read.zig` (`ReadWholeError`,
  once, in a line comment), and in `contract.zig` (`max_path`, unqualified). They are prose
  references, listed in `trace.zig`'s header so the next reader knows they are not imports.
- `joinZ` exists twice: three lines around `bufPrintZ`, with no contract of their own, used
  by `trace.zig`'s fixtures. Copied deliberately rather than exported.
- **What this change does not demonstrate**: #491's own success criterion — that an
  extracted module makes a *subsequent* real change more local. There is no subsequent change
  yet. The first candidate is the refusal-naming work #488 and #489 both deferred, which
  touches the trace reader at all three read sites; that change is where this one gets
  measured.
- **For the next seam.** Three tests cannot be split cleanly — `the rebuild refuses to write
  through a symlink`, `corruptState refuses a planted symlink`, and `snapshot, restore and
  corruptState carry symlinks as links (#122)` — because their property is that three regions
  agree about symlinks. Whichever region moves next will cross at least one of them. The
  classifier's reverse edge (`scratchMatches` used by the snapshot region) and the restore
  region's four ADRs are the other two costs already measured.
- **Stop conditions, restated from #491**: a cycle between `engine.zig` and a part, a
  contract type defined twice, or glue larger than the coupling it removed. None arose here;
  the first two were each one wrong decision away.
