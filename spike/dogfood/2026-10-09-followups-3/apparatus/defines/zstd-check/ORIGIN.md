# zstd — where this define comes from

Copied from the 2026-09-16 crossed-walls screen, first pass. This is not the 2026-09-16
userview-3 define (`2026-09-16-userview-3/apparatus/run-r1.sh`, `run-r1c.sh`), which has a
different seed and a checker.

## Source

Paths under `spike/dogfood/2026-09-16-crossed-walls/`.

- seed: `apparatus/screen.sh` lines 55–69 (`setup-bin.sh`, shared with lz4's first pass)
- operation: `apparatus/screen.sh` line 154 — `screen zstd setup-bin.sh 'zstd -q --rm @SD@/f.bin'`
- how it ran: `apparatus/screen.sh` lines 140–142 — `sideeye preflight --state "$SD" --setup …
  --operation … --shim … --oracle /usr/bin/strace --observe <mode>`, started from inside the
  state directory (`cd "$SD"`), with no `--cwd` and no `--check`
- checker: none. The screen ran `preflight` only; zstd never reached `explore` in that run.

## Tool

zstd 1.5.7 (`*** Zstandard CLI (64-bit) v1.5.7, by Yann Collet ***`,
`transcripts/screen/screen-summary.txt`), Debian trixie's package. `apparatus/Dockerfile.screen`
lines 9–11:

```
RUN for p in zstd pigz lz4 ninja-build git yadm git-annex nodejs npm; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt
```

## Engine

The released v1.4.0 (`sideeye 1.4.0 (trace contract v17)`) and main `d5911cd`
(`sideeye 1.4.0 (trace contract v18)`), both mounted into a `--privileged`, `--network none`
container (`SELECTION.md`, "Which build").

## Refusals

`preflight`, each mode named with `--observe`. `--observe supervised` was not run.

| Build | Mode | `unknown_reason` | Transcript (`transcripts/screen/pass1/`) |
|---|---|---|---|
| v1.4.0 | wrappers | `oracle_missed_operation` (operation 3, a `write` to `f.bin.zst`) | `zstd.140.wrappers.txt` |
| v1.4.0 | syscalls | `multiple_threads_detected` | `zstd.140.syscalls.txt` |
| main d5911cd | wrappers | `oracle_missed_operation` | `zstd.main.wrappers.txt` |
| main d5911cd | syscalls | `multiple_threads_detected` | `zstd.main.syscalls.txt` |

## Environment the driver exported (not part of this define)

`apparatus/screen.sh` line 29, with `AUX=/localrun/aux`:

```
export HOME=$AUX/home BUN_INSTALL_CACHE_DIR=$AUX/bun-cache TMPDIR=$AUX/tmp npm_config_update_notifier=false
```

The engine and the operation inherited it. Nothing here sets it: `seed.sh` runs in its own
shell and cannot export into the engine's environment.

## Changed from the original

- The state directory is `/s/zstd/state` (was `/localrun/st/<build>-<mode>/zstd`), and the
  operation's absolute path moved with it.
- `cwd` is declared as the state directory. The original declared none and started Sideeye from
  inside the state directory, so the commands ran there.
- The seed runs as `seed.sh` before the engine, not as the engine's `--setup`; its
  empty-the-directory loop is replaced by `rm -rf` and `mkdir -p`.
- The setup's copy of the input, `/localrun/aux/f.bin.orig`, is written to
  `/s/zstd/aux/f.bin.orig`. Nothing reads it: it was there for a checker this screen never had.
- The exported environment above is not carried.

The seed's bytes were compared with the original setup's: `f.bin` is 1,100,000 bytes, sha256
`e69ebe0fe9911ef6b07cb9d88f8ac08d543abb3c9e980e371a67ff84d7d5a19c`, from both.
