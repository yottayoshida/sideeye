# 0029 — The snapshot caps what holding the tree costs, not what the tree weighs

Status: Accepted (implementing PR merged as `ab8c688`, 2026-08-27)

## Context

`max_state_file_bytes` (#265) bounds one read at 64 MiB. Nothing bounded the sum, and the
constant's own comment said so: "a tree's TOTAL stays unbounded, and this constant must not
be read as a memory ceiling for the run". A tree of files each comfortably under the
per-file cap — 60 MiB a thousand times over — passes every check and ends in an OOM kill
with no report, which is the failure the per-file cap was built to remove. #323 is that
gap.

Two facts shape everything below.

**The allocator's own failure path does not fire.** Under Linux's overcommit the pages are
touched, so the kernel kills the process before `error.OutOfMemory` can be returned and
classified. A ceiling is what makes running out of memory reportable at all there. (macOS
is unmeasured: `mmap` may fail first and reach the error.)

**What a tree weighs and what holding it costs are different numbers.** The snapshot holds
everything in one arena that never frees. Measured before any change: one 64 MiB file left
the arena holding 113,780,014 bytes; 50,000 empty files held 12,959,676 bytes against a
content sum of zero; and the cost was **not monotonic in the tree** — two 32 MiB files cost
more than two 64 MiB ones, because where a growing buffer falls relative to an arena node
boundary decides how much of it is stranded.

## Decision

### The ceiling is read off the arena, not summed from file sizes

The check is `ArenaAllocator.queryCapacity()` against `max_state_tree_bytes`, evaluated
once per directory entry inside `walk`.

The rejected alternative was a hand-rolled `content.len + rel.len + @sizeOf(Entry)` sum.
It was the plan of record until first-look review measured it — on a standalone probe
reproducing `walk`'s allocation pattern, not on the engine — and found ratios of 1.70x,
2.43x and 7.07x on three tree shapes, worst on the all-empty-files shape the per-entry term
had been added to catch. **What the engine itself was measured at is the first of those and
a smaller version of the third**: one 64 MiB file held 113,780,014 bytes against 67,108,864
read, and 50,000 empty files — not the probe's 200,000 — held 12,959,676 bytes against a
content sum of zero, where a proxy has no denominator at all. A bound whose error varies
with the shape of its input is not a bound. Asking the
allocator also covers, without having to name any of them, the symlink target dupe, the
`rel` that the `.missing` branch allocates and drops, and the entry list's own growth.

The cost of that choice is that the number is not one an operator can reproduce with `du`.
The refusal therefore reports both: the arena's reach *and* the content bytes and entry
count behind it, saying which is which.

### `readWhole` reserves from the file's own length

Not an optimisation bolted on: without it the ceiling is not a contract anyone can predict.
The doubling buffer stranded its earlier copies in the arena, which is where both the 1.70x
and the non-monotonicity came from. Reserving the file's length up front (a hint — the loop
still reads to EOF, and past the cap it reserves only `cap + one chunk`) makes the cost a
flat **1.50x**, measured at 64 MiB, 32 MiB and 1 MiB: exactly `ArenaAllocator`'s node
growth factor, and nothing else.

What remains is that factor, **including the non-monotonicity**. A request that does not fit
the current node takes a new one sized 1.5x *(node + request)*, so several large files still
cost more than 1.5x their content — two 64 MiB files reach 336 MiB. The reservation removed
the stranding term and with it the specific inversion that motivated it (two 32 MiB files
costing more than two 64 MiB ones); the node term inverts a different pair, measured at the
shipped ceiling: **two 50 MiB files (100 MiB of content) are refused at 262 MiB while four
32 MiB files (128 MiB) are accepted at 168 MiB**. Stated rather than closed — and the
BUILDLOG's first version of this said the response was "not to document it but to remove
it", which is true of the term that was removed and false of the property.

### The walk stops at the break; the refusal reports only what it read

#323 asked the refusal to name "the total, the cap, and the largest contributors". Naming
contributors means continuing past the break in an accounting-only mode, and that was
rejected on four measurements:

- The continuation still runs `TooDeep`, `PathTooLong`, `ClassifyFailed` and
  `readLinkTarget`'s `ReadFailed`, and `walk`'s `opendir(...) orelse return` treats an
  unopenable directory as empty. Either a later failure replaces the size refusal, or the
  "real" total silently omits a subtree. Both orders are wrong in a documented way.
- Breadth is unbounded and `max_depth` does not touch it: first-look review measured
  200,000 empty entries at 13.88 s of syscalls on this machine's APFS, on a run that is
  already being refused. Not measured on the CI filesystem, and not by the engine.
- Ties in file size leave a top-3 order-dependent anyway — and the natural fixture, N sparse
  files of one size, is exactly the tie case.
- **It inverts the precedent it cited.** `FileTooLargeDiag.size` is optional because "a size
  nobody measured must not appear in the message". The answer that rule gives is to say
  less, not to walk further.

The refusal names the arena's reach, the ceiling, the content bytes and the entry count,
says those describe what was read rather than the tree, and points at `du -sb` and
`find | wc -l`. Naming contributors is filed separately, to be built if operators ask.

### Enforced inside `walk`, which reaches all five snapshot sites

A stat-only pre-pass before the initial snapshot was rejected three ways: the tree grows
during the operation, so a pre-run figure bounds nothing later (the same proxy shape #329
removed from the root vet); it opens a check-to-use window; and it adds a second traversal
to a cost #262 already measures. Inside `walk`, `run_phase` (#330) gives each site its
verdict for free — SETUP_ERROR at the initial snapshot, UNKNOWN at the four at or past the
recording run.

Three of the five sites precede the world loop (`initial`, `final`, `final_again`), so a
tree that is too large is refused before any world runs in every case except one: a crash
world that writes more than the recording did.

### A new closed-set member, which means before the tag or never

`state_tree_too_large` joins `contract.UnknownReason`.

- Not a share of `state_file_too_large`: a caller reading that goes looking for one
  oversized file, and here every file can be comfortably under the per-file cap.
- Not a share of `state_unsnapshotable` either: that member is the residue for failures
  with no limit behind them, and `snapshotDetail` already draws the line — the refusals
  with a limit report it, because a limit is something the operator can act on.

`docs/contract-freeze.md` makes the closed set exempt from surface 2's additive allowance:
gaining a member after the tag is a breaking change. **That clause was itself written on
2026-08-26** (`0e035eb`, #320/#324), which is worth recording next to a decision that leans
on it. The set has moved five times inside the current freeze-audit window (24 to 29:
`child_wait_failed`, `parent_exited`, `trace_too_large`, `state_file_too_large`,
`state_unsnapshotable`); this is the sixth. `contract_version` does not move — it versions
the trace's binary format, and neither #324 nor #351 touched it, so no saved case is
orphaned (#279). That is a statement about closed-set additions only: measured with
`git log -G`, the version has moved more than ten times, twice on 2026-08-26 alone. `-S`
reports one commit for it, because a value edit does not change how often the string
appears.

`SnapshotError` gains `TreeTooLarge`, and that error set is shared with `readTrace` /
`readTraceCapped` — so the trace reader now declares a failure it cannot raise. Nothing
breaks (its one caller catches everything into `setupError`), and splitting the sets is
left to its own change.

### The value: 256 MiB, chosen against measurement

At 256 MiB every 128 MiB-of-content shape tried is accepted — 4x32, 8x16, 16x8, 64x2 MiB.
In the two-file family the boundary sits far lower: **2x48 MiB (96 MiB) is accepted and
2x49 MiB (98 MiB) is refused**, and two files at exactly the per-file cap reach 336 MiB.
256 MiB of content is refused in every shape tried. Reading "128 MiB of content fits" off
the accepted list would be wrong, which is why the two-file boundary is written here too.

**What the criterion selects, and what it does not.** A ceiling must clear one file at the
per-file cap, or it refuses a tree holding exactly what the other ceiling permits: 256 MiB
clears that at 96 MiB with room. So does 128 MiB — the criterion is about n=1 and settles
nothing between them. **And no value below 336 MiB clears two such files**, so the
criterion cannot be extended to n=2 without moving the ceiling past a third of a gigabyte
per snapshot. 128 MiB was rejected on the table instead: there two 32 MiB files (64 MiB of
content, 168 MiB of arena) are refused, and refusing a 64 MiB tree is further from what an
operator expects than refusing a 98 MiB one. An earlier draft of this section presented the
n=1 criterion as the thing that chose 256 over 128; it does not.

It is not derived from the corpus, which would put it five orders of magnitude lower. The
corpus is the check that it refuses nothing real: the four defines buildable on the machine
this was measured on cost **888, 846, 846 and 544 bytes** (`cargo` and `cargo-r2` build the
same tree, which is why three numbers cover four defines). **That is 4 of the 45** files
matching `grep -rl '^state = ' --include='*.toml'` — a count of define files, including the
quickstart and dogfood ones and not only `spike/**/ops/`, rather than of distinct state
trees. The rest need tools this machine does not have, and what was measured is the
pre-state each `setup.sh` builds, not the tree after the operation has run.

Raising this value later is not the safe direction. Here a refusal is the good outcome, and
the alternative to refusing is the unreported death this ADR exists to remove; raising it
turns named refusals back into runs that may die unreported, and flips machine-visible
verdicts from UNKNOWN to PASS or FAIL.

## Consequences

- Four snapshots are live at once at the widest point, so a completed run's resident
  judgement data is bounded near four times the ceiling, plus the two trace arenas. The run
  that refuses may briefly hold more, for the node-growth reason above, and then exits.
- **`L0Plan` is not separately capped.** It borrows content slices from the two snapshots
  and holds one ~56-byte entry per judged pair, so the arena ceiling bounds the entry count
  and therefore bounds it too. The constant relating them is not measured here and is not
  claimed.
- The per-file cap keeps its own job and fires first for any single file over it:
  `readWhole` returns before the entry is appended, so the tree accounting never sees it.
- The shipped comment beside `max_state_file_bytes` carried two wrong numbers, both
  corrected here: "the crashed sequence holds three at once" (four are live, and
  `crashed_again` predates the comment by a fortnight, so it was wrong when written), and
  "bounds the largest single resident pair near 128 MiB" (192 MiB now, 217 MiB before the
  `readWhole` change).
- `spike/acceptance.sh` gains two legs driving the shipped constants; both are Linux-only,
  like the rest of that suite. The unit tests, which run on both platforms, carry the two
  things the legs cannot: how much the arena held at the break, and an all-empty tree.
