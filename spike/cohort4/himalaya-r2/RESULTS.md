# himalaya-r2: FAIL through the declared checker, reproduced

## The verdict

**FAIL, 1 of 3 explored worlds, `oracle_verified: true`, single
process.** Two runs, and the report fields that carry a judgement are
identical across both: verdict, exit code, oracle verification, world
count, violation count, process count, the crash point, and the violated
invariant. The eight fields that differ are the minted filename, which
the checker is deliberately name-agnostic about, and the per-run work
paths.

The violated invariant is **the checker (L2)**, not the engine's
built-in atomicity invariant, and the report carries
**`checker_earliest`** (#231, ADR 0020). Under this cohort's frozen
claim rule that is what a criterion-1 candidate is:

> A criterion-1 candidate is a run whose `checker_earliest` exhibit
> exists ... and the exhibit named there is the claim's exhibit. An
> L0-only FAIL is a precision-limit observation, recorded and never
> claimed.

The exhibit replays: `run1/replay-transcript.txt`, "the case
reproduced".

## What the crash leaves

The kill lands at crash point 2 of 2, **after the destination is opened
and before anything is written to it**:

    after  open(<store>/Archive/cur/<minted>:2,S)
    before write(<store>/Archive/cur/<minted>:2,S)

and the checker fails through leg D:

    leg D: the copy is present but its bytes are not the source's
           (0 bytes on disk against 307 in the source)

A message file exists at its final path in the target folder with no
content in it. That is the window `proposals.md` named before the engine
ran, and it is there because `messages copy` is the one io-maildir arm
that does not stage: it mints the name, builds the final path, and fills
the file in place.

## What the declaration predicted, and what the run did

`proposals.md` was committed before the engine touched the target. Every
declared reading held:

| Declared | Measured |
|---|---|
| two crash points plus the un-killed baseline | 3 worlds, crash points 2 + 1 baseline |
| single process, `oracle_verified: true` | both, in each run |
| a FAIL through leg D, not a PASS | FAIL, leg D, 0 bytes against 307 |
| the report carries `checker_earliest` | present, invariant "the checker (L2)" |

Nothing in the declaration was adjusted after the fact. The one thing it
did not predict is in the metadata line, disclosed and unjudged: one
`fchmod` outside the judged state (#121, #190).

## What is not claimed here

- **No upstream contact.** Each report is its own owner-approved gate,
  and the freeze's Reporting section adds a precondition this finding has
  not met yet: measure the recovery paths that exist outside the tool and
  the conditions under which they do not apply. For himalaya that is the
  other side of the sync, and it is unmeasured. That is the one
  measurement still standing between this candidate and a report.
- **The stock reproduction is done, and it turned the toml's argument
  into a measurement** (`stock-reproduction.txt`). No shim, no engine, no
  seccomp, no `/etc/ld.so.preload`, no interposer: the stock binary under
  strace with one injected signal. Stock copies with a single
  `copy_file_range` of the whole 307-byte message, not the read/write
  loop the define measured, and the window is there anyway: the kill
  leaves a 0-byte message at its final path in the target folder,
  himalaya lists it as an ordinary envelope, and `message read` on it
  fails. The apparatus decided what the engine could see. It did not make
  the finding.
- **Novelty was cleared at selection time**, not here
  (`../novelty-prescan-himalaya.txt`, rule 14): 51 terms, controls green,
  nothing on the tracker describing this write shape. That is evidence a
  known shape was looked for and not found, which is all a clean scan can
  be.

## The apparatus, and what it does not buy

`no-accel-copy.so` answers `copy_file_range`, `sendfile` and
`sendfile64` in userspace so the syscall is never made. It exists
because r1 refused: the seccomp profile made those calls *fail*, and the
oracle refuses on a call being *observed*. The apparatus decides what the
engine can see. It does not create the kill window, and it does not
touch the checker, the property, the fixtures or the argv, all of which
are r1's byte for byte.
