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

## Added after the snapshotted runs, before the deletion runs

The second row's prediction was wrong in its verdict. Only the main thread writes (as predicted), and
the page's path gets past `multiple_threads_detected`, but explore ends `UNKNOWN baseline_run_failed`
("the un-killed baseline world did not exit normally"). `preflight --twice` names why before explore
does: the two runs leave different bytes in `.jj/working_copy/tree_state` — a 6-byte field at offset 12,
the file's modification time in milliseconds. Restore assigns timestamps during restore (`docs/cli.md`,
the `metadata` line), so in every world `alpha`'s time differs from the one `jj status` recorded; jj
re-reads the file and rewrites `tree_state` — one temporary and one rename more than the recording
(`transcripts/lab-5-{keep,retime}.txt`: 13 renames with the seed's time kept, 14 with `alpha` touched).
The baseline world's trace is one operation longer than world 81's (14159 against 14095 bytes, 64 per
operation), read here as the engine stopping it at operation 82, the index it was armed with; that
reading comes from the sizes, not from a decoded trace.

What the page's `next` says to do is "pin or relocate what differs". A working copy with no tracked file
has nothing whose time can differ, so the third form deletes `alpha` before the snapshot and the
operation commits the deletion; its checker asks that the probe commit hold no `alpha`.

| define | prediction |
|---|---|
| jj 0.44.0 and 0.46.0, `alpha` deleted and the deletion snapshotted (`jj status` last in the seed) | `preflight --twice` accepted (no `tree_state` difference), one writer thread, and explore judges it: PASS (temporaries and renames throughout, and the crash model is a killed process, not a lost write) |
