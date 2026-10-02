# rrdtool — origin

Copied from `spike/dogfood/2026-09-16-userview-3/`, slate 2. Not measured here.

## Source

| piece | where (under `2026-09-16-userview-3/apparatus/`) |
|---|---|
| setup (now `seed.sh`) | `run-r2.sh` lines 27-33 (`setup-rrd.sh`) |
| checker (`check.sh`) | `run-r2.sh` lines 82-91 (`check-rrd.sh`) |
| state and operation | `run-r2.sh` lines 130 and 141-142 (flags, string-form operation) |

The only define written for rrdtool; the `run-r2b.sh` … `run-r2e.sh` re-measurements do not
touch it.

## Tool and engine at the time

rrdtool from Debian trixie's package; the version was not recorded by that run.
`Dockerfile.run2`:

```
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps faketime libfaketime git
RUN for p in fish python3-pip rrdtool composer php-cli pre-commit; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt
```

Engine: the released Sideeye v1.4.0 (`trace contract v17`), mounted read-only at `/se`, run
with `--shim /se/libsideeye_shim.so --oracle /usr/bin/strace`. The `docker run` line was not
recorded by that run.

## What refused it

Default mode (no `--observe`). `UNKNOWN unsupported_syscall_observed` —
`mmap(PROT_WRITE|MAP_SHARED)` (`transcripts/explore/rrdtool.txt`, `rrdtool.json`).
`preflight` without an oracle: `state_changed_without_ops`
(`transcripts/preflight/rrdtool.txt`). `--observe syscalls` was not tried.

## Changed from the original

- State `/localrun/st/rr` -> `/s/rrdtool/state`. It is in the operation
  (`/s/rrdtool/state/t.rrd`); the rest of the operation is unchanged.
- The engine no longer runs the setup (`--setup` is gone): its body is `seed.sh`, which the
  runner runs before each engine invocation. `seed.sh` starts by removing `/s/rrdtool`.
- No `cwd` was declared then and none is declared here.
- `$SD` in the setup and the checker is spelled out; the checker is at
  `/ap/defines/rrdtool/check.sh`.
- `check.sh` needs mode 755 (the engine executes it). It was set when the file was written;
  check it after a checkout.

## The checker is red on the seed — as it was then

Run on the fresh seed in the 2026-10-02 box, `check.sh` exits 1: "the earlier value 22 at
1700000120 is gone". It is not gone. The RRA's step is 60 s and `fetch AVERAGE` prints the
consolidated rows — `1700000100: 1.8333e+01`, the average of 11 and 22 — so no row ever reads
`1700000120: 2.2…`; `rrdtool lastupdate` shows the raw update. The pattern never matched. On
2026-09-16 the define was refused before any explore (`unsupported_syscall_observed`, the
shared mapping), so the checker never ran and its red was never seen. It is copied unchanged
here, because the question is the engine's; a verdict that rests on this checker is not read
as a verdict about rrdtool.
