# Cohort 4, the probe stage: what each target's slot is worth

Engine-free throughout: normal executions only, no kill, no crash, no
checker, so nothing here observes a failure of any target and the
provenance gate is untouched. The plans these runs execute were frozen in
`../PROTOCOL.md` before any of them ran (#245, main `5eef5957`).

| Step | Outcome | Transcript |
|---|---|---|
| Drills re-run under this image | 0 failures in both cohorts' sets | `drills-under-image.txt` |
| Positive control | split, as required | `positive-control.txt` |
| himalaya, bare (falsification) | both forecasts fired | `himalaya-bare.txt` |
| **himalaya, apparatus** | **9 of 9 conditions pass** | `himalaya.txt` |
| unison, bare (falsification) | both forecasts fired | `unison-bare.txt` |
| **unison, apparatus** | **8 of 9; determinism fails: named wall** | `unison.txt` |

Every transcript ends with a verdict manifest (`check-transcript.sh`),
which compares the verdict names that were emitted against the names the
plan requires. A probe that judged fewer conditions than it claims now
fails mechanically instead of reading as a clean green; the accident that
bought that check is in the BUILDLOG.

## himalaya: a slot worth spending

The frozen operation is `maildir messages copy`, the one io-maildir arm
that fills a message at its final path rather than staging it. Under the
declared apparatus (libfaketime and `pin-getpid.so` on the target
invocations, the container under `seccomp-enosys.json`) all nine
conditions pass:

- Two runs two seconds apart leave **byte-identical** state roots. The
  minted entry name is `1767225600.#0M0P4242.<host>:2,S` in both, which is
  the apparatus visible in the artifact: frozen clock, pinned pid.
- **Condition 8 passes**: every in-root mutation the kernel performed also
  passed through a function the interposer sees.
- **Condition 9 counts 2 kill points** (one `open`, one `write`) inside
  the state root. Not the papis shape.
- The copy runs on the libc read/write path: the dedicated strace shows
  0 successful `copy_file_range`/`sendfile` of 3 attempts, the rest
  answered ENOSYS by the profile.

The bare falsification is what justifies that apparatus rather than
assuming it: without it the two runs split on the minted name (clock and
pid fields visibly differing), and the copy **succeeds** through
`copy_file_range`, which the shim cannot see. Both are recorded in
`himalaya-bare.txt` before the apparatus was used once.

## unison: a named wall, bought for one transcript

Eight conditions pass, including the two the target was most likely to
fail. Condition 8 is clean: with the seccomp profile landing the copy
stub on its read/write fallback, **every** in-root mutation is
interposable (link 4/4, open 21/21, rename 3/3, unlink 8/8, write 26/26,
none unmatched). Condition 9 counts **62** kill points: a rich interior,
exactly the shape the slot was chosen for. The tool's own read-back works
non-interactively, and a re-run on the synced result reports "Nothing to
do: replicas have not changed since last sync."

**Condition 5 fails.** Two runs of the frozen operation, from the same
restored pre-state, do not leave byte-identical roots: two archive files
and the fingerprint cache differ, by 4 to 8 and 19 bytes. That is the
nondeterministic-writer class, recorded at probe time, and it costs no
define, which is the entire point of running probes before defines.

`unison-clock-diagnosis.txt` is the bisection behind it, and it corrects
the frozen plan on two points rather than confirming it:

1. **The plan's clock apparatus had to be re-plumbed, and the correction
   is recorded rather than smoothed over.** Applied to the whole harness,
   libfaketime made the pre-state's mtimes equal the frozen instant as the
   target reads them, which armed unison's own conservative guard
   (`fileinfo.ml:243-249`: if a file's mtime is the current second, sleep
   one second and call it changed), and libfaketime then scaled that
   one-second sleep by the frozen speed. strace caught it as
   `clock_nanosleep(CLOCK_REALTIME, {tv_sec=9223372036})`: a wait that
   cannot end. Applied to the target only, the same apparatus is harmless.
   The apparatus was breaking the measurement, not the target.
2. **The residue is not the term the freeze forecast.** The freeze named
   the directory inode inside `freshDirStamp` as the un-coverable one.
   Measured, the directory inodes, and the propagated file's inode, come
   back identical on both runs, as does its mtime once `-times=true` is
   added. Clock, pid, mtime and inode are each eliminated by a separate
   measurement, and the archive still differs. **The residue is
   unattributed, and is recorded as unattributed.** Four hypotheses were
   tested; a fifth would be a guess, and the probe's verdict does not
   depend on it.

`-times=true` appears in the diagnosis only to answer the question an
owner would otherwise have to guess at: whether amending the frozen argv
would buy determinism. It does not: the archive still differs with it.
So the wall stands on its own, and no amendment is proposed.

## What this leaves the cohort

himalaya has a clean probe and goes to its define next. unison is a
recorded wall, so the measured cohort is one target, an outcome the
freeze's own rules produce, not a decision taken here. The owner declined
a single-target slate at selection time; that a probe wall has since
reduced it to one is a fact for the record, and the standing #201
tripwire fires on the cohort's outcome, not on this transcript.
