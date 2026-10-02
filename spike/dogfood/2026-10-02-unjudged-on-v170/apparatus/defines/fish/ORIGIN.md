# fish — origin

Copied from `spike/dogfood/2026-09-16-userview-3/`, slate 2. Not measured here.

## Source

| piece | where (under `2026-09-16-userview-3/apparatus/`) |
|---|---|
| setup (now `seed.sh`) | `run-r2e.sh` lines 8-13 (`setup-fishv.sh`) |
| checker (`check.sh`) | `run-r2e.sh` lines 16-21 (`check-fishv.sh`) |
| define (`sideeye.toml`) | `run-r2e.sh` lines 24-30 (`fishv.toml`, argv form) |
| environment, a hand run of the setup, the explore | `run-r2e.sh` lines 32-37 |

This is the universal-variable form, the one `RESULTS.md` records as fish's wall
(`inotify_add_watch`, `explore/fish4.txt`). The other form — appending to the history file —
was not copied, because it never wrote the state at all:

- `run-r2.sh` lines 11-16, 60-67, 133-136: string-form `fish -c echo_MARKER-third-entry`,
  refused `recording_run_failed`, exit 127 (`explore/fish.txt`).
- `run-r2b.sh` lines 15-37 and 74: argv form, `XDG_DATA_HOME` not in the engine's
  environment — `PASS`, "the operation performed nothing that can change the judged state"
  (`explore/fish2.txt`).
- `run-r2c.sh` / `run-r2d.sh`: the same with `XDG_DATA_HOME` exported — `checker_not_falsified`,
  the state directory held no files (`explore/fish3.txt`): a non-interactive `fish -c` does
  not write history.

## Tool and engine at the time

fish from Debian trixie's package; the version was not recorded by that run.
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

Default mode (no `--observe`). `UNKNOWN unsupported_syscall_observed` — `inotify_add_watch`
(`transcripts/explore/fish4.txt`, `fish4.json`). `--observe syscalls` was not tried.

## The runner has to supply (not expressible in `seed.sh` or `sideeye.toml`)

`XDG_CONFIG_HOME` in the engine's environment, pointing at the state directory. The
2026-09-16 runner exported it before starting the engine (`run-r2e.sh` line 32):

```
XDG_CONFIG_HOME=/localrun/st/fv; export XDG_CONFIG_HOME
```

Here that is `XDG_CONFIG_HOME=/s/fish/state`. The operation names no path, so without it fish
uses its default configuration directory, which is not the judged one. What the engine
answers in that case was not measured. The 2026-09-28 `run.sh` exports nothing. The setup and the checker set it inline.

## Changed from the original

- State `/localrun/st/fv` -> `/s/fish/state`. The operation's argv names no path and is
  unchanged.
- The engine no longer runs the setup (`setup =` is gone from the toml): its body is `seed.sh`,
  which the runner runs before each engine invocation. `seed.sh` starts by removing `/s/fish`.
  On 2026-09-16 the runner ran the setup once by hand (line 33) and the engine then ran it
  again over that state without emptying it; here it runs once, on an empty directory.
- No `cwd` was declared then and none is declared here.
- `$SD` in the setup and the checker is spelled out; the checker is at
  `/ap/defines/fish/check.sh`.
- `check.sh` needs mode 755 (the engine executes it). It was set when the file was written;
  check it after a checkout.
