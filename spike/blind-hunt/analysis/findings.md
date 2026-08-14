# What the blind hunt found — topydo 0.14, exploration at Seal B

The exploration ran from the Seal B merge commit `5a034aff` in a clean worktree,
inside the pinned container, on 2026-08-14. `verify-seals.sh a21b0933 5a034aff
<run-manifest> <sealed-reports>` prints **ALL SEAL CHECKS PASSED (R1 audited)** —
the declaration's commit order, its match to the sealed selection, the
append-only ledger, and the run's own head/clean-tree claim are all machine-checked.

Everything in the *Declared results* section below came out of the search from an
invariant written before anything about this target's crash behavior was observed.
Everything in *Analysis* is human work done **after** the seal, following the
findings into the recovery path — it is not part of the automated claim, and this
file keeps the two apart on purpose.

## Declared results — the automated half

| operation | verdict | worlds violating / explored | earliest window |
|-----------|---------|-----------------------------|-----------------|
| add, append, del, dep-add, dep-rm, depri, postpone, pri, sort, tag | FAIL | 1 of 3 | after `open(todo.txt)`, before `write(todo.txt)` |
| do | FAIL | 2 of 5 | after `write(done.txt)`, before `open(todo.txt)` |
| revert | FAIL | 5 of 8 | after `open(done.txt)`, before `write(done.txt)` |
| ls | PASS | 0 of 0 | — (read-only recording, zero state-changing operations, as declared) |

Twelve of the thirteen declared operation forms produced a counterexample; the
one declared read-only form recorded nothing and passed. Every FAIL carries a
saved case (`cases/`), a machine-readable report (`reports/`) and a reproduce
line (`transcripts/`). The oracle agreed on every operation in every run, and
the checker was falsified before each run — no verdict here rests on a checker
that could not fail.

The mechanism the reports name is the same for the ten single-file operations:
the active list is rewritten in place, and a crash between the open and the
write leaves it empty. `do` and `revert` fail across the file pair instead — the
task is in neither file, or in both.

**The saved cases replay with nothing else installed.** In a fresh pinned
container, `sideeye replay analysis/cases/<op>.json` reproduces the
counterexample for every case tried (add, do, revert, sort, tag): exit 1,
verdict FAIL, `this run is a replay; the case reproduced`. No target build
step, no recipe — the define's absolute paths resolve inside the image, which
is what the sealed selection predicate's resolution leg was a structural proxy
for. This is the property the timewarrior finding could not offer (`#82`: a
recipe bound to a built binary, not a CI-resident case).

**What this half does *not* say.** Ten of the twelve ran under the declared
`backup_count = 0` configuration (declaration.md, "The backup decision"), so
they measure the crash surface with topydo's own safety net switched off by us.
`do` and `revert` ran with backups at their default. A finding's weight depends
on what recovery exists, and recovery is exactly what the declaration said it
would not check — hence the analysis below.

## Analysis — done after the seal, not part of the blind claim

Following the FAILs into the documented recovery path (`revert`, whose backups
are on by default with `backup_count` 5) gives a sharper picture than the
truncation window itself. Measured across every crash point of `add` and `do`
under the **default** configuration (`recovery-matrix.sh`,
`transcripts/recovery-matrix.txt`):

- **The data is recoverable — but only through the numbered form.** `revert 1`
  restored the intact pre-crash state in every case tried, including the worlds
  where the active list had been emptied (`force.sh`). The backup store holds
  what was lost and `revert ls` lists it.
- **The no-argument form, which is what the docs put first, does something
  else.** For `add`, in **3 of its 5 crash worlds**, the crash left the
  pre-existing task intact — and running plain `revert` then **deleted it**,
  exiting 0 with `Reverted to state before: add seed-task`: a command the user
  had not pointed at. In 2 worlds it refused (`No backup was found for the
  current state of …`), also exiting 0. For `do`, the same command behaved
  correctly in 6 worlds and refused in 2.
- **Why the older command gets undone.** After the interrupted write the active
  list is byte-identical to the snapshot taken by an *earlier* command, so the
  search for "a backup corresponding to the current state" matches that earlier
  entry, and reverting it rolls the file back past work the crash never touched.
- **The two documentation sources disagree about this case.** The `revert`
  help text says it "will revert to the latest backup available, provided that
  this backup matches the current state of the todo file" and that topydo "will
  refuse to revert, if any changes to todo file were made … after the latest
  backup". The documentation tiddler says instead that topydo "searches for a
  proper backup … It won't do anything if … it couldn't a find backup that
  corresponds to the current state." The observed behavior follows the second
  reading; under the first it should have refused. The consequence of the
  difference, after a crash, is a deleted task.

Not silent, to be precise: the message does name the older command. It is
nonetheless a success-shaped exit 0 in a situation the help says is a refusal,
and the outcome is data the crash had left alone.

## Honest scoring against §17's first condition

- **Declared before the bug was known:** yes, and machine-checkable — the
  checker's commit precedes the first crash measurement in the pushed history,
  and verify-seals recomputes the target selection rather than trusting it.
- **Found by the search, not by a human hypothesis:** yes for the crash windows
  above. The recovery behavior in *Analysis* was reached by a human reading the
  findings afterwards; it is reported as analysis, not as an automated find.
- **Novelty — checked on 2026-08-14, after everything above was merged**
  (the ledger records the search terms, the positive control, and the bodies
  read). Split verdict: the crash-window destruction of the active list is
  **not novel as a phenomenon** — `topydo/topydo#318` (open since 2023-10,
  no comments) reports the same failure surface driven by a disk-full write;
  what this campaign adds there is the mechanism and a replayable
  counterexample, not the discovery. The recovery misfire — plain `revert`
  after a crash undoing an *older* command and deleting data the crash left
  intact, with the two documentation sources contradicting each other on the
  matching rule — **was not found anywhere in the tracker** and is novel as
  far as that search can see; it is also the finding that came from post-seal
  human analysis rather than the blind search, and both halves of that
  sentence belong in any claim built on it.
- **These were high-risk blind targets, not the §18 average-target
  calibration** (candidates.md) — that calibration stands on timewarrior and is
  not re-claimed.
