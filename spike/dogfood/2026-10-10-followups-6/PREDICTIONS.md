# Predictions — 2026-10-10 follow-ups 6

Written before the runs. The eighth "おわり？". #687 asks first for a measurement — whether the static
Go and Rust tools behind `multiple_threads_detected` under `--observe supervised` have any order to
record — and the comment posted there on 2026-10-09 measured doctl, tofu, codex and tombi but said
"jj was not re-measured". Jujutsu 0.44.0 refused 5 of 5 on 2026-09-27: the main thread opening
`.jj`'s `working_copy`, another thread a temporary in git's `objects`. Measured here on 0.44.0 and on
0.46.0 (the latest, 2026-10-07): which threads write the repository (`strace -f`, `apparatus/writers.sh`),
and the page's path for each define. Also recorded: ktlint/ktlint#3409's maintainer confirmed the
defect on 2026-10-09 (stage `acknowledged`; nothing was asked, so nothing is answered — the 2026-09-14
rule).

| define | prediction |
|---|---|
| jj 0.44.0 and 0.46.0, 2026-09-27's pre-state (`jj commit` snapshots the modified file itself) | the second writer is a rayon worker writing the file's blob into git's objects during the snapshot, beside the main thread's `.jj` writes; `multiple_threads_detected` under supervised, as on 2026-09-27 |
| the same, the pre-state already snapshotted (`jj status` last in the seed, what any jj command does) | the commit has no new file contents to write, so only the main thread writes, and the run is judged: PASS (jj writes its operation log and commit objects through temporaries and renames) |
