# npm pkg set — where this define comes from

Copied from the 2026-09-16 crossed-walls screen, first pass, where the target is named `npm`
(`npm pkg set` on the record's pages). One form only.

## Source

Paths under `spike/dogfood/2026-09-16-crossed-walls/`.

- seed: `apparatus/screen.sh` lines 113–118 (`setup-npm.sh`)
- operation: `apparatus/screen.sh` line 160 — `screen npm setup-npm.sh 'npm pkg set description=second --prefix @SD@'`
- how it ran: `apparatus/screen.sh` lines 140–142 — `sideeye preflight --state "$SD" --setup …
  --operation … --shim … --oracle /usr/bin/strace --observe <mode>`, started from inside the
  state directory (`cd "$SD"`), with no `--cwd` and no `--check`
- checker: none. The screen ran `preflight` only; npm never reached `explore` in that run.

## Tool

npm 9.2.0 on Node v20.19.2 (`transcripts/screen/screen-summary.txt`,
`transcripts/meta/environment.txt`), both Debian trixie's packages. `apparatus/Dockerfile.screen`
lines 9–11:

```
RUN for p in zstd pigz lz4 ninja-build git yadm git-annex nodejs npm; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt
```

The image also ran `npm config set registry https://registry.npmjs.org/` and
`npm config set strict-ssl false` (lines 14–15), which write root's `.npmrc` at build time. The
screen ran with `HOME` pointed elsewhere (below), so npm's user-level `.npmrc` was looked for at
a different path. Read from the scripts; which file npm opened was not measured.

## Engine

The released v1.4.0 (`sideeye 1.4.0 (trace contract v17)`) and main `d5911cd`
(`sideeye 1.4.0 (trace contract v18)`), both mounted into a `--privileged`, `--network none`
container (`SELECTION.md`, "Which build").

## Refusals

`preflight`, each mode named with `--observe`. `--observe supervised` was not run.

| Build | Mode | `unknown_reason` | Transcript (`transcripts/screen/pass1/`) |
|---|---|---|---|
| v1.4.0 | wrappers | `multiple_threads_detected` | `npm.140.wrappers.txt` |
| v1.4.0 | syscalls | `multiple_threads_detected` | `npm.140.syscalls.txt` |
| main d5911cd | wrappers | `multiple_threads_detected` | `npm.main.wrappers.txt` |
| main d5911cd | syscalls | `multiple_threads_detected` | `npm.main.syscalls.txt` |

Each names one thread's `open` of `package.json` and another's `write`.

## Environment the driver exported (not part of this define)

`apparatus/screen.sh` line 29, with `AUX=/localrun/aux`:

```
export HOME=$AUX/home BUN_INSTALL_CACHE_DIR=$AUX/bun-cache TMPDIR=$AUX/tmp npm_config_update_notifier=false
```

The engine and the operation inherited it; `HOME` was a new, empty directory. **This is the
target the export was most plainly written for**: by npm's defaults its debug log and its
update-notifier stamp go under `$HOME/.npm` and its user configuration is `$HOME/.npmrc` — the
screen's strace saw both the log and the stamp opened (`transcripts/screen/screen-summary.txt`)
— and `npm_config_update_notifier=false` turns the update check off. Nothing here sets any of
it: `seed.sh` runs in its own shell and cannot export into the engine's environment. What npm
does without these variables in a `--network none` box was not measured.

## Changed from the original

- The state directory is `/s/npm-pkg-set/state` (was `/localrun/st/<build>-<mode>/npm`), and
  the operation's `--prefix` moved with it.
- `cwd` is declared as the state directory. The original declared none and started Sideeye from
  inside the state directory, so the commands ran there.
- The seed runs as `seed.sh` before the engine, not as the engine's `--setup`.
- The exported environment above is not carried.

The seed's bytes were compared with the original setup's: `package.json` is 75 bytes, sha256
`95b3e490b5cec86c2b53273c3b3e71b5319274e98e64c48c9e3f5182a00a4814`, from both.
