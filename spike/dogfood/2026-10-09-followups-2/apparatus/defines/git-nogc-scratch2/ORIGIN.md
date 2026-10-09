# git — where this define comes from

The commit that starts automatic maintenance. Copied from the 2026-09-16 crossed-walls screen,
second pass. One form only.

## Source

Paths under `spike/dogfood/2026-09-16-crossed-walls/`.

- seed: `apparatus/screen2.sh` lines 58–75 (`setup-git.sh`): three commits, each repacked, so
  three packs stand against `gc.autoPackLimit=2`, and one staged change
- operation: `apparatus/screen2.sh` line 111 — `screen git setup-git.sh 'git -C @SD@ commit -q -m second'`
- how it ran: `apparatus/screen2.sh` lines 96–98 — `sideeye preflight --state "$SD" --setup …
  --operation … --shim … --oracle /usr/bin/strace --observe <mode>`, started from inside the
  state directory (`cd "$SD"`), with no `--cwd` and no `--check`
- checker: none. The screen ran `preflight` only; no exploration
  (`docs/target-classes.md`, "Commits that start automatic maintenance").

The state directory is the whole work tree, `.git` included.

## Tool

git 2.47.3 (`git version 2.47.3`, `transcripts/screen/screen2-summary.txt`), Debian trixie's
package. `apparatus/Dockerfile.screen` lines 9–11:

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
| v1.4.0 | wrappers | `child_touched_state_dir` | `git.140.wrappers.txt` |
| v1.4.0 | syscalls | `child_touched_state_dir` | `git.140.syscalls.txt` |
| main d5911cd | wrappers | `child_touched_state_dir` | `git.main.wrappers.txt` |
| main d5911cd | syscalls | `child_touched_state_dir` | `git.main.syscalls.txt` |

`git.140.wrappers.txt` names a process other than the subject opening `.git/gc.pid.lock` while
another was still writing. The strace reading beside it: 12 processes, one `setsid`
(`transcripts/screen/screen2-summary.txt`).

## Environment the driver exported (not part of this define)

`apparatus/screen2.sh` line 26, with `AUX=/localrun/aux`:

```
export HOME=$AUX/home TMPDIR=$AUX/tmp
```

The engine, the setup and the operation inherited it; `HOME` was a new, empty directory, so git
read no user-level configuration. Nothing here sets it: `seed.sh` runs in its own shell and
cannot export into the engine's environment. A box whose `HOME` holds a `.gitconfig` would
change what both the seed and the operation do.

## Changed from the original

- The state directory is `/s/git/state` (was `/localrun/st/<build>-<mode>/git`), and the
  operation's `-C` moved with it.
- `cwd` is declared as the state directory. The original declared none and started Sideeye from
  inside the state directory, so the commands ran there.
- The seed runs as `seed.sh` before the engine, not as the engine's `--setup`. Its commands
  after the `cd` are the original's, line for line (compared with `diff`).
- The exported environment above is not carried.

The seed's bytes cannot be compared across runs: each seeding makes new commits with the
current time, so object and pack names differ every time, as they did in the original.
