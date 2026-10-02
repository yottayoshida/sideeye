# zstd (the 2026-09-16 userview-3 form) — origin

Copied from `spike/dogfood/2026-09-16-userview-3/`, slate 1. Not measured here. The
`2026-09-16-crossed-walls` run has a different zstd form; that one is `defines/zstd/`, not
this directory.

## Source

| piece | where (under `2026-09-16-userview-3/apparatus/`) |
|---|---|
| setup (now `seed.sh`) | `run-r1c.sh` lines 8-18 (`setup-zstd.sh`; `run-r1b.sh` lines 18-28 are the same lines) |
| checker (`check.sh`) | `run-r1c.sh` lines 21-33 (`check-zstd.sh`) |
| state and operation, default mode | `run-r1b.sh` lines 126-127 |
| state and operation, `--observe syscalls` | `run-r1c.sh` lines 36-40 |

`RESULTS.md` records one operation, `zstd -q --rm <state>/f.bin`, under both observation
modes (`explore/zstd*.txt`). Other forms exist and were not copied:

- `run-r1.sh` lines 46-59: a setup that left the previous `f.bin.zst` in place, so the
  operation exited 1 on a second run. `run-r1b.sh` replaced it and overwrote its transcript.
- `run-r1b.sh` lines 32-44: the same checker with a longer last message (it prints both
  sizes). The copy here is `run-r1c.sh`'s, the later one; the logic is the same.
- `run-r1d.sh`: `zstd -q --single-thread --rm`, under `--observe syscalls` — the same refusal
  (`explore/zstd-singlethread.txt`).

## Tool and engine at the time

zstd from Debian trixie's package; the version was not recorded by that run. `Dockerfile.run`:

```
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps faketime libfaketime
RUN for p in codespell vim zstd rubocop zoxide; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt
```

Engine: the released Sideeye v1.4.0 (`trace contract v17`), mounted read-only at `/se`, run
with `--shim /se/libsideeye_shim.so --oracle /usr/bin/strace`. The `docker run` line was not
recorded by that run.

## What refused it

- Default mode: `UNKNOWN oracle_missed_operation` — the oracle saw a `write` to `f.bin.zst`
  where the shim recorded the `unlink` of `f.bin` (`transcripts/explore/zstd.txt`, `zstd.json`).
- `--observe syscalls`: `UNKNOWN multiple_threads_detected` — one thread opened `f.bin.zst`,
  another wrote it (`transcripts/explore/zstd-syscalls.txt`, `zstd-syscalls.json`).
- `preflight` without an oracle accepted the recording with 3 operations
  (`transcripts/preflight/zstd.txt`).

The 2026-09-28 `run.sh` runs `--observe syscalls` only when the default mode's next step
names it. On 2026-09-16 the next step did not name it, and the second mode was run anyway.

## Changed from the original

- State `/localrun/st/zs` -> `/s/zstd-userview3/state`. It is in the operation
  (`/s/zstd-userview3/state/f.bin`); the rest of the operation is unchanged.
- The untouched copy the checker compares against, `/localrun/aux/f.bin.orig` ->
  `/s/zstd-userview3/aux/f.bin.orig` (outside the state directory, as it was).
- The engine no longer runs the setup (`--setup` is gone): its body is `seed.sh`, which the
  runner runs before each engine invocation. `seed.sh` starts by removing
  `/s/zstd-userview3`. The seed needs `python3`.
- No `cwd` was declared then and none is declared here.
- `$SD` in the setup and the checker is spelled out; the checker is at
  `/ap/defines/zstd-userview3/check.sh`.
- `check.sh` needs mode 755 (the engine executes it). It was set when the file was written;
  check it after a checkout.
