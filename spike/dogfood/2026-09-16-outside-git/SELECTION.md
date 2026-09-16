# 2026-09-16 — outside git: selection

The brief: five more targets, weighted to state a user keeps **outside version control** — a
credentials file, editor history, a vault cache, user configuration. The crossed-walls run earlier
the same day (`../2026-09-16-crossed-walls/`) reached three more truncating rewrites, all of files
that live in git, and none was worth reporting upstream on that ground. The owner's call for these
five was to look where a crash loses something git does not hold, preferring the classes that
day's walls opened: Node writing synchronously, the JVM, the syscall observer, a cgroup for
detached processes.

## Which build

- **The released v1.4.0**: `sideeye-v1.4.0-aarch64-linux.tar.gz`, sha256
  `709057371894565cbfc368cd2cc3402282f65f453520acb5cb4e9a2fb5b08820`, matched against the digest
  the release publishes (`transcripts/meta/environment.txt`). Prints
  `sideeye 1.4.0 (trace contract v17)`. Every verdict below is stated from it.
- **main `047592d`**, cross-built with the release workflow's flags (`zig build
  -Doptimize=ReleaseSafe -Dtarget=aarch64-linux-gnu.2.28`); prints `(trace contract v18)`. Not a
  release. It differs from the crossed-walls run's `d5911cd` by that run's record only.

Linux in Docker (Debian trixie, aarch64), as root in a `--privileged` container, state and work on
the container's own filesystem (#528).

**Added after the first review**: neovim's latest release, v0.12.5 (`apparatus/Dockerfile.nvim012`,
the release tarball's digest matched the published one, `transcripts/meta/environment.txt`), beside
Debian's 0.10.4 — the review read in neovim's source that
0.11 and later write the shada file differently (`RESULTS.md`).

**The aws-cli credentials in the scripts and transcripts are substitutes** for the fabricated
AWS-shaped keys the run used, replaced in every commit before the first push (`BUILDLOG.md`).

## Candidates, and what removed three of them

`apparatus/repo-meta.sh` → `transcripts/meta/repos.txt`, `apparatus/rule11-github.py` →
`transcripts/meta/rule11.txt`. None of the candidates appears in an earlier dogfood selection,
`docs/target-classes.md`, `spike/cohort4/CANDIDATES-REJECTED.md` or
`spike/unknown-rate/b-exclusions.txt`.

| Candidate | State outside git | ★ | Commits (6 mo) | Rule 11 (reports ≥ 7 days old, not by the repo's own people) | Taken |
|---|---|---|---|---|---|
| aws-cli (`aws configure set`) | `credentials` / `config` | 17,259 | 100, most by the release bot | 2 of 4 answered within ~1 day | ✅ |
| hatch (`hatch config set`) | user `config.toml` | 7,236 | 66 | 1 of 4 | ✅ |
| neovim (`:wshada`) | `main.shada` — command history, registers, marks | 102,361 | 100 | none old enough in the 60 most recent items | ✅ |
| jbang (`jbang config set`) | `jbang.properties` | 1,863 | 100 (maxandersen 56, quintesse 8, …) | 2 of 4 | ✅ |
| Bitwarden CLI (`bw config server`) | `data.json` — the vault cache and login | 13,791 | 100 | none old enough | screened (below) |
| pyenv (`pyenv global`) | `version` | 45,104 | 100 | 1 of 4 | ✅ (the spare) |
| GnuPG (`gpg --import`) | the keyring | **977** (a GitHub mirror, issues off) | — | unmeasurable | ❌ **rules 1, 11** — the one candidate that would have exercised the cgroup: gpg starts keyboxd or the agent detached |
| pm2 (`pm2 save`) | the process dump | 43,291 | 62, **all one author's** | — | ❌ **rule 3** |
| Angular CLI (`ng config -g`) | `~/.angular-config.json` | 27,023 | 100 | — | ❌ — not on the rules: the first screen measured that it refuses Node 20.19.2, the version Debian trixie ships ("requires a minimum Node.js version of v22.22.3", `transcripts/screen/pass1-faulted/screen-summary.txt`) |

## The measured screen, before the slate

strace (`screen-strace.py`: threads, processes, `setsid`/`setpgid`, which tids wrote the state)
and `sideeye preflight --oracle strace` under both builds and both observation modes.
Transcripts: `transcripts/screen/pass1/`, `pass2/`; the faulted first pass is kept as
`pass1-faulted/`. Scripts `apparatus/screen.sh`, `screen2.sh`.

| Candidate | Threads / processes | v1.4.0 wrappers | v1.4.0 syscalls | main wrappers | main syscalls |
|---|---|---|---|---|---|
| **aws-cli 2.23.6** | 1 / 16 (none of the 16 touched the state) | accepted, 2 ops | accepted | accepted | accepted |
| **hatch 1.18.0** | 0 / 0 | accepted, 5 ops | accepted | accepted | accepted |
| **neovim 0.10.4** | 0 / 0 | accepted, 12 ops | accepted | accepted | accepted |
| jbang 0.141.0 through its bash launcher | 19 / 11 | `child_touched_state_dir` | same | same | same |
| **jbang 0.141.0, the JVM named directly** (pass 2) | 20 / 0 | accepted, 2 ops | accepted | accepted | accepted |
| Bitwarden CLI 2026.8.0 | 10 / 0 | `multiple_threads_detected` | same | same, *"No thread creation or join the shim recorded orders the first of those before the second"* | same |
| **pyenv 2.8.5** | 0 / 14 | `state_changed_without_ops` | **accepted, 3 ops** | `state_changed_without_ops` | **accepted, 3 ops** |

What the screen produced that reading would not have:

- **jbang's launcher is a wall its jar is not.** The `jbang` script runs `java -jar jbang.jar`
  as a child inside `$(...)` and execs what that prints; the java child's writing thread is not
  its main one, and the run refuses `child_touched_state_dir`. Named directly, the same JVM is one
  process with one writing thread among twenty, and is accepted. `docs/cli.md`: *"Naming an
  executable image directly takes the question away."*
- **The Bitwarden CLI is the Node asynchronous class.** `data.json.lock` is made and removed by
  threads other than the main one; the write of `data.json` itself is the main thread's.
- **aws-cli starts 16 processes** (`lsb_release`, `uname`, `getopt`, `tr`, `cut` among them) and
  none touches the state; the engine attributes a FAIL's window to the subject only and says so.

## Faults in the screen itself

- **The first pass ran the operation under `sh -c` for strace and split it on spaces for the
  engine**, and neovim's define quoted its `-c` commands. `docs/cli.md` says command strings are
  split on spaces with no quoting: under the engine nvim received `"call`, `histadd(\"cmd\",` and
  `"qa!"` as separate words and waited in `epoll_wait` until the container was stopped, a little
  over ten minutes in. Those readings — `ps`, `/proc/<pid>/cmdline`, `/proc/<pid>/wchan` — were
  taken by hand before stopping it and were not kept; what `pass1-faulted/` holds is the empty
  `nvim.140.wrappers.txt` the stopped preflight left. The screen now splits both halves the
  engine's way, passes neovim's commands as a script file (`-S`), and runs `preflight` under
  `timeout 600`.
- **hatch's first setup ran `hatch config restore` on a path that did not exist**, which it
  refuses; the file is created empty first.
- **Two checker faults, caught by `apparatus/probe-checkers.sh` before any exploration** (every
  checker on the setup's state, the completed operation's state, and the state file emptied;
  `transcripts/probes/checkers.txt`). neovim's first checker read nothing through `-i NONE` and
  `:rshada!` and failed on correct states; it reads through `-i` and clears `'shada'` before
  quitting, and the probe shows the file unchanged after a check. hatch's operation set
  `terminal.styles.info` to `bold`, the default, so the file was rewritten and no value changed;
  it sets `italic`.

## The slate

| # | Target | Language | State | The single operation measured |
|---|---|---|---|---|
| 1 | aws-cli 2.23.6 | Python | `credentials`, two profiles | `aws configure set aws_secret_access_key … --profile work` |
| 2 | hatch 1.18.0 | Python | `config.toml` | `hatch config set terminal.styles.info italic` |
| 3 | neovim 0.10.4 | C | `main.shada` | `nvim --headless -n -u NONE -i <state>/main.shada -S op.vim` (adds a history entry, `:wshada`, quits) |
| 4 | jbang 0.141.0 (OpenJDK 21.0.12.1) | Java | `jbang.properties` | `java -jar jbang.jar config set second.key second-value` |
| 5 | pyenv 2.8.5 | Bash | `version` | `pyenv global 3.12.4` (two installed versions faked as directories) |
