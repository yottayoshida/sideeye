# Bitwarden CLI — where this define comes from

Copied from the 2026-09-16 outside-git screen, first pass, where the target is named `bw`
(`Bitwarden CLI` on the record's pages). One form only.

## Source

Paths under `spike/dogfood/2026-09-16-outside-git/`.

- seed: `apparatus/screen.sh` lines 78–83 (`setup-bw.sh`) — the tool itself writes the first
  `data.json`: `bw config server https://first.example.invalid`
- operation: `apparatus/screen.sh` line 132 —
  `screen bw setup-bw.sh 'env BITWARDENCLI_APPDATA_DIR=@SD@ bw config server https://second.example.invalid'`
- how it ran: `apparatus/screen.sh` lines 113–115 — `timeout 600 sideeye preflight --state "$SD"
  --setup … --operation … --shim … --oracle /usr/bin/strace --observe <mode>`, started from
  inside the state directory (`cd "$SD"`), with no `--cwd` and no `--check`
- checker: none. The screen ran `preflight` only; the Bitwarden CLI never reached `explore`.

No server and no login are involved: `bw config server` only records a URL, and both the setup
and the operation completed in the original's `--network none` container (operation exit 0,
`Saved setting \`config\`.`, `transcripts/screen/pass1/bw.op.txt`).

The variable is passed the way the original passed it, as `env NAME=value` at the head of the
operation. `docs/cli.md` gives a define no way to set a variable (`apparatus` declares and
checks one, it does not apply it).

## Tool

Bitwarden CLI 2026.8.0 on Node v20.19.2 (`transcripts/meta/environment.txt`;
`SELECTION.md`'s screen table). Node and npm are Debian trixie's packages; the CLI came from npm
with no version pinned, so 2026.8.0 is what the registry served on 2026-09-16.
`apparatus/Dockerfile` lines 9–11 and 19–21:

```
RUN for p in awscli neovim openjdk-21-jdk-headless nodejs npm python3-pip; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt
```

```
RUN npm config set registry https://registry.npmjs.org/ \
 && npm config set strict-ssl false \
 && npm install -g @bitwarden/cli @angular/cli > /tmp/npm-install.log 2>&1; tail -3 /tmp/npm-install.log
```

## Engine

The released v1.4.0 (`sideeye 1.4.0 (trace contract v17)`) and main `047592d`
(`sideeye 1.4.0 (trace contract v18)`), both mounted into a `--privileged`, `--network none`
container (`SELECTION.md`, "Which build").

## Refusals

`preflight`, each mode named with `--observe`. `--observe supervised` was not run.

| Build | Mode | `unknown_reason` | Transcript (`transcripts/screen/pass1/`) |
|---|---|---|---|
| v1.4.0 | wrappers | `multiple_threads_detected` | `bw.140.wrappers.txt` |
| v1.4.0 | syscalls | `multiple_threads_detected` | `bw.140.syscalls.txt` |
| main 047592d | wrappers | `multiple_threads_detected` | `bw.main.wrappers.txt` |
| main 047592d | syscalls | `multiple_threads_detected` | `bw.main.syscalls.txt` |

Each names one thread's `mkdir` of `data.json.lock` and another's `rmdir` of it. The write of
`data.json` itself is the main thread's (`transcripts/screen/pass1/screen-summary.txt`).

## Environment the driver exported (not part of this define)

`apparatus/screen.sh` lines 32–33, with `AUX=/localrun/aux`:

```
export HOME=$AUX/home TMPDIR=$AUX/tmp XDG_STATE_HOME=$AUX/state XDG_DATA_HOME=$AUX/data \
       XDG_CACHE_HOME=$AUX/cache NG_CLI_ANALYTICS=false JBANG_NO_VERSION_CHECK=true
```

The engine, the setup and the operation inherited it; `HOME` was a new, empty directory.
Nothing here sets it: `seed.sh` runs in its own shell and cannot export into the engine's
environment. Whether the CLI reads any of these once `BITWARDENCLI_APPDATA_DIR` is set was not
measured.

## Changed from the original

- The state directory is `/s/bitwarden/state` (was `/localrun/st/<build>-<mode>/bw`), and the
  `BITWARDENCLI_APPDATA_DIR` value in the seed and in the operation moved with it.
- `cwd` is declared as the state directory. The original declared none and started Sideeye from
  inside the state directory, so the commands ran there.
- The seed runs as `seed.sh` before the engine, not as the engine's `--setup`.
- The original ran each `preflight` under `timeout 600`; nothing here carries a time limit.
- The exported environment above is not carried.

The seed's bytes were not compared with the original's: the seed is the tool's own output, and
the tool is not installed where this was written.
