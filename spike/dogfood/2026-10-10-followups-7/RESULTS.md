# Results — 2026-10-10 follow-ups 7

The question follow-ups 6's comment on #687 left open: whether the thread that writes Jujutsu's
blob is joined before the first thread's next write. Measured on **Jujutsu 0.46.0** (the
`aarch64-unknown-linux-musl` release, sha256 `80e28f75…` as follow-ups 6 pinned it), in
`ubuntu:24.04` (sha256 `534baea6…`, aarch64, Docker Desktop on the maintainer's machine), with
2026-09-27's define as follow-ups 6 ran it: the seed and environment are
`spike/dogfood/2026-10-10-followups-6/apparatus/defines/jj-046-plain/{seed.sh,env.sh}`, the
operation `jj -R /s/jj/repo commit -m probe` over a modified working file.

`apparatus/run.sh` ran it under `strace -f -tt -y` with `clone`, `exit`, `exit_group` and
`futex` traced and **without `-qq`**, so a thread's exit is in the record — follow-ups 6's
`writers.sh` passed `-qq`, which drops it. The operation exited 0 (`transcripts/op.log`). The trace and output are written inside the container and
copied out at the end, so the record names no host path; a first run that wrote them through the mount
showed the same shape and is not kept for that reason.

## What the trace shows (`transcripts/join.strace`)

- The process creates **11 threads** (2812–2822) before it writes anything; 15 `clone` lines,
  some of them a call strace split across `unfinished`/`resumed`.
- **Thread 2820 writes the blob**: a temporary in `.git/objects`, two writes, the rename to
  `.git/objects/46/d35347…` at 51.615134.
- At 51.615399 it calls `futex(FUTEX_WAKE)`; the first thread (2811), waiting in `futex`, resumes
  at 51.615431, and at 51.616554 opens its own temporary in `.git/objects` and writes —
  1.4 ms after the rename.
- **Thread 2820 does not exit there.** All 11 threads exit together from 51.645229, just before
  the first thread (51.645411).

## What it says

The two writers have an order — a futex hand-over inside a thread pool — and it is not one that a
thread's creation or a join records. Recording `clone` and thread exits from outside, the second
half of #687's "What to add", would not order these writes.
