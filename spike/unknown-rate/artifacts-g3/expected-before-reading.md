# g3 — written BEFORE the sweep's results are read (2026-09-18)

Expected shape of `spike/unknown-rate/artifacts-g3/`:
- manifest.tsv: 50 rows = 20 B + 30 B2 (corpus rows with group in {B,B2}, since ≤ g3).
- Wall rows (argv `wall:W…`, no engine run): B 13 + B2 11 = 24. Explored trials: B 7 + B2 19 = 26.
- apparatus.txt: banner `sideeye 1.5.0 (trace contract v18)`, two digest lines, `engine: release v1.5.0 sideeye-v1.5.0-aarch64-linux.tar.gz f81c58a3… verified-against github-release-digest`, `head: 0b9e5e68…`, image lines incl. sideeye-ur-extra and sideeye-ur-b2.
- Every explored trial dir: preflight.txt, legs.tsv (1 or 2 rows), report-wrappers.json, report.json (+ report-syscalls.json when leg 2 ran), transcript*.txt, launcher-rc.
- B2 preflight --twice exits: 14 × 0, 5 × 2 (bs1770gain, otf2bdf, unmass, pacpl, mail-expire), as in authoring — unless the sweep image differs from the authoring container (same image, targets baked in: expect equal).
- B2 verdicts, my guesses (NOT a threshold; recorded so the guess is dated before the numbers):
  - unmass: UNKNOWN (segfaults on every archive; expected in NOTES).
  - bs1770gain: UNKNOWN in wrappers (mkdirat refusal) → leg 2 asked? unknown.
  - otf2bdf: authoring said "stdio → 掃引で 2 脚目" — expect leg 2 to run for it.
  - the rest: mostly PASS or FAIL; no number guessed.
- Old B, g1 → g3: g1 had 1/7 UNKNOWN. Verdicts may move (engine 0.13.0 → 1.5.0); each row is compared leg-by-leg in the prose, never pooled with B2.
- `count.py check` after `generations.tsv` g3 → complete and `emit` pasted: OK, `1 generation(s) held to a pinned release`.
- Second legs: recorded only where leg 1's next_step opens with the observe_syscalls sentence. count.py refuses any other shape.

Falsifiers: a manifest row count ≠ 50; a B2 explored trial without legs.tsv; a preflight exit that differs from authoring (would mean the sweep environment ≠ authoring environment — record it, do not "fix" the define).
