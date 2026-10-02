# svgo — where this define comes from

Copied from the 2026-09-16 crossed-walls screen, first pass. One form only.

## Source

Paths under `spike/dogfood/2026-09-16-crossed-walls/`.

- seed: `apparatus/screen.sh` lines 89–104 (`setup-svgo.sh`)
- operation: `apparatus/screen.sh` line 158 — `screen svgo setup-svgo.sh 'svgo -q @SD@/a.svg'`
- how it ran: `apparatus/screen.sh` lines 140–142 — `sideeye preflight --state "$SD" --setup …
  --operation … --shim … --oracle /usr/bin/strace --observe <mode>`, started from inside the
  state directory (`cd "$SD"`), with no `--cwd` and no `--check`
- checker: none. The screen ran `preflight` only; svgo never reached `explore` in that run.

## Tool

svgo 4.1.0 on Node v20.19.2 (`transcripts/screen/screen-summary.txt`,
`transcripts/meta/environment.txt`). Node and npm are Debian trixie's packages; svgo came from
npm with no version pinned, so 4.1.0 is what the registry served on 2026-09-16.
`apparatus/Dockerfile.screen` lines 9–11 and 14–17:

```
RUN for p in zstd pigz lz4 ninja-build git yadm git-annex nodejs npm; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt
```

```
RUN npm config set registry https://registry.npmjs.org/ \
 && npm config set strict-ssl false \
 && npm install -g prettier svgo markdownlint-cli > /tmp/npm-install.log 2>&1; \
    tail -3 /tmp/npm-install.log
```

## Engine

The released v1.4.0 (`sideeye 1.4.0 (trace contract v17)`) and main `d5911cd`
(`sideeye 1.4.0 (trace contract v18)`), both mounted into a `--privileged`, `--network none`
container (`SELECTION.md`, "Which build").

## Refusals

`preflight`, each mode named with `--observe`. `--observe supervised` was not run.

| Build | Mode | `unknown_reason` | Transcript (`transcripts/screen/pass1/`) |
|---|---|---|---|
| v1.4.0 | wrappers | `multiple_threads_detected` | `svgo.140.wrappers.txt` |
| v1.4.0 | syscalls | `multiple_threads_detected` | `svgo.140.syscalls.txt` |
| main d5911cd | wrappers | `multiple_threads_detected` | `svgo.main.wrappers.txt` |
| main d5911cd | syscalls | `multiple_threads_detected` | `svgo.main.syscalls.txt` |

Each names one thread's `mkdir` of the state directory itself and another's `open` of `a.svg`.

## Environment the driver exported (not part of this define)

`apparatus/screen.sh` line 29, with `AUX=/localrun/aux`:

```
export HOME=$AUX/home BUN_INSTALL_CACHE_DIR=$AUX/bun-cache TMPDIR=$AUX/tmp npm_config_update_notifier=false
```

The engine and the operation inherited it; `HOME` was a new, empty directory. Nothing here
sets it: `seed.sh` runs in its own shell and cannot export into the engine's environment.

## Changed from the original

- The state directory is `/s/svgo/state` (was `/localrun/st/<build>-<mode>/svgo`), and the
  operation's absolute path moved with it.
- `cwd` is declared as the state directory. The original declared none and started Sideeye from
  inside the state directory, so the commands ran there.
- The seed runs as `seed.sh` before the engine, not as the engine's `--setup`.
- The exported environment above is not carried.

The seed's bytes were compared with the original setup's: `a.svg` is 358 bytes, sha256
`3f809442b237dc87a119f4d79c21fe5c6bb0a84656f6dc785bb19d5b14bd643d`, from both.
