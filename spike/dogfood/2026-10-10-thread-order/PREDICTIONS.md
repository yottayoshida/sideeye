# Predictions — 2026-10-10 thread-order (#687)

Written and committed before any run. The question: when Sideeye v1.10.0 refuses
`multiple_threads_detected` under `--observe supervised`, does a thread creation or a thread exit fall
between one writing thread's write and the next writer's — so that recording both from outside would
order the run? `apparatus/order.py` reads the oracle capture of each refused recording run and says,
per run, `all-ordered`, `unordered` (at least one hand-over neither event orders) or `no-handover`.

Each target is attempted until five recording runs are refused, or fifteen attempts. No switch for one
thread is set (no `GOMAXPROCS`, no `RAYON_NUM_THREADS` / `TOKIO_WORKER_THREADS`): the shape #687 names.

| target | refused | each refused run |
|---|---|---|
| `ctl-ordered` (control: write, create, the worker writes, join, write) | 5 of 5 — supervised records no join | `all-ordered` |
| `ctl-condvar` (control: the worker created first, a condition variable hands over, the worker alive to the end) | 5 of 5 | `unordered` |
| jj 0.46.0 `commit` of a modified file | 5 of 5 (2026-09-27: 5/5) | `unordered` — the blob writer hands back through a futex (follow-ups 7) |
| OpenTofu 1.13.1 `state rm` | at least 1 of 15 — the writer thread is the scheduler's choice per run | `unordered` |
| doctl 1.177.0 `auth switch` | 5 of 5 | `unordered` |
| codex 0.160.0 `mcp add` | 5 of 5 | `unordered` — the config thread and the threads that make `tmp/arg0` |
| notesmd-cli 0.3.7 `move` | at least 1 of 15 (2026-10-03: 2 of 5 at the gate) | `unordered` |

Overall: **no refused run of the five targets reads `all-ordered`.** If one does, the plan stops:
that run is one a supervisor recording creations and exits could judge, and #687's "Only if they do"
applies (not this change). A refused run that reads `no-handover` means the reader counts writes
differently from the engine; the reader is fixed and every capture read again before anything is
concluded.
