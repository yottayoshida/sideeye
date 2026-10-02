# meson — origin

Copied from `spike/dogfood/2026-09-16-userview-3/`, slate 4. Not measured here.

## Source

| piece | where (under `2026-09-16-userview-3/apparatus/`) |
|---|---|
| the source tree (`meson.build`, `p.c`), written by the runner | `run-r4c.sh` lines 8-9 |
| setup (now `seed.sh`, after the two lines above) | `run-r4c.sh` lines 12-21 (`setup-meson.sh`) |
| checker (`check.sh`) | `run-r4c.sh` lines 24-29 (`check-meson.sh`) |
| state, environment, operation | `run-r4c.sh` lines 7 and 32-39 (flags, string-form operation) |

The only define written for meson. `run-r4.sh` lines 8-12, `run-r4b.sh` lines 36-39 and
`run-r4d.sh` lines 6-10 ran `meson setup` by hand to learn why it failed in the image; they
are not defines.

## Tool and engine at the time

meson 1.7.0 (`transcripts/screen/r4-screen.txt`, line 19), Debian trixie's package.
`Dockerfile.run4`:

```
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps faketime libfaketime
RUN for p in ninja-build ccache pandoc meson rust-coreutils gcc libc6-dev; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt
```

ccache was in the same image, and meson picked it up as the compiler until `CC` was set
(`SELECTION.md`, the screen table's meson row; `run-r4c.sh` line 2).

Engine: the released Sideeye v1.4.0 (`trace contract v17`), mounted read-only at `/se`, run
with `--shim /se/libsideeye_shim.so --oracle /usr/bin/strace`. The `docker run` line was not
recorded by that run.

## What refused it

Default mode (no `--observe`). `UNKNOWN baseline_violates_invariant` — "the re-run from the
restored state left meson-logs/meson-log.txt holding neither the old nor the new content"
(`transcripts/explore/meson.txt`, `meson.json`). `preflight` without an oracle:
`boundary_without_oracle` (`transcripts/preflight/meson.txt`). `--observe syscalls` was not
tried.

## The runner has to supply (not expressible in `seed.sh` or `sideeye.toml`)

`CC=gcc` in the engine's environment. The 2026-09-16 runner exported it before starting the
engine (`run-r4c.sh` line 7):

```
CC=gcc; export CC
```

The setup sets it inline; the operation (`meson setup --reconfigure`) inherited it from the
engine. The 2026-09-28 `run.sh` exports nothing.

## Changed from the original

- State `/localrun/st/ms` -> `/s/meson/state`, source tree `/localrun/aux/ms/src` ->
  `/s/meson/aux/ms/src`. Both are arguments of the operation, so those two words changed.
- The two `printf` lines that write the source tree moved from the runner into `seed.sh`.
- The engine no longer runs the setup (`--setup` is gone): its body is `seed.sh`, which the
  runner runs before each engine invocation. `seed.sh` starts by removing `/s/meson`; the
  setup's own emptying of the state directory is kept as it was and now finds it empty.
- No `cwd` was declared then and none is declared here.
- `$SD` in the setup and the checker is spelled out; the checker is at
  `/ap/defines/meson/check.sh`.
- `check.sh` needs mode 755 (the engine executes it). It was set when the file was written;
  check it after a checkout.
