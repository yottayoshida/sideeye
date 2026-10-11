# Results — 2026-10-11, #815: a world held to the recording's operations

Two engines built from this repository for aarch64-linux-gnu.2.28, run in Docker on one Mac:
**before** is #852 (the recording starts from the rebuilt state, no comparison of a world's
operations); **after** is #852 plus ADR 0119's comparison.

## #815's shape

`apparatus/set-order.sh`, in the `sideeye-spike` box: `python3` writes `alpha` and `beta` in the
order of a set (`PYTHONHASHSEED` random), and a checker refuses `alpha` without `beta`. Four crash
points; worlds 2, 3 and 4 are compared, world 1 has nothing before its crash point.

| engine | runs | PASS | FAIL | UNKNOWN `kill_did_not_land` | record |
|---|---|---|---|---|---|
| before | 30 | 7 | 23 | — | `transcripts/set-order-before.log` |
| after | 120 | 4 | 8 | 108 (at world 2: 59, 3: 36, 4: 13) | `transcripts/set-order-after.log` |

Before, 6 of the 7 PASSes had a compared world writing the other order (all but run 24), and 4 of them
(runs 1, 12, 15, 16) had recorded `alpha` first, the order the checker fails in.
After, every run that reached a verdict had worlds 2–4 in the recording's order (each log line lists
the recording's opens and each world's): the 4 PASSes recorded `beta` first, an order in which the
checker holds, and the 8 FAILs recorded `alpha` first.

## Targets judged before

`apparatus/Dockerfile.targets` (Debian trixie: stylelint 17.15.0 on Node v20.19.2, doctl 1.177.0,
virtualenv 20.31.2) and `apparatus/targets.sh`, with the defines of
`spike/dogfood/2026-10-09-followups-3/` (stylelint under `UV_THREADPOOL_SIZE=1`, doctl under
`GOMAXPROCS=1` and `--observe supervised`) and `spike/dogfood/2026-09-26-threads-gate-virtualenv/`
(no checker). `--oracle /usr/bin/strace`.
The box copies `doctl.tgz`, doctl's release asset `doctl-1.177.0-linux-arm64.tar.gz`, from beside the
Dockerfile (sha256 `3adfe5bb667c2cdee15eb3501d53b57d8f04dfa945ddd4584f6f760834506992`, as the release's
checksums file gives it).

| target | before | after |
|---|---|---|
| stylelint `--fix a.css` | PASS 6/6, 5 runs of 5 | PASS 6/6, 5 runs of 5 |
| doctl `auth switch` | FAIL 1/3, earliest 2, 5 runs of 5 | FAIL 1/3, earliest 2, 5 runs of 5 |
| virtualenv `-q --no-download` | UNKNOWN `nothing_could_fail`, 1382 explored | UNKNOWN `kill_did_not_land` at world 1360: `open v2/bin/pip` in the world, `open v2/bin/pip3.13` in the recording |
| virtualenv, `PYTHONHASHSEED=0` | — | UNKNOWN `nothing_could_fail`, 1382 explored |

`transcripts/targets.txt` holds each run's first line.
