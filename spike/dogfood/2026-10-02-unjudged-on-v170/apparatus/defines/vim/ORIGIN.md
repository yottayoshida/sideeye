# vim — origin

Copied from `spike/dogfood/2026-09-16-userview-3/`, slate 1. Not measured here.

## Source

| piece | where (under `2026-09-16-userview-3/apparatus/`) |
|---|---|
| setup (now `seed.sh`) | `run-r1b.sh` lines 49-56 (`setup-vim.sh`) |
| checker (`check.sh`) | `run-r1b.sh` lines 59-66 (`check-vim.sh`) |
| define (`sideeye.toml`) | `run-r1b.sh` lines 69-75 (`vim.toml`, argv form) |
| the two explores | `run-r1b.sh` lines 129-130 (`vim2`, and `vim2-syscalls` with `--observe syscalls`) |

This is the form `RESULTS.md` records for vim (`explore/vim2*.txt`): the argv form, with
`set nobackup noswapfile nowritebackup` as one argument. An earlier form exists and was not
copied: `run-r1.sh` lines 35-44, 110-121 and 196 — string-form
`vim -es -u NONE -c %s/old/new/g -c wq <state>/a.txt`, without the backup options. It was
refused for the same reason (`explore/vim.txt`).

## Tool and engine at the time

vim from Debian trixie's package; the version was not recorded by that run. `Dockerfile.run`:

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

Both observation modes, the same answer: `UNKNOWN unsupported_syscall_observed` — `getxattr`.
Default mode: `transcripts/explore/vim2.txt`, `vim2.json`. `--observe syscalls`:
`transcripts/explore/vim2-syscalls.txt`, `vim2-syscalls.json`. `preflight` without an oracle,
on the earlier form, accepted the recording with 17 operations
(`transcripts/preflight/vim.txt`).

The 2026-09-28 `run.sh` runs `--observe syscalls` only when the default mode's next step
names it. On 2026-09-16 the next step did not name it, and the second mode was run anyway.

## Changed from the original

- State `/localrun/st/vi` -> `/s/vim/state`. It is the last argument of the operation
  (`/s/vim/state/a.txt`); the other ten are unchanged.
- The engine no longer runs the setup (`setup =` is gone from the toml): its body is `seed.sh`,
  which the runner runs before each engine invocation. `seed.sh` starts by removing `/s/vim`.
- No `cwd` was declared then and none is declared here.
- `$SD` in the setup and the checker is spelled out; the checker is at
  `/ap/defines/vim/check.sh`.
- `check.sh` needs mode 755 (the engine executes it). It was set when the file was written;
  check it after a checkout.
