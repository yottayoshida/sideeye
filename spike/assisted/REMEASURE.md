# Re-measurement after the engine gaps closed (#121 / #122)

2026-08-15. The first cohort (`RESULTS.md`, sealed record — deliberately
unchanged) left four targets — stow, devtodo, buku, pass — short of a
verdict or short of a verified one (calcurse alone had a verified
verdict). #122 (symlink class, contract v9) and #121 (option b:
ownership/permission recorded-only) merged today; this file records the
same committed defines, re-run unmodified, against the new engine. It is
an assisted record, never blind, same as everything under `assisted/`.

## Apparatus identity

- Engine: `sideeye 0.7.0 (trace contract v9)`, built from main `647acbf`
  (`zig build -Dtarget=aarch64-linux-gnu`), run from `/work` exactly as
  the cohort ran. The version banner, the container's target versions,
  the oracle path, and the image ID (`d27e30513847` — the cohort's image,
  not rebuilt) are captured in `apparatus-remeasure.txt` beside this
  file, from the same container the runs used; "built from `647acbf`" is
  the one apparatus claim only this sentence carries.
- Every run: the committed `<target>/ops/explore.sh`, verbatim, with
  `--oracle /usr/bin/strace` (strict; no `--allow-unverified` anywhere —
  the transcripts carry real `agreed on N operations` lines, which the
  unverified path cannot produce) — the acceptance criterion #121/#122
  named. Raw exit codes were read in the driving session before any
  pipe; the committed evidence of each verdict is the transcript's own
  verdict block, and of each replay the `the case reproduced` line (a
  reproduced FAIL is exit 1 by the exit-code contract).

## The table

| Target | First cohort | Now | Window | Replay |
|--------|-------------|-----|--------|--------|
| stow | UNKNOWN `symlinkat` | **FAIL 2/5, oracle agreed on 4 ops** | after `unlink(target/sub)`, before `mkdir(target/sub)` — the fold symlink is destroyed before the real directory exists; package A's files unreachable (checker and built-in L0 agree) | rc=1, reproduced |
| devtodo | UNKNOWN `fchmodat` | **FAIL 6/8, oracle agreed on 7 ops** | after `open(.todo)`, before `write(.todo)` — the XML database is rewritten in place through truncation; crashed content is neither old nor new (checker: not well-formed / GraceNote gone) | rc=1, reproduced |
| buku | strict UNKNOWN `fchown`; unverified FAIL 2/22 (suspended in the #120 scoring) | **strict FAIL 2/22, oracle agreed on 21 ops** — the question re-posed fresh per the scoring, and the same torn-db answer came back VERIFIED (`fchown x1` observed and excluded, named in the report) | between two `write(bookmarks.db)` — neither old nor new | rc=1, reproduced |
| calcurse | FAIL 1/11 verified — but its saved case was contract v8, dead under v9 | **FAIL 1/11 again, oracle agreed on 10 ops**; case re-recorded under v9 | after `open(d/apts)`, before `write(d/apts)` — the interrupted purge truncates `apts` | reproduced (FAIL) |
| pass | UNKNOWN `child_process_detected` (exec) | UNKNOWN `child_process_detected` — unchanged, as the control should be: #123 is untouched (`pass/control-remeasure-transcript.txt`) | — | — |

(The Replay column's "reproduced" is each replay transcript's own
`the case reproduced` line; a reproduced FAIL is exit 1 by the
exit-code contract.)

All four saved cases embed `contract_version: 9` and tracked
`/work/spike/assisted/<t>/ops/` paths; each replay above ran in a fresh
container over a fresh state root from the committed case file. Artifacts
for the four verdict targets: `report-remeasure.json`,
`explore-remeasure-transcript.txt`, `cases-remeasure/000001.json`,
`replay-remeasure-transcript.txt`; the pass control's record is its
transcript alone (no case exists to save from a refusal).

## What this changes in the #118 decision material

The #120 scoring's harsh axis — drivable-slice discovery value — was
1.5/5, and its binding constraint was named as the judge's reach. The
reach question is now measured instead of forecast: **four of the five
committed defines reach a verdict, all four verdicts are
replay-confirmed counterexamples, and the fifth (pass) remains blocked
by exactly the issue (#123) that was deferred as too heavy.** Question
quality was already 5/5; what the re-run adds is that the questions,
once the judge could reach them, all had answers. The VALUE score is the
owner's to re-assign, not this file's — what belongs here is only that
the constraint the 1.5/5 blamed is gone for 4 of 5, at the cost of two
engine PRs in one day.

Two review forecasts held — the second not at the target it named: R2 of
#122 predicted stow would FAIL with an L0 `missing` at the unfold window,
exactly as measured (and the L2 checker agreed). R2 of #121 predicted the
restore-flattening note would matter most where no metadata syscall fires
and named buku — buku's strict run in fact shows `fchown x1`, while the
no-syscall case turned out to be stow and calcurse; the general rule (the
sentence rides both note branches unconditionally) is what actually did
the work.

## Honest limits

- Novelty is deliberately unchecked for all four findings (no tracker
  search — a separate step, same as the cohort rule).
- The first stow run happened in a container whose `--rm` discarded the
  saved case; the run was repeated in a single session to harvest it, and
  both runs returned the identical verdict and window. Determinism did
  the recovery work; the slip is recorded anyway.
- The old buku artifacts (`report-unverified.json`, `cases/000001.json`
  at v8) are superseded by the strict v9 run but left in place: they are
  the cohort's record of what a suspension looked like.
- The engine still reports its version as 0.7.0; the version bump rides
  the next release ceremony, and this file names the engine by commit for
  that reason.
- pass's gpg key setup in the control run was best-effort (`|| true`);
  the refusal fires at exec detection before any gpg semantics matter.
  The committed control transcript's refusal text can be compared with
  the cohort's `report-strict.json` message directly — both name the
  image replacement.

## v10 re-record (2026-08-15, #123)

Contract v10 (self-exec chains judged; `shim_ready` seq now carries the
continuation base) makes the v9 saved cases refuse as
`case_no_longer_applies` — the #82-class cost the bump priced in. The four
committed defines were re-run unmodified in the cohort image with the
strict oracle, engine 0.8.0/v10 built from this branch: **identical
verdicts and oracle agreement to the v9 remeasure** (buku FAIL 2/22
agreed-21, calcurse FAIL 1/11 agreed-10, devtodo FAIL 6/8 agreed-7, stow
FAIL 2/5 agreed-4). Artifacts: `<target>/explore-v10-transcript.txt`,
`<target>/cases-v10/000001.json`, `<target>/replay-v10-transcript.txt` —
each replay ran in a fresh container and printed `the case reproduced`
(exit 1). The v9 artifacts stay in place as records, the same arrangement
v8 got when v9 superseded it.

Two replay trips worth recording for the next fresh checkout: the state
root must exist before `replay` (path resolution refuses otherwise), and
buku's replay needs the launcher's environment (`XDG_DATA_HOME` pointing
into the state root) — the cohort's own R1 lesson that the toml does not
carry the environment, now measured on the replay side too: without it
the fresh recording counts zero in-scope operations and the case refuses
honestly as `case_no_longer_applies`.
