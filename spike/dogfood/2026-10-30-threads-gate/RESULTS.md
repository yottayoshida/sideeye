# #979: the threads gate and operations that change nothing

main (`f07d80a6`) beside this change, both built for aarch64 Linux and mounted into the boxes their defines
were written for (`apparatus/gate.sh`, `apparatus/a.sh`), with the cgroup the engine needs
(`--privileged --cgroupns=private`).

| define | runs | main | this change | record |
|---|---|---|---|---|
| vercel (2026-10-09 follow-ups 3, `UV_THREADPOOL_SIZE=1`), `explore --oracle` | 10 each | `multiple_threads_detected` 10 | PASS 20/20 10 | `transcripts/vercel.txt` |
| codex-scratch (2026-10-09 follow-ups 4, `tmp` scratch), `explore --observe supervised` | 3 each | `multiple_threads_detected` 3 | PASS 21/21 3 | `transcripts/codex-scratch.txt` |
| acceptance toy, two workers that only `mkdir` the state root | 1 each | `multiple_threads_detected` | FAIL at crash point 7 of 7 (the toy's own defect) | `transcripts/toys.txt` |
| acceptance toy, two siblings that write files of their own | 1 each | `multiple_threads_detected` | `multiple_threads_detected` | `transcripts/toys.txt` |

Not recorded: an earlier set of ten vercel runs on this change, nine PASS 20/20 and one stopped at
`child_process_detected` (vercel's update notifier starts a child at random), and the toy's first form, where the
two workers made the root at the same instant and took the same crash-point number: `sequence_numbering_broken`.
The toy now has the second worker wait on a flag, so nothing orders the two but neither runs at once.
