# lz4 — where this define comes from

Copied from the 2026-09-16 crossed-walls screen, **second pass** — the form `SELECTION.md`'s
table records (`lz4 1.10.0 -T2 --rm, 5,750,000 bytes (pass 2)`).

## Source

Paths under `spike/dogfood/2026-09-16-crossed-walls/`.

- seed: `apparatus/screen2.sh` lines 44–56 (`setup-lz4.sh`)
- operation: `apparatus/screen2.sh` line 110 — `screen lz4 setup-lz4.sh 'lz4 -q -T2 --rm @SD@/f.bin'`
- how it ran: `apparatus/screen2.sh` lines 96–98 — `sideeye preflight --state "$SD" --setup …
  --operation … --shim … --oracle /usr/bin/strace --observe <mode>`, started from inside the
  state directory (`cd "$SD"`), with no `--cwd` and no `--check`
- checker: none. The screen ran `preflight` only; lz4 never reached `explore` in that run.

## The other form, not copied

The first pass (`apparatus/screen.sh` lines 55–69 and line 155) ran
`lz4 -q -B4 -T2 --rm @SD@/f.bin` over a 1,100,000-byte file. lz4 1.10 starts no worker for a
file that small, so that pass measured a single-threaded lz4: `oracle_missed_operation` under
wrappers, **accepted, 4 operations** under syscalls (`transcripts/screen/pass1/lz4.*.txt`).
`SELECTION.md` ("lz4 starts no workers for a small file") replaced it with the second pass.

## Tool

lz4 1.10.0 (`*** lz4 v1.10.0 64-bit multithread, by Yann Collet ***`,
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

| Build | Mode | `unknown_reason` | Transcript (`transcripts/screen/pass2/`) |
|---|---|---|---|
| v1.4.0 | wrappers | `oracle_missed_operation` (operation 3, a 942,080-byte `write` to `f.bin.lz4`) | `lz4.140.wrappers.txt` |
| v1.4.0 | syscalls | `multiple_threads_detected` | `lz4.140.syscalls.txt` |
| main d5911cd | wrappers | `oracle_missed_operation` | `lz4.main.wrappers.txt` |
| main d5911cd | syscalls | `multiple_threads_detected` | `lz4.main.syscalls.txt` |

Summary of all four: `transcripts/screen/screen2-summary.txt`.

## Environment the driver exported (not part of this define)

`apparatus/screen2.sh` line 26, with `AUX=/localrun/aux`:

```
export HOME=$AUX/home TMPDIR=$AUX/tmp
```

The engine and the operation inherited it. Nothing here sets it: `seed.sh` runs in its own
shell and cannot export into the engine's environment.

## Changed from the original

- The state directory is `/s/lz4/state` (was `/localrun/st/<build>-<mode>/lz4`), and the
  operation's absolute path moved with it.
- `cwd` is declared as the state directory. The original declared none and started Sideeye from
  inside the state directory, so the commands ran there.
- The seed runs as `seed.sh` before the engine, not as the engine's `--setup`; its
  empty-the-directory loop is replaced by `rm -rf` and `mkdir -p`.
- The setup's copy of the input, `/localrun/aux/lz4.orig`, is written to `/s/lz4/aux/lz4.orig`.
  Nothing reads it: it was there for a checker this screen never had.
- The exported environment above is not carried.

The seed's bytes were compared with the original setup's: `f.bin` is 5,750,000 bytes, sha256
`685a9bee60bd1eda808b37fe9e7defe96d3e71b221f3cc2d4269915f3e84942a`, from both.
