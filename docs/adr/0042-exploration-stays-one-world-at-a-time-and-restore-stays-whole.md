# 0042 — Exploration stays one world at a time, and restore stays whole, until a target needs otherwise

Status: Accepted (2026-09-03)

Closes #262. The issue was the tracked home for the engine's throughput bound: exploration is
strictly sequential and every world pays the full size of the state directory. Its cheap
first step, the binary search in `Snapshot.find`, shipped on 2026-08-24 (PR #300, in v1.0.0;
CHANGELOG, "#262, partial"). This record measures the bound, names what the remaining three steps would each
have to preserve, declines the fourth, and moves the tracking from the issue to DESIGN.md §9
and this page. The owner approved closing on 2026-09-03 after seeing the measurement; the
engine does not change.

## Context

One exploration runs the baseline world plus one world per crash point, in kill-index order,
in one process (`src/main.zig`, the `while (k <= n + 1)` loop). Each world starts with
`restore`, which deletes the whole state directory and recreates every entry from the
recorded snapshot (`src/engine.zig`, `restore` → `deleteTreeAt`; every directory is created
with the same requested mode, `0755`, every file with `0644`, both masked by the process
umask, and symlinks are recreated from their recorded targets), runs the operation under the shim, and ends with a full snapshot of
the tree, which the judges compare entry by entry against the recording. Every world
therefore writes every file once and reads every file once, whatever the operation touched.
Restore is whole on purpose: #164 pinned that a world starting with a previous world's
residue is judged wrong, and deleting the tree is what makes residue impossible rather than
detected.

The bound was measured for this decision (`spike/explore-cost/`, three runs, medians): one
laptop, the fixed toy (four crash points, one or two files of its own) over a padding
directory the operation never touches, no oracle, no checker, no forking target. Per world,
medians of three runs: 20 padding files, 0.17 s; 200, 0.56 s; 2,000, 3.7 s; 20,000, 28 s.
That is under 0.2 s per world plus 1.4 to 2.2 ms per padding file per world (1.4 ms on the
20,000-file shape, 1.8 ms at 2,000, 2.2 ms at 200), where "per world" is the engine's whole
clock divided by its five worlds and so an upper bound on one world (start-up, `setup`, the
recording run and its two snapshots are inside the clock). The laptop was not idle: the run
logs record a one-minute load average between 10 and 15, and the spread between runs was
2.0× on the 20-file row and 1.1 to 1.2× on the others. The shape is the claim, not the
constants. Bytes are secondary: the same 2,000 files at five times the size measured 8%
more per world.
DESIGN.md §9 carries the figures as a known constraint. They are held by review, not by a
check (ADR 0039): the script prints the engine's exit code and its own
`explored N worlds (crash points K + 1 baseline)` line beside every row, and a row that is
a refusal rather than an exploration prints no per-world figure, so the number quoted is
always one the engine confirmed it earned.

The number of crash points is the number of state-changing operations the recording saw,
which the operation decides and the file count does not. A run's cost is therefore
"per-world cost times crash points plus one", and no estimate of the form "2,000 files take
N minutes" is written anywhere, because the multiplier is not a property of the tree.

## Decision

1. **In 1.x the engine keeps exploring one world at a time, and `restore` keeps deleting and
   recreating the whole tree.** No `--jobs`, no differential restore, no crash-point selection
   on `explore`. The bound is declared in DESIGN.md §9 with its conditions and the path of the
   record.
2. **The issue closes; the tracking lives here.** The trigger for reopening any of the three
   steps below is a real target, not a benchmark: an exploration whose file count times crash
   points puts one run past what an operator will wait for. When that target exists, its
   figures are measured the same way (`spike/explore-cost/measure.sh`, or a sibling that
   records the same three columns) before anything is built.
3. **What each remaining step would have to preserve**, written now so the design question is
   not rediscovered:
   - **(a) Crash-point selection on `explore`.** Today only a replay narrows the loop
     (`only_k`, taken from the case; there is no entry from the CLI). A partial exploration
     changes what `explored` and `crash_points` mean to a reader: `explored` is documented as
     `crash_points + 1` for a full exploration (with the one exception the schema already
     states, an operation that changes nothing reports both as 0), and `violations` is
     "crash worlds whose invariant did not hold" over the worlds run. A partial run must therefore name the set it
     chose in the report, an additive field under `docs/contract-freeze.md` surface 2, and
     `earliest` must be read as earliest *among the chosen*, which the text report has to say.
   - **(b) Differential restore.** Applying the difference between the crashed snapshot and the
     recorded state instead of rebuilding the tree. It has to reproduce exactly what whole
     restore produces today, including the mode normalisation whole restore performs by
     construction (one requested mode for every directory and one for every file, masked by
     umask, so a verification leg compares modes against a whole restore rather than against
     constants; cohort 2's relocated Borg cache was an exec-bit case) and the symlinks it
     recreates, and it needs a verification leg that compares the tree after a
     differential restore with the tree after a whole one, byte for byte and mode for mode,
     because #164's strictness is the property being risked.
   - **(c) Parallel worlds.** Every world today shares one work directory: one
     `stdout-world.txt`, one trace path handed to the shim through `SIDEEYE_TRACE_PATH`, one
     kill index through `SIDEEYE_KILL_AT`. Workers need a work directory and a trace path
     each, and a state directory each, since `--state` is what the target writes to. Two
     report promises are order-dependent and would have to be computed after all workers
     return rather than falling out of the loop: `earliest` is the lowest violating crash
     point, which the sequential loop finds first by construction, and `checker_earliest.case`
     is "written strictly after the earliest's", so in a fresh work directory `000001` always
     belongs to the overall earliest. A field saying how many workers ran would be additive.
4. **Hash-first comparison is declined**, and the reason is recorded as a comparison question,
   not an I/O one: both sides of a judgement are already in memory (the recorded snapshot and
   the world's snapshot hold file contents in an arena), the comparison is `std.mem.eql`, a
   memcmp that stops at the first differing byte, and a hash has to read both contents to the
   end before it can say anything, so it is never cheaper than the compare it would guard.
   Hashing the recorded side once and reusing it across worlds does not change that: the
   world's side is new every world and would be read to the end to hash it, where the memcmp
   stops at the first difference. Where the per-world cost actually is, is the I/O either side of the compare: the whole
   write of restore and the whole read of the snapshot. That is what (b) is about.

## Alternatives considered

- **Build differential restore now.** Declined by the owner: no target has needed it, and
  the verification leg in (b) is most of the work.
- **Leave #262 open as the tracking issue.** Declined by the owner: an issue nobody measures
  against sits in a queue; the constraint belongs in the design document, and the
  prerequisites belong in a record that does not close.
- **Quote a total.** "2,000 files, eight minutes" was in the first draft. Dropped: the
  multiplier is the crash-point count, which the operation sets, so the total is not a
  property of the tree and the per-world figure is the only one the record can support.

## Consequences

- DESIGN.md §9 gains a known constraint with the per-world figures, their conditions and
  the record's path. The freeze-audit row for #262 moves to resolved / document; nothing on a
  frozen surface moved.
- `spike/explore-cost/` is a record directory: `measure.sh` (host only; not run by CI, because
  runner figures are not the figures the constraint quotes), three raw runs, and `RESULTS.md`
  with the medians. `.gitattributes` classifies it as documentation by position.
- A reader who hits the bound on a real target finds the three preconditions here, and the
  measurement script that turns their case into the same three columns.
