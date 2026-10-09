# bat — origin

Copied from `spike/dogfood/2026-09-16-userview-3/`, slate 3. Not measured here.

## Source

| piece | where (under `2026-09-16-userview-3/apparatus/`) |
|---|---|
| setup (now `seed.sh`) | `run-r3b.sh` lines 10-13 (`setup-bat.sh`) |
| checker (`check.sh`) | `run-r3b.sh` lines 16-20 (`check-bat.sh`) |
| define (`sideeye.toml`) | `run-r3b.sh` lines 23-30 (`bat.toml`, argv form, with `apparatus`) |
| the pinned clock, set by the runner | `run-r3b.sh` lines 60-61, undone on line 66 |
| the explore | `run-r3b.sh` lines 62-64 |

This is the form `RESULTS.md` records for bat (`explore/bat2.txt`: "`metadata.yaml`, and a
faked clock does not fix it"). An earlier form exists and was not copied: `run-r3.sh` lines
17-31 and 118-121 — string-form operation on `/localrun/st/bt`, no pinned clock,
`BAT_CACHE_PATH` exported in the engine's environment, and a checker that also ran
`batcat --language sh --plain /etc/hostname`. It was refused for the same reason
(`explore/bat.txt`).

## Tool and engine at the time

bat 0.25.0 (`transcripts/explore/bat2.txt`, line 2), Debian trixie's package `bat`, whose
binary is `batcat`. `Dockerfile.run3`:

```
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps faketime libfaketime git
RUN for p in bat python3-sphinx python3-virtualenv libvips-tools tesseract-ocr tesseract-ocr-eng python3-pil; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt
```

Engine: the released Sideeye v1.4.0 (`trace contract v17`), mounted read-only at `/se`, run
with `--shim /se/libsideeye_shim.so --oracle /usr/bin/strace`. The `docker run` line was not
recorded by that run.

## What refused it

Default mode (no `--observe`). `UNKNOWN baseline_violates_invariant` — "the re-run from the
restored state left metadata.yaml holding neither the old nor the new content"
(`transcripts/explore/bat2.txt`, `bat2.json`). `preflight` without an oracle, on the earlier
form, accepted the recording with 7 operations (`transcripts/preflight/bat.txt`).
`--observe syscalls` was not tried.

## The runner has to supply (not expressible in `seed.sh` or `sideeye.toml`)

The define declares `apparatus = ["env:FAKETIME=@2024-01-01 00:00:00", "preload:libfaketime"]`.
Sideeye applies none of it and refuses as SETUP ERROR when it is absent (`docs/apparatus.md`).
The 2026-09-16 runner did this before starting the engine, so the setup ran under it too:

```
FT=$(find /usr/lib -name 'libfaketime.so*' 2>/dev/null | head -1); echo "$FT" > /etc/ld.so.preload
FAKETIME="@2024-01-01 00:00:00"; export FAKETIME
```

The 2026-09-28 `run.sh` does neither. The box needs the `libfaketime` package.

## Changed from the original

- State `/localrun/st/bt2` -> `/s/bat/state`, and the syntax source directory
  `/localrun/aux/batsrc` -> `/s/bat/aux/batsrc`. Both are arguments of the operation, so the
  operation's argv changed in those two words and nowhere else.
- The engine no longer runs the setup (`setup =` is gone from the toml): its body is `seed.sh`,
  which the runner runs before each engine invocation. `seed.sh` starts by removing `/s/bat`;
  the original setup did not empty the state directory.
- `$SD` in the setup and the checker is spelled out; the checker is at `/ap/defines/bat/check.sh`.
- `check.sh` needs mode 755 (the engine executes it). It was set when the file was written;
  check it after a checkout.
