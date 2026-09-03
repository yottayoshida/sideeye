# Exploration cost per world, by file count and by bytes (#262, ADR 0042)

A record, held by review (ADR 0039). `measure.sh` produced `run-1.txt`, `run-2.txt` and
`run-3.txt` on 2026-09-03, one after another; every row is an exploration the engine
confirmed — exit code 0 and its own `explored 5 worlds (crash points 4 + 1 baseline)` line —
and the table below is the median of the three per-world figures.

## Conditions

- Host, from the run headers: macOS 15.3.1, Apple M4, 32 GiB, Zig 0.16.0. Engine and shim
  built from `30f9a6c`; the headers say `5ae3d40` because the checkout was fast-forwarded
  to that docs-only commit before the runs, and `src/`, `shim/` and `build.zig` are identical
  at both.
- The host was not idle. Each log records `uptime` at start and end: the one-minute load
  average was between 10.0 and 14.6 across the six readings, with an endpoint scanner and
  a browser busy. The constants below are therefore this machine's on this afternoon; the
  shape — a part per world plus a part per file per world — is the claim.
- Target: `spike/out/toy-fixed` (`init` as setup, `rotate` as operation), which produces
  four crash points and owns one or two files of its own; the padding directory under
  `--state` is never touched by the operation. Every padding file holds the same random
  bytes; only their number and size vary. No oracle (`--allow-unverified`), no checker, no
  forking target. A run with a checker adds one process per world; a world in which a process
  boundary appears (a fork or an exec) snapshots the tree a second time, and none of these
  rows has one.
- **"Per world" is an upper bound.** The timer wraps the engine process, and the engine's
  clock covers start-up, `setup`, the recording run and the two snapshots around it before
  the first world; the figure divides that whole clock by the five worlds. On this toy the
  extra is roughly two full-tree reads on top of the ten passes (five restores, five
  snapshots) the worlds cost. The record does not subtract an estimate.

## Per world, median of three runs

| padding files | bytes each | `du -sh` | run 1 | run 2 | run 3 | median | spread |
|---|---|---|---|---|---|---|---|
| 20 | 1 KiB | 80 KiB | 0.167 s | 0.227 s | 0.113 s | **0.17 s** | 2.0× |
| 200 | 100 KiB | 20 MiB | 0.497 s | 0.586 s | 0.560 s | **0.56 s** | 1.2× |
| 2,000 | 10 KiB | 23 MiB | 3.737 s | 4.117 s | 3.606 s | **3.7 s** | 1.1× |
| 2,000 | 50 KiB | 102 MiB | 4.573 s | 4.043 s | 3.778 s | **4.0 s** | 1.2× |
| 20,000 | 1 KiB | 78 MiB | 28.135 s | 25.340 s | 31.457 s | **28 s** | 1.2× |

`du -sh` is allocation as the filesystem reports it, in KiB and MiB; the 20,000-file tree
holds 20.5 MB of content on 78 MiB of blocks. Spread is the largest of the three runs over
the smallest.

Read from the medians against the 20-file row, per padding file added: 1.4 ms on the
20,000-file shape (1.3 to 1.6 across runs), 1.8 ms at 2,000, 2.2 ms at 200, where the fixed
part and the spread dominate the small difference. The fixed part, under 0.2 s, is
engine start-up and `setup`; the two full-tree reads before the first world (the initial
snapshot and the one after the recording run) grow with the file count and so sit in the
per-file part, which is why the slope is an upper bound too: about twelve tree passes are
counted against the ten that five worlds cost. Bytes are secondary: five times the bytes at
2,000 files measured 8% more per world.

## What this does not say

- Nothing about a total. The number of crash points is the number of state-changing
  operations the recording saw, which the operation sets; a run costs the per-world figure
  times crash points plus one, and the file count does not predict the multiplier.
- Nothing about an idle machine, another filesystem, or Linux. `measure.sh` runs on either
  host; the figures here are one laptop's.
- Nothing about the snapshot ceiling. Every row is under `max_state_tree_bytes`; a row that
  hit it would have printed `not-counted`, and none did.
