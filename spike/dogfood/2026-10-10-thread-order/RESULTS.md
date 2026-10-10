# Results — 2026-10-10 thread-order (#687)

#687 asks whether the static targets that stop at `--observe supervised`'s threads wall have an order
between their writing threads that recording thread creations and exits from outside would see — and
only if they do, to record them. Measured on the released **v1.10.0** (`apparatus/Dockerfile`: Debian
trixie, Docker Desktop on the maintainer's Apple-silicon machine, aarch64; each target binary pinned by
the digest GitHub publishes for its release asset), with the defines of the campaigns that first met
them and **no switch for one thread** (no `GOMAXPROCS`, no `RAYON_NUM_THREADS` / `TOKIO_WORKER_THREADS`).
Predictions were committed before any run (`953b6e8d`, `PREDICTIONS.md`).

## Method

Each attempt seeds the state and runs `sideeye preflight --config <define> --observe supervised
--oracle /usr/bin/strace` (`apparatus/run.sh`): the recording run only. The oracle is strace over that
same run, with the engine's own arguments (`-f -y -e trace=%file,%desc,%process,…`), so a refused
attempt leaves a capture of the very run the engine refused — every thread's creation (`clone`'s
return value) and exit, and every call of the engine's ten kill-point classes. `apparatus/order.py`
reads it: a **hand-over** is two consecutive state writes of one process by two different threads,
A then B, failed calls included (the engine counts them) and calls a signal took back (`= ?
ERESTART…`) not. It is ordered when, between A's write and B's, A (or a thread A created in that
window) created B, or A — or a thread A created in that window — exited. A join is visible from
outside only as the exit, so the second test is the generous one: any exit in that chain is taken as
the join that would order the hand-over (ADR 0067's chain of creations and joins). Per run:
`all-ordered`, `unordered` (at least one hand-over that neither orders), or `no-handover`.

The reader was checked before it was believed: `order.py --selftest` holds eight synthetic captures
(every hand-over ordered, none, one of two, one writer, a creation that precedes the creator's last
write, an exit of a thread the writer created afterwards, an exit of one it created before, a write
taken back by a signal), and builds three broken readers — one that ignores the creation's window,
one that ignores exits, one that ignores when an exiting thread was created — that four of the cases
catch. Two C programs then went
through the same pipeline as the targets (`apparatus/controls/`): `ctl-ordered` writes, creates a
worker that writes, joins it and writes; `ctl-condvar` creates its worker first and hands over through
a condition variable, the worker alive until after the last write. And follow-ups 7's hand-read jj
capture reads `unordered` (2820 → 2811, the futex hand-over).

## What the captures show (`transcripts/order.tsv`)

| target | refused / attempts | `unordered` | `all-ordered` |
|---|---|---|---|
| `ctl-ordered` (control) | 5 / 5 | 0 | **5** — as predicted: supervised records no join, so it refuses a run whose every hand-over a creation or an exit orders |
| `ctl-condvar` (control) | 5 / 5 | **5** | 0 |
| jj 0.46.0 `commit` of a modified file | 5 / 5 | 5 | 0 |
| OpenTofu 1.13.1 `state rm` | 5 / 11 | 5 | 0 |
| codex 0.160.0 `mcp add` | 5 / 5 | 5 | 0 |
| doctl 1.177.0 `auth switch` | 35 / 40 | 33 | **2** |
| notesmd-cli 0.3.7 `move` | **0 / 15** | — | — |

**Of the 50 refused recording runs of the four targets, 48 hold a hand-over that neither a creation
nor an exit orders.** Two predictions were wrong: "no refused run reads `all-ordered`" (doctl, 2 of
35), and notesmd-cli's "at least 1 of 15" refused (0 of 15).

- **doctl, the two.** The main thread opens `config.yaml` with `O_RDWR|O_CREAT|O_TRUNC` — the
  truncation is its write — and another thread writes the new contents. In the two runs, the writing
  thread descends from a creation the main thread made after the open: in attempt 3 of the first
  five the main thread created it, in attempt 35 of a second run (35 attempts, 30 refused) the main
  thread created a thread that created it. In the other 33 the writer descends only from creations
  made before the open, which order nothing after it. Which thread the Go scheduler runs the writing
  goroutine on is its choice per run. The second run was taken to count this (`apparatus/measure.sh`
  names the command; `transcripts/doctl-30/`).
- **notesmd-cli** was accepted at the recording in all 15 attempts on v1.10.0, one thread writing
  (2026-10-03 met the threads refusal in 2 of 5 at the gate, on v1.7.0). It is not one of the 50.
- **jj** hands back through a futex inside a thread pool (follow-ups 7); OpenTofu and codex likewise
  hand over between threads that were created before either wrote and outlive the writes.

## What was decided (owner, 2026-10-10)

The two doctl runs met the plan's stop condition: a refused run that recording creations and exits
would order. The owner chose not to build that recording, and to write the counts down instead.
The reason: a run is judged only when the recording and every explored world are ordered — doctl's
explorations have three or four worlds, and at the measured rate (2 in 35) all of them landing
ordered is not a way past. Not measured: whether worlds are independent of one another in this
respect (an estimate, not a finding). doctl reached a verdict once with `GOMAXPROCS=1` under
supervised (2026-10-09 follow-ups 3: FAIL 1/3); with one P the writing thread is still the
scheduler's choice, and OpenTofu was refused under the same switch, so it is a way past measured
once, not one guaranteed.

## What this does not cover

- **Recording runs only.** An explored world and a replay run without an oracle, so their refusals
  were not read (OpenTofu refused in both replays of its 2026-10-09 FAIL). **tombi**, the sixth target
  #687 names, is not here: it refused in 1 of 36 supervised explores and 3 of 20 replays while its
  preflight was accepted 26 times of 26 (`docs/target-classes.md`), so fifteen recording runs would
  most likely have read nothing, and the replays and worlds that refused have no oracle capture.
- **A join is read as an exit.** A thread that exits is not necessarily joined before the next write;
  the generous reading can only have counted more hand-overs ordered, not fewer. Widening it to the
  exits of threads the writer created (the first reading counted the writer's own exit only) changed
  no run's verdict over all 60 captures, the ones not kept included.
- **One machine, aarch64, Docker Desktop.** The scheduler's choices are the measured thing, and they
  may differ elsewhere.
- **Kept here:** every run's verdict (`order-<n>.json`, `attempts.tsv`, `preflight-<n>.txt`) and
  sixteen of the captures — the ten controls, one each of jj, OpenTofu and codex, and doctl's two
  `all-ordered` runs beside one `unordered`. The other captures and the work directories (42 MB) were
  read in place and not committed; `order.tsv` marks which capture is kept. In the kept captures the
  host path of the mounted `transcripts/` directory, which strace printed for the operation's stdout
  and stderr, is replaced by the box's own `/out/` (73 occurrences in six captures; every reading was
  compared before and after and is unchanged). `attempts.tsv` shows `-` for the attempts the
  recording accepted in the first run: the `run.sh` committed with the predictions matched no
  `PREFLIGHT` line; each `preflight-<n>.txt` says `recording accepted`.
