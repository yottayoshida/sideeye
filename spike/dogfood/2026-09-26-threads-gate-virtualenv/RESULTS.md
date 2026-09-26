# Results — the 2026-09-26 threads-gate run

One target, through the 2026-09-22 entry gate and nothing further: the question was what the
gate's threads question answers on a real target whose two writing threads a join orders
(ADR 0085, amended 2026-09-22, left it open). The answer to *whether to drop the question*
did not wait on this — `PREDICTION.md`, committed before the box was built, gives why — so
there is no explore and no replay; the 2026-09-16 run already judged this target PASS
1382/1382 under contract v18.

| | |
|---|---|
| engine | Sideeye **v1.6.0** (trace contract v18), installed in the 2026-09-22 box by the page's installer, digest `86622c84…` matched (`transcripts/environment.txt`) |
| box | `sideeye-tg`: `FROM sideeye-sv` (the 2026-09-22 image, sha256:5cbbc4c9…) plus Debian's `python3-virtualenv` 20.31.2+ds-1+deb13u1 (`apparatus/Dockerfile`). Run `--network none --cap-add SYS_PTRACE`, the 2026-09-22 flags — not the 2026-09-16 run's `seccomp=unconfined` |
| gate | `apparatus/entry.sh`, `gate.sh`, `toml2flags.py` — the 2026-09-22 files byte for byte (`cmp` before the commit) |
| target | virtualenv 20.31.2 from `/usr/lib/python3/dist-packages`, the same package the 2026-09-16 run measured; define `apparatus/defines/virtualenv/` from that run's (`2026-09-16-userview-3/apparatus/run-r3.sh`) |
| driver | `apparatus/run.sh`; rows in `transcripts/rows.txt`, everything else in `transcripts/entry/` |

**Differs from the plan:** the plan copied the 2026-09-22 Dockerfile and added one package.
The box is built `FROM` the 2026-09-22 image instead, because a rebuild re-fetches Sideeye and
every candidate over the network with nothing to guarantee the same bytes; `run.sh` prints the
engine version and installer digest from inside the box.

## Rows

| define | static | preflight | threads | gate |
|---|---|---|---|---|
| `legs/joinedthreads` (contrast) | dynamic | rc 0, accepted, 4 operations | rc 1 — 2 writer ids, 3 `CLONE_THREAD` | **1** |
| `defines/js-beautify` (contrast) | dynamic | rc 0, accepted, 3 operations | rc 0 — 1 writer id, 7 `CLONE_THREAD` | **0** |
| `defines/virtualenv` | dynamic | rc 0, **accepted, 1381 operations** | rc 1 — **2 writer ids**, 3 `CLONE_THREAD` | **1** |

The contrasts give the same answers they gave on 2026-09-22, in this box: the gate can answer
both ways here.

**virtualenv is row 1 of the prediction's reading: accepted, and red on threads.** The
engine's account in the same preflight (`virtualenv.preflight.txt`, line 6): *"the shim
recorded 2 thread(s) created, and 2 thread id(s) of the subject's own process wrote the
judged directory; 2 hand-over(s) between threads in causal order, 2 join(s) and 0 detach(es)
recorded"*. The engine counts the same two writers the gate does, reads the joins that order
them, and admits the run; the gate counts them and turns it away.

## The writer count, from three places

| source | writers |
|---|---|
| the gate (`strace -f`, `virtualenv.strace.txt`) | tid 233 — 32 writing lines; tid 235 — 499 writing lines. Three ids in the capture: 233 and the two threads it created, 234 and 235 (of the 3 lines carrying `CLONE_THREAD`, one is a `clone3` refused `ENOSYS` and retried); 234 never writes inside `/s/venv` |
| preflight's account (the shim's record, a separate run) | 2 thread ids of the subject's own process |
| the 2026-09-16 `LD_PRELOAD` probe (another day, another instrument; `2026-09-16-threads-take-turns/RESULTS.md`) | the main thread, 18 operations before it joins the pip thread and 14 after — 32; the pip thread, 499 |

Two, in all three. tid 233 is the process `env -C / /usr/bin/virtualenv …` exec'd into — the
main thread — and no child process was created: the capture carries three ids and no others,
233 (1,967 lines), 234 (17) and 235 (4,259), and 234 and 235 are the two threads 233 created, so the gate's count over every id under
`strace -f` and the engine's over the subject's own process are the same count here. The
per-thread figures agree exactly as well: the main thread's 32 writing lines are 5 `mkdirat`,
12 `openat`, 3 `symlinkat` and 12 `write`, which is the probe's 5 `mkdir`, 12 `open`,
3 `symlink` and 12 `write`; the pip thread's are 499 in both.

## Corrections to the prediction

`PREDICTION.md` is left as committed. Two of its statements about 2026-09-16 are wrong, and
neither touches the reading:

- *"main thread … with 18 operations"* — 18 is the count before the join; the main thread
  performs 14 more after it, 32 in all (`2026-09-16-threads-take-turns/RESULTS.md`, steps 1
  and 5).
- *"on main `d5911cd`"*, *"2026-09-16's main accepted"* — that run used a branch build of
  Sideeye (contract v18; the transcripts print its branch version), not main.
  `d5911cd` is the later merge commit. The comparison that matters holds either way: this
  run's engine is the released v1.6.0, contract v18.

Not changed, and recorded: `run.sh` copies `/tmp/gate-out/threads.txt` after the loop
without checking which define wrote it last. Had virtualenv's threads step not run, the file
would have been js-beautify's under virtualenv's name. It was virtualenv's here: its sixth
line is the `execve` of `/usr/bin/virtualenv`, after `env`'s.

## What this settles

The disagreement ADR 0085's amendment derived from the code and showed on a toy occurs on a
real target: the one real target whose writers a join orders, measured with the released
engine and the gate as shipped. The question is dropped (ADR 0085, amended 2026-09-26); the
reasoning is the prediction's and does not rest on this row.

Also in the preflight, and not read further here: *"the second observed run recorded a thread,
and that run's capture is never parsed, so nothing accounts for it"* — a disclosure the
engine makes about `--twice`'s second run, recorded verbatim.
