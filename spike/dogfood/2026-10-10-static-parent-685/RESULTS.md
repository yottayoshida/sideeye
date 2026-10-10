# Results — 2026-10-10, the three static parents on #685's build

#685 asks for the refusal a static parent with a dynamic child meets to name `--observe supervised`, and for
lefthook to be re-measured under the corrected advice. The three targets the records hold in that shape were
run on the build under test — branch `auto/b_cc4c998976e3` at `f57083d4` with #685's working tree, built for
aarch64 Linux (`sideeye version` says 1.10.0, the version this build inherits; it is not the release; the
base, the sha256 of the `src`/`shim` diff and of the two binaries are in `transcripts/build.txt`, and the
commits `main` gained after `f57083d4` before this was written touch neither) — each
with the define its record used, copied unchanged into `apparatus/defines/`. `apparatus/run.sh` runs the page's
command (`explore --config … --oracle /usr/bin/strace --json`) in the default mode, then follows the next step
once, by the mode it names. The box (`apparatus/Dockerfile`) holds the three tools from their release assets
(`/downloads.sha256` in the image) and no engine; the build is mounted. No checkers: the built-in atomicity rule
judges, as in the runs these defines come from.

| target | default mode | the step it names | followed once |
|---|---|---|---|
| aliyun-cli 3.5.1 `configure delete` | UNKNOWN `oracle_missed_operation` | `observe_supervised_static_parent` | **PASS** 7/7, 6 crash points, the oracle agreeing on 6 operations |
| roswell 26.02.116 `ros config set` | UNKNOWN `unresolvable_path` (`trace-closed-by-target`) | `observe_supervised_static_parent` | **FAIL** 1/3, crash point 2 of 2 — after the `open` of `config`, before its `write`, holding neither content |
| lefthook 1.13.6 `install` | UNKNOWN `oracle_missed_operation` | `observe_supervised_static_parent` | UNKNOWN `nothing_could_fail`: 5 worlds over 4 crash points, and none of the 14 paths the built-in rule judges was changed by one |

All three are statically linked (`file -L` in `transcripts/explore/<t>/engine.txt`). On the releases those records ran (v1.7.0,
v1.8.0, v1.9.0) the first two steps sent the reader to `--observe syscalls` and to the class wall, and only `--observe supervised`
named by hand got past (`2026-10-05-user-data-2`, `2026-10-07-user-data-3`, `2026-10-02-unjudged-on-v170`). On
this build the page's path gets there: aliyun-cli and roswell reach the verdicts their records reached by hand.

lefthook gets past the observation wall — the default mode explored 0 worlds, supervised explores 5 — and stops
at the define. Its record's PASS 5/5 on v1.7.0 judged git's `*.sample` hooks, which `install` does not write;
ADR 0091 (owner ruling 2026-10-06) made an exploration in which nothing could fail UNKNOWN, and this run says so with the step
that asks for a checker. The define's own checker (`defines/lefthook/check.sh`) was refused
`checker_not_falsified` on 2026-09-27 and is not run here.

Not measured here: the `child_touched_state_dir` shape. It was measured on a toy only (`spike/acceptance.sh`,
the #685 legs); no real target in the records has met it.

Records: `transcripts/build.txt`; `transcripts/explore/<t>/{default,followed}.{txt,json,rc}`, `engine.txt`, `seed-*.log`.
