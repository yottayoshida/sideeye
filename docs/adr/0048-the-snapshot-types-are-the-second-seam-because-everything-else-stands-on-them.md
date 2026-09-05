# 0048 — The snapshot types are the second seam, because everything else stands on them

Status: Accepted (2026-09-05)

## Context

ADR 0047 took the trace reader out of `src/engine.zig` as the first seam of #491 and left
the file at 4,745 lines holding four of the issue's five parts. The change that shipped it
also closed #491 by a `Closes` line in its commit message, with one seam of four done; the
issue was reopened the same day. This ADR is the second seam and does not close it either.

#491 sketches the remaining files as `engine/snapshot.zig` (`Entry`, `Snapshot`, diff and
reconciliation and their invariants), `engine/state_fs.zig` (walk, restore, fresh, corrupt,
root safety) and `engine/judge.zig` (classification, `L0Plan`, the judges, scratch
semantics), "subject to what the code proves during extraction", and says the first
extraction should be "whichever seam has the clearest independent contract and least
coupling". 0047 measured the candidates it could see at the time and predicted two costs for
whatever moved next: a reverse edge from the snapshot region into the classifier
(`scratchMatches`), and that three tests about symlink agreement — the rebuild refusing to
write through a link, `corruptState` refusing a planted link, and the three regions carrying
links as links (#122) — could not be split, so "whichever region moves next will cross at
least one of them".

## Decision

**The snapshot region goes second**, to `src/engine/snapshot.zig`: `Entry`, `Snapshot` with
`find`, `OrderProblem` / `validateSortedUnique`, `firstUnsupportedEntry`, `Difference` /
`DiffCount` / `diffSnapshots` / `diffSnapshotsExcept`, `Unaccounted` / `Reconciled` / `Link` /
`reconcile` / `collectLinks` with the link-resolution helpers behind them, and the
twenty-six tests that hold them (the reconcile and diff tests, the `find` cost and
correctness tests, the `validateSortedUnique` test, the producer-boundary test, and the
`scratchMatches` test).

Measured reasons, in the order they decided it (line numbers are `origin/main` at `2f7067d`):

- **Direction.** Outside the seven line ranges that move, `engine.zig` spells `Snapshot`
  54 times and `Entry` 4 times (word occurrences; a first count of 58 and 7 had left the
  helper lines on the outside, and a first-look reviewer re-measured) — the walk, the
  restore and the judges all take or build snapshots. The moved code reaches outward to
  `Op` (29 times, already in `engine/trace.zig`), `contract.isInsideDir` once, `posix.Kind`
  twice, and three small helpers. Every other candidate imports the snapshot types;
  the snapshot types import none of the candidates.
  Extracting the walk, the restore or the judges first would have each of them import
  `Snapshot` from `engine.zig` — a cycle, which #491 names as the stop condition. This seam
  is what makes the next two possible.
- **Nothing private crosses.** The ten private names that move — `relUnderRoot`,
  `appendInto`, `substituteOnce`, `resolveThroughLinks`, `reconcileIn`, `compareRel`,
  `rel_comparisons`, `max_link_hops`, `linearFind` and `lessThanRel` — are referenced by
  nothing outside the moved code.
- **The three symlink-agreement tests do not move and are not crossed.** They exercise
  `takeSnapshot`, `restore` and `corruptState` — the walk and the destructive side — and
  all three stay in `engine.zig`. ("The producers", here and in the module map, are the
  two the code calls by that name: the walk's `takeSnapshotCapped` and the `testSnapshot`
  fixture, the two that end in `finalizeEntries`.) 0047's prediction was written for the walk and restore regions and does not
  hold for this one.

**Four small helpers move with the region**, each decided by who uses it:

| helper | was | now | why |
|---|---|---|---|
| `lessThanRel` | walk region, private | `snapshot.zig`, private | the order of `Entry`; used by `finalizeEntries` and one diff test |
| `finalizeEntries` | walk region, private | `snapshot.zig`, **pub** | sort + `validateSortedUnique` — the sorted-unique invariant closed at the producer boundary, the thing #491 says to preserve. `takeSnapshotCapped` calls it through the facade |
| `scratchMatches` | judge region, pub | `snapshot.zig`, pub | `diffSnapshotsExcept` uses it; left on the judge side it would make `snapshot.zig` import the judges, the cycle. The *semantics* — what `classifyWith` does with a match, `L0Plan.isScratch` — stay with the judges |
| `testSnapshot` | among the judge tests, private | `snapshot.zig`, **pub** | the fixture that builds a snapshot through `finalizeEntries`, used by the `find` tests that move and by the judge tests that stay. Public so the judge tests keep their spelling through the facade |

**Five types the walk fails or reports with stay in `engine.zig`**: `SnapshotError`,
`SnapshotCaps`, `FileTooLargeDiag`, `TreeTooLargeDiag`, `SnapshotDiag`. They are the
producer's vocabulary — `SnapshotError` is returned by `charge`, `walk`, `takeSnapshot` and
`takeSnapshotCapped` and by nothing else, and of its eight members only
`EntriesNotSortedUnique` belongs to the invariant, which `finalizeEntries` already names in
its own error set. They move with the walk. The promise written into `engine.zig`'s module
map therefore says `Entry` and `Snapshot`, not "the snapshot types"; the first draft said
the latter and a first-look reviewer showed it false at merge.

**`reconcile` stays with the snapshot types**, as the issue sketched, so `snapshot.zig`
imports `trace.zig` for `Op`. `snapshot.zig` imports `trace.zig`, `contract` and
`../posix.zig`; `trace.zig` imports `read.zig`, `contract` and `../posix.zig`; nothing
under `engine/` imports `engine.zig`. No cycle.

**The facade test walks both parts.** `engine.zig`'s test that every public declaration of
`trace.zig` is re-exported now runs over a list of parts — two arrays, names and types, so
the compile error can say which part dropped a name. `refAllDecls(snapshot)` joins the
block that makes test collection unconditional (0047 records why).

## Alternatives considered

- **The restore region second.** Imports `Snapshot`; a cycle unless this seam comes first.
  0047's cost measurement (about 23 private helpers, four ADRs) still stands for seam 3.
- **The judges second.** Same cycle, plus the `scratchMatches` edge.
- **`reconcile` in its own `engine/reconcile.zig`.** A purer graph — `snapshot.zig` would
  not need `trace.zig` — but two files in one seam, against the issue's "one semantic
  extraction per PR", and against its own sketch. Splitting a leaf into two later is cheap.
- **A second copy of `testSnapshot`** (the `joinZ` precedent from 0047). `joinZ` is three
  lines with no claim; `testSnapshot` is twenty lines whose claim is "built under the same
  finalizer as a real snapshot", and two copies open a path for one to be built under
  weaker rules.
- **`scratchMatches` in a new `engine/path.zig`.** A file for seven lines.
- **`scratchMatches` replaced by `contract.isInsideDir`.** The same shape of predicate, but
  a behaviour change hidden in a file move is what #491 forbids; if it is right it is its
  own change.
- **Moving `SnapshotError` too**, so "the snapshot types" could stand as written. Wrong
  owner: seven of its eight members are walk failures.
- **Working on the shared checkout.** It carries another session's open PR; switching it
  breaks that session's readers. The seam is built in a linked worktree on the batch
  branch, fast-forwarded to `main` after checking that the branch holds nothing `main`
  does not.

## Consequences

- `engine.zig` loses about 1,220 lines and gains seventeen re-exports; `snapshot.zig` is
  about 1,235 lines including tests. Exact counts are written at commit time, not here —
  0047's line count drifted four times between plan and merge.
- `main.zig` and `mcp.zig` are unchanged; they reach everything as `engine.*`. The report,
  the case format, the CLI and the MCP surface are untouched.
- The facade's public surface gains two names that were private: `finalizeEntries` (a
  producer boundary) and `testSnapshot` (a fixture). Neither is a contract surface.
- **The `scratchMatches` edge is inverted, not removed.** Before: the snapshot region
  reached into the judge region for it. After: the judges reach `snapshot.zig` through the
  facade. Seam 4 (`judge.zig`) will import `snapshot.zig`; that is the right direction.
- **What measures #491's success criterion next.** 0047 named the refusal-naming work as
  the first real change to measure the trace seam against. For this seam the measurement
  is structural and belongs to seam 3's plan: whether the walk and the restore can leave
  `engine.zig` importing `snapshot.zig` alone, with no reference back. Before this seam the
  answer was no for every remaining region.
- **For seam 3.** `SnapshotError` and the four cap/diag types go with the walk. The three
  symlink-agreement tests are where 0047 said they were, and now they are the cost of the
  next seam rather than this one.
- **Stop conditions, restated from #491**: a cycle, a contract type defined twice, glue
  larger than the coupling it removed. None arose; the cycle was one ownership decision
  away (`scratchMatches`).
- **#491 stays open after this change.** The commit message and the PR body refer to it as
  `Refs #491` and put no closing keyword in the same clause, negated or not — GitHub closes
  on "not closed by" too.
