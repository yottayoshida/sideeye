# g4 — written BEFORE the sweep runs (2026-10-10)

Committed with the apparatus (#696), outside `artifacts-g4/` because `sweep.sh` refuses to
sweep a generation whose directory exists; moved into it with the results. g3's file of the
same name is the model.

Expected shape of `spike/unknown-rate/artifacts-g4/`:
- manifest.tsv: 50 rows = 20 B + 30 B2, the same rows as g3 (same corpus, same `since`).
- Wall rows (argv `wall:W…`, no engine run): B 13 + B2 11 = 24. Explored trials: B 7 + B2 19 = 26,
  each trial directory with a `launcher-rc` (26).
- apparatus.txt: banner `sideeye 1.5.0 (trace contract v18)`, two digest lines,
  `engine: release v1.5.0 sideeye-v1.5.0-x86_64-linux.tar.gz f836b7af… verified-against github-release-digest`,
  `head:` the merge commit of the apparatus PR, `machine: x86_64 x86_64`, `ci-run:` the workflow's run id,
  the image lines.
- `count.py check` after g4 → complete and `emit` pasted: OK, with g4's heading ending `on Linux x86_64`.

What differs from g3 besides the machine: the Debian packages of the day (neither Dockerfile pins a
snapshot), the kernel and the VM (Azure's Ubuntu runner against Docker Desktop's LinuxKit), and the
container runtime's defaults (AppArmor's docker-default on the runner). A difference between g3 and g4
is therefore not a difference of architecture alone, and is not read as one.

Verdict guesses (NOT a threshold; recorded so the guess is dated before the numbers):
- B: 2/7 UNKNOWN as in g3 — cookietool (`recording_run_failed`) and lbdb (`child_touched_state_dir`).
  Nothing in either refusal is architecture-specific.
- B2: 5/19 UNKNOWN as in g3, with one row most likely to move: unmass, whose `recording_run_failed`
  on g3 is a segmentation fault on arm64 (its NOTES.md). If it does not crash on x86_64 it may reach
  PASS or FAIL, and B2 reads 4/19.
- The walls are define-level facts recorded by the corpus (no engine runs): identical to g3 by
  construction, and printed under g4's heading for that reason only.

Decided before the results (owner, 2026-10-10):
- **Criterion 4's basis stays g3; Row 8 reads g4.** g4's B is recorded beside g3's and does not move
  criterion 4, whatever it reads. A g4 failing part 1 is still DESIGN §18 material: the kill-criteria
  review's Row 8 has no platform qualifier, and a sweep on another platform faces it on its own numbers.
  The threshold has two parts (`docs/unknown-rate.md`, "Threshold"): part 1, target-origin UNKNOWNs ≤
  1/7, and part 2, the overall per-trial UNKNOWN rate ≤ 50%. g3 holds part 1 at its edge when lbdb is
  filed as target-origin (1/7) and with room when it is not (0/7), and part 2 at 2/7. Part 1 is read with
  cookietool filed as g3 files it (define-budget) and lbdb either way, so one more target-origin UNKNOWN
  than g3 fails it; part 2 fails at 4/7 or more. If g4's B would fail either part, that is written in the
  threshold section of `docs/unknown-rate.md` and on #696; criterion 4 does not move on it, and a failure
  of part 1 reopens the kill-criteria review through Row 8. The page says so from this pull request,
  before the sweep.
- **The record is the first sweep that completes.** A sweep that exits non-zero is diagnosed, the cause
  fixed, and g4 swept again from the start; every run, completed or not, is listed in the results PR.
- **A SETUP_ERROR a Dockerfile change resolves** is resolved that way and g4 swept again from the start,
  both runs recorded (the page's rule: fix and re-run when the fix is available). Defines are not changed:
  their digests are shared with g3. A SETUP_ERROR no Dockerfile change resolves goes to exclusions.tsv
  with a reason that says it is g4's (x86_64) alone. A FAIL or an UNKNOWN is a result and is published.

Falsifiers: a manifest row count ≠ 50; an explored trial directory without `launcher-rc`; a `machine:`
line that is not `x86_64 x86_64`; a `head:` that is not the apparatus PR's merge commit; a `ci-run:` that
names a run of another workflow or of another commit.
