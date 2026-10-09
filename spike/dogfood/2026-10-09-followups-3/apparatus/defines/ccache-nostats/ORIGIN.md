# ccache — origin

Copied from `spike/dogfood/2026-09-16-userview-3/`, slate 4. Not measured here.

## Source

| piece | where (under `2026-09-16-userview-3/apparatus/`) |
|---|---|
| setup (now `seed.sh`) | `run-r4d.sh` lines 15-21 (`setup-ccache.sh`) |
| checker (`check.sh`) | `run-r4d.sh` lines 24-36 (`check-ccache.sh`) |
| state, environment, operation | `run-r4d.sh` lines 39-43 (flags, string-form operation) |

This is the form `RESULTS.md` records for ccache (`explore/ccache2.txt`). An earlier form
exists and was not copied: `run-r4.sh` lines 35-52 and 107-110 — same operation on
`/localrun/st/cc`, with a checker that only asked whether `ccache -s` ran. That one was
refused `checker_not_falsified` (`explore/ccache.txt`), which is why the checker was replaced.

## Tool and engine at the time

ccache from Debian trixie's package; the version was not recorded by that run.
`Dockerfile.run4`:

```
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps faketime libfaketime
RUN for p in ninja-build ccache pandoc meson rust-coreutils gcc libc6-dev; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt
```

Engine: the released Sideeye v1.4.0 (`trace contract v17`), mounted read-only at `/se`, run
with `--shim /se/libsideeye_shim.so --oracle /usr/bin/strace`. The `docker run` line was not
recorded by that run.

## What refused it

Default mode (no `--observe`). `UNKNOWN kill_did_not_land` — "An operation whose sequence of
state-directory calls varies between runs cannot be explored at a fixed index"
(`transcripts/explore/ccache2.txt`, `ccache2.json`). `preflight` without an oracle, on the
earlier form: `boundary_without_oracle` (`transcripts/preflight/ccache.txt`).
`--observe syscalls` was not tried.

## The runner has to supply (not expressible in `seed.sh` or `sideeye.toml`)

`CCACHE_DIR` in the engine's environment, pointing at the state directory. The 2026-09-16
runner exported it before starting the engine (`run-r4d.sh` line 40):

```
CCACHE_DIR=$CC2; export CCACHE_DIR
```

Here that is `CCACHE_DIR=/s/ccache/state`. The operation names no cache directory, so without
it ccache uses its default cache directory, which is not the judged one. What the engine
answers in that case was not measured. The 2026-09-28 `run.sh` exports nothing. The setup and the checker set it inline and do not
depend on this.

## Changed from the original

- State `/localrun/st/cc2` -> `/s/ccache/state`. The source directory `/localrun/aux/src` ->
  `/s/ccache/aux/src`; it is in the operation (`b.c`, `b.o`), so those two arguments changed.
- The engine no longer runs the setup (`--setup` is gone): its body is `seed.sh`, which the
  runner runs before each engine invocation. `seed.sh` starts by removing `/s/ccache`; the
  original setup did not empty the state directory.
- No `cwd` was declared then and none is declared here: the commands ran in the engine's own
  directory (`/work` in that image).
- `$SD` in the setup and the checker is spelled out; the checker is at
  `/ap/defines/ccache-nostats/check.sh`.
- `check.sh` needs mode 755 (the engine executes it). It was set when the file was written;
  check it after a checkout.
