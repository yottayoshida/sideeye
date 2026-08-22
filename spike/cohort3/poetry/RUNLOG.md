# poetry (cohort 3, target 4) — run log and ruling

## Timeline (all 2026-08-22)

1. The define merged (main `75b3d19`) **after one recorded reversal**:
   R1's novelty-shape finding forced a recovery-shaped re-scan, which
   surfaced python-poetry/poetry#1196 / PR #6753 and upstream's own
   test pinning bare-`poetry lock`-fails-on-a-broken-lock as intended;
   the owner's chain ruling (leg R = the prescription, then the
   documented `--regenerate`, then re-check) and the moved prospect
   (the manifest, not the lock) are frozen in `proposals.md` and
   BUILDLOG. Mini-seal verified: the define's first-parent
   introduction stands on main before any artifact.
2. **Three explores, identical verdicts.** Run 0's cases were lost to
   an operator error (the engine's `--work` default landed inside the
   discarded container; transcript and report were retained in the
   session workspace and match run 1 on verdict, world counts and the
   full earliest block). Run 1 is the committed artifact set
   (`explore-transcript.txt`, `report.json`, `cases/000001.json`,
   `--work` mounted). Run 2 reproduced run 1 exactly on every compared
   field: verdict, violations, explored, crash_points, and
   earliest.{crash_point, invariant, subject, observed}.

## The verdict

**FAIL, 2 of 5 worlds (4 crash points + baseline) — and the earliest
violating world is L0-only, so under the frozen claim reading this run
is recorded and not claimed.**

The world map, read off the committed transcript:

- **Crash point 2** (after `open(poetry.lock)`, before its single
  `write`): the empty lock. **L0 red** — the file holds neither the
  old nor the new content — and **the checker heals it green** at
  chain step 2, with poetry's self-prescribing step-1 failure ("The
  lock file does not have a metadata entry. Regenerate the lock file
  with the `poetry lock` command.") now observed **in a real crash
  world**, not only in drill surgery. This world is violating world 1
  of 2, and the run's earliest — invariant "built-in atomicity (L0)".
- **Crash point 3** (between the lock write and the manifest open):
  the between-writes state. The checker heals it at chain step 1 —
  the prescription working, exactly as declared. Not a violation.
- **Crash point 4** (after `open(pyproject.toml)`, before its write):
  the empty manifest. **The whole documented chain fails**
  (config-invalid: name/version gone; step 1 rc 1, step 2 rc 1) — the
  declared candidate shape, checker-red, violating world 2 of 2. The
  user-authored manifest is destroyed and nothing poetry documents
  brings it back.

Every world-level declaration in `proposals.md` was confirmed by the
engine: A heals at step 1, the empty lock heals at step 2, the empty
manifest chain-fails. What the declaration missed is one level up.

## The reading (frozen before any explore; binding here)

The cohort rule (PROTOCOL, restating cohort 2's frozen text): *a
criterion-1 candidate is a run whose saved case — the earliest
violating world — has the declared checker as its violated invariant;
an L0-only FAIL is a precision-limit observation, recorded and never
claimed.* The earliest violating world here is the empty lock: L0-only
(the checker healed it). **Therefore: no candidate. The checker-red
manifest world at crash point 4 is real, recorded, and not the
earliest.**

The structure that decides this is the write shape itself: `poetry
add` writes the lock first, so the lock's mid-write world always
precedes the manifest's, and L0 fires there whenever a file is caught
between truncate and write. Under this define, no run of this
operation can put the checker-red manifest world earliest. The
declaration ("that red is the candidate shape") predicted the world
correctly and its candidacy wrongly — it read the checker column and
missed that L0's independent red at an earlier crash point owns the
claim exhibit under the frozen earliest-case rule. Recorded as the
miss it is; the rule did exactly what it was frozen to do (the hg
73/107 lesson, applied by machinery this time).

## What the verdict adds

- **Poetry's lock contract, measured in real crash worlds, holds
  through the documented chain**: both lock-damage worlds came back
  green through poetry's own commands (step 1 for staleness, step 2
  for destruction). This is the chain ruling validated by the engine,
  not just by surgery.
- **The manifest wound is real and now engine-measured**: crash point
  4 destroys user-authored `pyproject.toml` and the whole documented
  recovery chain fails on the result. It sits in the record as a
  precision-limit-adjacent observation (checker-red world, non-
  earliest) — the same in-place truncate-and-write the formatter half
  died of, here as a side effect of dependency management.
- **The stale prescription is now observed under crash**, not only in
  drills: check names `poetry lock`, `poetry lock` fails and names
  itself. Upstream-report material (message defect), behind the
  standing per-report owner gate; the stock-reproduction rule applies
  to any conversation about the manifest wound.
- **A revision question, deferred to the owner, not part of this
  record**: an operation whose only in-root write is the manifest
  (e.g. `poetry version patch`, if its write shape measures that way)
  would make the manifest world the earliest and the claim reading
  would then see the checker-red world first. That is a new
  target-directory revision with its own frozen define if the owner
  wants it; nothing in this run's reading changes either way.

## Bounds

Assisted provenance, as the whole cohort. `oracle_verified: true`;
python-discovery forks stayed within the oracle's accounting (8 other
processes observed, none touched the state; no refusal — the probe's
forecast risk did not materialize). Not tested: power loss, torn
writes, concurrent processes, appended tails (the report's own
line). Timeout apparatus reading was frozen in proposals.md and was
not needed: no red names a timeout.
