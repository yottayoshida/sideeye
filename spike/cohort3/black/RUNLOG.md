# black (cohort 3, target 2) — run log and ruling

## Timeline (all 2026-08-22, each step's evidence committed where named)

1. The define merged (main `413cdb2`, its R1 having corrected the
   torn-file reading to name leg E for the engine-reachable tear —
   the empty file — before the freeze).
2. **The first explore returned FAIL** — the cohort's first full
   crash-world verdict: 1 of 3 explored worlds, single process,
   `oracle_verified: true`. Two further runs reproduced it identically
   (same crash point, same invariant, same case shape); the committed
   `explore-transcript.txt`, `report.json` and `cases/000001.json` are
   the third run's consistent set.

## The verdict, read under the protocol's frozen rules

**FAIL, 1 of 3 worlds; the earliest (and only) violating world is
crash point 2 of 2 — after `open(probe.py)`, before `write(probe.py)`
— exactly the engine-reachable tear the define's R1 predicted: the
truncating open lands, the write never does, and the file is empty.**

- The violated invariant is **"built-in atomicity, and the checker"**
  — the combined form: L0 sees a file holding neither the old nor the
  new content, and the checker's leg E sees a file that parses (an
  empty module) but is a different program from the frozen source. The
  drill `E-red-empty-file` had rehearsed this exact world.
- Under the frozen claim reading this is **a candidate shape** — the
  earliest case's violated invariant names the declared checker; only
  L0-only FAILs are excluded.
- What it means in user terms: kill `black --no-cache file.py` between
  its truncating open and its single write, and the user's source file
  is destroyed — black's in-place rewrite has no temp file, no rename,
  no recovery.

## The novelty gate closes the candidate (recorded search, 2026-08-22)

The standing gates require a recorded tracker search with a positive
control before any claim. The search (`gh api search/issues`,
repo:psf/black; positive control "cache" = 192 hits): "atomic" 6,
"data loss" 3, "truncated" 6 — and among them **psf/black#2479, open
since 2021-09-06: "black in-place reformat wipes or corrupts target
when disk is full."** The failure surface is the same non-atomic
in-place write; the trigger differs (ENOSPC there, a crash here — the
same split as topydo#318 in the blind campaign). The thread's
maintainer converged on the temp-file-plus-rename fix in 2021, and
**PR psf/black#5207 ("Write formatted files atomically to avoid
corruption on write failure") has been open since 2026-07-01** — after
the current stable (26.5.1, 2026-05-18) shipped, so the measured
behavior is the current release's real behavior, with the fix in
flight.

**Ruling: the phenomenon is known upstream; the candidate cannot serve
criterion 1 as a novel find.** What this cohort adds to the public
record — a deterministic crash-window mechanism, an exact kill point,
and a replayable case for a defect the upstream thread knew only
through disk-full accidents — is recorded here; whether any of it is
offered to the open upstream thread is a separate, owner-gated
decision, and nothing has been filed.

## What the verdict proves anyway

This is the sweet-spot thesis measured: on the most-used Python
formatter, at its current stable, the engine went from a frozen define
to a checker-red crash-world verdict in three worlds and a few minutes
— finding exactly the defect class the project's own tracker took from
2021 to 2026 to converge on fixing. The tool found the right thing;
the thing was already known. The cohort's search for a *novel*
candidate continues down the order.

## A fact the next target inherits

The #2479 thread's 2026-07-01 comment surveys other formatters:
"rustfmt, Prettier, yapf, and autopep8 all just write directly with no
fallback." **rustfmt — this cohort's target 3 — has its direct
in-place write publicly named in that thread.** Its novelty gate must
be checked against its own tracker before its define is written; the
probe already measured the same single-truncate-and-write shape
(`O_WRONLY|O_CREAT|O_TRUNC`, `../probes/raw/rustfmt.strace`).
