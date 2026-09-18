# 0073 — B2 is selected by a committed predicate and a keyed order, and measured with the released engine

Status: Accepted (2026-09-18)

## Context

`docs/unknown-rate.md` publishes one measurement of how often Sideeye reaches a verdict
on a target it has never met: the B-group, twenty Debian packages selected mechanically
and swept on 2026-08-16 by the v0.9.0 engine. Since then the engine moved — argv
operations, exec chains, child-process accounting, the thread rule, `--observe syscalls`
— and the seven B targets that reached an explore are no longer fresh: their refusals
are on the page, two of them motivated later work, and hnb has since reached a verdict
on a newer engine. #619 asks for a current reading, in two parts that must never be
pooled: the old sample re-measured on today's engine, and a new never-run sample.

The B-group's discipline is the part worth keeping — a predicate committed before the
list, the list committed before the numbers, funnel walls instead of substitutions. Its
predicate is not: `works-with::pim|db` on bookworm aimed at database-server tooling, and
the alphabetical head of that pool put nine of twenty behind the W2 wall. And its engine
was a build of the checkout at the sweep's HEAD, which was sound when a sweep took an
afternoon and is not when the selection must be committed days before the sweep on a
`main` that moves several times a day.

## Decision

1. **Three merges, not two.** The selection protocol and the target list merge first;
   the defines and the apparatus second; the swept artifacts and the numbers last. The
   B-group merged its list and its defines together; #619's acceptance condition 1 says
   no candidate may run before the list is committed, and authoring a define runs
   `preflight` against the candidate, so the list has to be a merge of its own.

2. **A predicate on Debian 13's debtags that asks for a state-changing command-line
   program in a first-table language**: `role::program`, `implemented-in::` in {c, c++,
   python, perl, ruby, php, haskell, java, ecmascript}, `use::` in {editing, converting,
   compressing, organizing, storing, synchronizing}, `works-with::` in the file-shaped
   families, `interface::commandline`, not daemon/x11/graphical/web. Its bias is
   published on the page rather than denied: partial tag coverage, no Rust (the
   vocabulary has no `implemented-in::rust`), no text-mode programs.

3. **The order is `sha256("<package>\t<key>")` ascending**, the key being the commit the
   v1.5.0 tag points at, written into `b2-order-key.txt` before the pool was generated.
   The alphabet is an order too, but the page already records what its head looked
   like. Choosing the key is a human act; what the key closes is reordering after seeing
   the list, and `count.py b2-selection` recomputes the order from the file.

4. **N is 30.** At least the twenty the issue asks for, and chosen from the first pool's
   funnel rate (7 of 20 explored) so that one trial is not expected to move the rate by
   a seventh. An expectation, stated as one; the funnel table measures it.

5. **Fresh is held by exact package name through an alias table, and by a wall for the
   rest.** `b2-exclusions.txt` carries every package the project has run, read or
   sealed; `b2-exclusion-aliases.tsv` maps every ledger spelling to its packages; the
   check holds the five machine-readable ledgers to that pair. A selected target the
   project met under a name the table does not map is wall **W0**, recorded — never
   replaced, and the table is not corrected after the fact.

6. **The engine is the released `v1.5.0` tarball**, pinned by tag, asset and the digest
   GitHub publishes in `engine-pins.tsv` (committed with the first merge); `sweep.sh`
   will fetch and verify it and mount it at `/work/zig-out` in place of a build, and
   `apparatus.txt` will record the pin beside the two digest lines it already carries
   (the second merge).

7. **One launcher, same name and arguments, two observation legs.** `bgroup.sh` will
   gain (the second merge) `preflight --twice`, a second `explore` under
   `--observe syscalls` when the first refuses with a `next_step` that names that mode,
   and `legs.tsv` binding each leg's report by sha256. The verdict is the last leg's; a second leg refused
   `syscalls_may_have_killed` is the mode's side effect, and the wall published is the
   first leg's. The B rows of `corpus.tsv` do not change — `count.py check` binds a
   completed generation's manifest argv to `launcher args`, so a new launcher name or a
   new argument on those rows would have broken g1's record.

8. **The generation is one: g3 covers B and B2.** Same engine, same images per group,
   separate tables, and a line under B's heading saying it is a re-measurement. No
   threshold is set from B2 before or after its number; B's g3 figures meet the frozen
   threshold as any B sweep does, and whether criterion 4's status moves on that is the
   owner's dated ruling in `PRD.md`, not a sentence written before the number exists.

## Alternatives Considered

- **Re-run the B-group only.** Answers "did the engine catch up with its own inputs",
  which the A-group already answers at 5.6%. Rejected by #619 itself.
- **The same predicate on trixie.** 52 packages, the same DB-server head. Rejected: the
  issue asks for the same discipline, not the same predicate, and the walls it produced
  were the predicate's, not the engine's.
- **Alphabetical order, or a random seed chosen by hand.** The first has a recorded bias;
  the second leaves room to try seeds. A key that is a public commit id chosen before the
  pool exists leaves the least room, and the ADR says how much is left.
- **A HEAD build, as g1 and g2.** Between the list's merge and the sweep, `main` will
  carry engine changes; "the engine chosen before the sweep" has to be a thing that does
  not move. The last five dogfood runs already used the tarball.
- **A new launcher for B2.** Cleaner in isolation; it would have left the B rows on the
  old protocol or rewritten rows whose g1 manifest is frozen. Same name, derived defines
  directory, image chosen by group in `sweep.sh`.
- **Authoring time inside each define directory.** The manifest hashes those directories,
  and the `final` event lands after the sweep. One file outside them.
- **Re-checking the old walls.** W1 is an install that failed, W2 is state on a server or
  a device, W3's two rows are a GUI application and a transitional metapackage. None
  depends on the engine; each is restated with its ground in the results, not re-run.

## Consequences

- Three pull requests, in a fixed order, with the first-parent history as the proof.
  Nothing in the second or third may edit the list.
- The published B2 rate is a property of the predicate as much as of the engine, and
  the page says which walls are which. A W0 row is a defect in the alias table and is
  published as one.
- A second observation leg changes what some targets do (the README names the
  processes `--observe syscalls` kills); the tables print both legs so a reader can see
  where the mode, not the target, decided.
- The old B rows gain a `--twice` answer and possibly a second leg they did not have in
  g1; the first leg is the like-for-like comparison, and the results say so.
- `count.py` grows a group and a mode; `sweep.sh` learns to run a release; the
  acceptance suite's pinned message for `gen-group-unknown` changes with the group list.
