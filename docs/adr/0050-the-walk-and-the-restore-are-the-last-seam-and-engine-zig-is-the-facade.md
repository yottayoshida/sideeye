# 0050 — The walk and the restore are the last seam, and `engine.zig` is the facade

Status: Accepted (2026-09-05)

## Context

Three seams of #491 are out of `src/engine.zig`: the trace reader (ADR 0047), the
snapshot types (0048) and the judges (0049). What is left at `19067e2` is 2,745 lines: the
snapshot walk with its caps, the destructive restore with its root vets, the corruption
probe, the facade blocks that re-export the three parts already out, and `WorldResult`.
The issue sketched this last region as `engine/state_fs.zig` — "walk/snapshot acquisition,
restore/fresh/corrupt paths, destructive root safety" — and 0049 left one question for
this seam's plan: where `WorldResult` goes.

## Decision

**The walk and the restore leave together**, to `src/engine/state_fs.zig`: the nineteen
public declarations (`SnapshotError`, `max_depth`, `max_state_file_bytes`,
`max_state_tree_bytes`, `SnapshotCaps`, `FileTooLargeDiag`, `TreeTooLargeDiag`,
`SnapshotDiag`, `takeSnapshot`, `takeSnapshotCapped`, `RestoreError`, `assertSafeRoot`,
`assertSafeNamingRoot`, `freshDir`, `restore`, `corruption_probe`,
`corruption_probe_target`, `corruptState`, `countCorruptible`), the twenty-three private
declarations behind them, and thirty-one tests. `engine.zig` keeps `WorldResult`, the test
that pins the three read error sets together, and the checks on the facade itself.

Measured (line numbers are `origin/main` at `19067e2`):

- **What the region reaches outward, in code.** `Snapshot` eleven times, `Entry` once and
  `finalizeEntries` once from `snapshot.zig`; `readWhole` five times from `read.zig`;
  `posix`, `contract` and `engine_build_options` (the last a module import, resolved from
  under `src/engine/` the way `snapshot.zig` resolves `contract`). **Nothing from
  `judge.zig` and nothing from `trace.zig`** — 0049 listed `trace` among what this region
  reaches, and that was the facade's own re-export lines being counted; corrected here.
- **One file, not two.** The plan's first reason for not splitting the walk from the
  restore — that the root vets serve both — was false: the walk (255–415) names no vet.
  Two real couplings hold them together. `max_depth` is one constant with two meanings,
  the walk's descent bound and `deleteTreeAt`'s, and its doc comment says so ("**and how
  deep `deleteTreeAt` descends before refusing to delete**"). And the test `snapshot,
  restore and corruptState carry symlinks as links (#122)` (2241) exercises all three in
  one body, which 0047 predicted no seam could split. Splitting the file would put the
  constant and that test on one side of a line the other side depends on.
- **`WorldResult` stays in `engine.zig`.** It holds `k`, `term`, `landed` and
  `violation`: a kill's outcome, produced only by `main.zig`'s world loop (3229, 3241).
  No function in the walk, the restore or the judges returns it. It is the orchestrator's
  type, and `engine.zig` remains the exploration engine's public surface, so that is
  where it belongs. Moving it to `main.zig` would remove a name from that surface —
  a change to what `engine.*` offers, which this change does not make.
- **The three-set test stays in `engine.zig`.** It pins `SnapshotError`, `ReadWholeError`
  and `TraceReadError` in one place, on purpose (its own comment says so), and the facade
  is the only file where all three are visible without importing three parts.

**Seven documents are re-pointed with a parenthesis, not a rewrite.** ADRs 0011 (line 8),
0022 (173–174), 0042 (18), 0046 (6, 48) and `docs/freeze-audit.md` (431; the table there
is a generated block whose source is `spike/freeze-audit/audit.tsv`, so the note is in the
TSV and the page is re-rendered from it) say the root vets,
`freshDir` or the restore live in `engine.zig`; 0048 (66) says five types "stay in
`engine.zig`"; 0049 (59) says two things stay there that the word "judge" might claim, and
one of the two — `SnapshotError.ClassifyFailed` — moves with the walk. Each gets
"(since #491: now `src/engine/state_fs.zig`)" after the claim, and not one word of the
decision they record changes — the same rule the last three seams kept: a later ADR
corrects, an earlier one is not edited into agreement. Where 0048 and 0049 count the
facade's parts ("both", "three"), the count stands as a description of the facade on the
day they were written; this ADR says four.

**Comments elsewhere that named `engine.zig` as where the walk or the restore live are
corrected in place**: `src/main.zig` (the `RestoreError` note at the world loop),
`src/contract.zig` (the `opendir … orelse return` note about the walk), the headers of
`judge.zig` and `trace.zig`, and two acceptance scripts (`spike/acceptance.sh`, whose
note also named a vet by a name it lost in an earlier rename, and
`spike/mcp-acceptance.sh`). Comment lines only; the sweep that found them ran over `.zig`,
`.md` and `.sh`, after a first sweep that had left `.sh` out.

**What this does not settle.** #491's own success criterion — that an extracted module
makes a subsequent real change more local — is still unmeasured after all four seams,
because there is no subsequent change yet. The first candidate remains the
refusal-naming work #488 and #489 deferred, which touches the trace reader and the world
loop's account of a kill. Whether #491 closes on the four files or on that measurement is
the issue owner's call, asked separately from this change.

## Alternatives considered

- **Two files, `walk.zig` and `restore.zig`.** `max_depth` and the #122 test would have to
  choose a side; the issue's sketch is one file; and the issue says four files are a
  candidate, not a requirement — which cuts both ways and does not argue for five.
- **`WorldResult` into `main.zig`.** Removes a name from `engine.*`; not a move.
- **`WorldResult` into `judge.zig` or `state_fs.zig`.** Neither produces it.
- **The three-set test into `state_fs.zig`.** It would then read two of its three sets
  through imports of other parts, which is what pinning them in one place avoids.
- **Rewriting the seven documents' sentences.** They record decisions; the address moved,
  the decisions did not.
- **Closing #491 in this change.** The four files the issue sketched exist, but the
  demonstration it asked for does not. The first seam closed the issue by a `Closes` line
  with one file of four done and was reopened the same day; this one leaves the close to
  the owner.

## Consequences

- `engine.zig` is about 230 lines: the header with a five-entry module map, the facade
  blocks re-exporting fifty-three names across four parts, `WorldResult`, the three-set
  test, and the facade's own checks. Exact counts are written at commit time.
- `state_fs.zig` imports `std`, `contract`, `../posix.zig`, `engine_build_options`,
  `read.zig` and `snapshot.zig`. The graph is `state_fs → {snapshot, read}`,
  `snapshot → trace → read`, `judge → snapshot`; no cycle.
- `mcp.zig` is unchanged and `main.zig` changes in two comments; every name they spell as
  `engine.*` is a re-export. The report, the case format, the CLI and the MCP surface are
  untouched.
- The tests `engine.zig`'s root collects may change in count without changing coverage:
  `posix.zig`'s tests were collected there because `engine.zig`'s own tests called
  `posix.*`, and after the move none of the two remaining tests do. If `refAllDecls` on
  the parts reaches `posix` transitively the count stays; if not, `posix.zig`'s tests still
  run in their own root, and `build.zig`'s comment naming the engine root as an example
  is corrected. The plan measures which, before and after.
- **Stop conditions, restated from #491**: a cycle, a contract type defined twice, glue
  larger than the coupling it removed. None arose in any of the four seams.
- **#491 stays open after this change**, and the question of closing it is asked of the
  owner with the measurement above in hand.
