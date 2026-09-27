# Selection — 2026-09-27 supervised-static

The static-linkage wall in `docs/target-classes.md` names five real tools: Jujutsu, chezmoi and gopass (one row),
lefthook, each in the "Refusals that are the correct answer" table, and `gh` (the "Static binaries" clause under the
tables). `--observe supervised` (#217, ADR 0089, PR #663) counts a statically linked target from
outside the process; until this run it had been measured on a toy only, and the page says so and
says the rows move only when a real tool is re-measured. This run re-measures them. It is the
same shape as 2026-09-11's re-measurement of targets a wall had refused: **the denominator is
fixed by the page, not by taste.**

## The denominator: seven targets

| # | target | why it is here | the row's mode |
|---|---|---|---|
| 1 | Jujutsu 0.44.0, `jj commit` | the Jujutsu row | wrappers |
| 2 | chezmoi 2.72.1, `chezmoi apply` | the chezmoi/gopass row | wrappers |
| 3 | gopass 1.17.0, `gopass generate` | the chezmoi/gopass row | wrappers |
| 4 | `gh` 2.97.0, `gh config set` | "Static binaries" clause | wrappers |
| 5 | lefthook 1.13.6, `lefthook install` | the lefthook row | **syscalls** (the row was measured there) |
| 6 | busybox-static `sed -i`, run directly | declared before measuring (below) | wrappers |
| 7 | busybox-static `sed -i`, run by a dynamic `/bin/sh` that `exec`s it | declared before measuring (below) | **syscalls** |

Measured and recorded but **outside the denominator and outside #217's closing condition**:
lefthook `install` reached through a dynamic `/bin/sh` that `exec`s it (`lefthook-sh`), the Go
counterpart of #7.

**Why #6 and #7 were added, said plainly: because they are likely to reach a verdict.** The four
Go tools are expected to meet the thread wall this mode keeps (`multiple_threads_detected`; mlr
did in five of six runs) and Jujutsu is the only non-Go tool among the five, so the page's own
list could leave #217's closing condition — "at least one target the current engine refuses as
`no_shim_marker` reaches a verdict under supervised" — resting on one tool. busybox-static is a
statically linked, single-threaded C program Debian ships, and `sed -i` rewrites a file in place
(write a temporary, rename over), which is the class Sideeye judges. Considered for the same
purpose and not taken: a static toy (that is what PR #663 already measured — the question here is
real tools); `busybox-static`'s other applets (`sed -i` is the one that rewrites a file the user
named). No wider search for static C tools was made.

**#7 is the "structurally unsafe in-process" target** #217's condition asks for. Under
`--observe syscalls` the shim installs its seccomp filter in the dynamic `sh`; `exec` keeps the
filter and drops the shim's handler, so the static busybox is killed by SIGSYS on its first
trapped call (the contract-v14 wall, pinned on a toy in `spike/acceptance.sh`). It passes only
when the strace capture shows `--- SIGSYS {... si_code=SYS_SECCOMP` on the busybox pid and the run
refuses `recording_run_failed`. `sh` rather than npm's lefthook (node execs the binary) so that no
libuv thread pool comes along. The plan's `sh -c "busybox sed -i …"` is spelled as a script
(`apparatus/bbsed.sh`, `exec /bin/busybox sed -i …`) because a define given as flags splits on
spaces with no quoting (`docs/cli.md`) and `preflight` takes flags only.

## Measured before this table (the ordering rule)

`transcripts/<target>/entry-*.txt`, one run each in the box, by `apparatus/run.sh <target> entry`:
`file -L` on the operation's first word, then one `preflight --twice --oracle /usr/bin/strace` in
the mode the row was measured in.

| target | `file -L` | the row reproduced? |
|---|---|---|
| jj | statically linked | yes — `no_shim_marker` |
| chezmoi | statically linked | yes — `no_shim_marker` |
| gopass | statically linked | yes — `no_shim_marker` |
| gh | statically linked | yes — `no_shim_marker` |
| lefthook | statically linked | yes — `oracle_missed_operation` under `--observe syscalls` |
| busybox `sed -i` | statically linked | `no_shim_marker` (no row before; the refusal names `--observe supervised`) |
| sh → busybox `sed -i` | `/bin/sh` dynamically linked | `recording_run_failed` under `--observe syscalls`, and the capture has one `--- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, … si_syscall=__NR_openat …}` on pid 34, the pid that `execve`d `/bin/busybox` (`transcripts/shbb/entry-oracle.txt` lines 54–59) |

Every row the page carries reproduced before it moves.

## Versions and digests

`apparatus/build.sh` checks each release file against the digest its project publishes before
copying it in (`transcripts/build.txt`): `gh_2.97.0_checksums.txt`, `chezmoi_2.72.1_checksums.txt`,
`gopass_1.17.0_SHA256SUMS`, `lefthook_checksums.txt`, and for Jujutsu the value `spike/cohort2`
pinned. busybox-static is Debian bookworm's `1:1.35.0-4+deb12u1+b1`, installed at that version.
The versions are the rows' own. The Jujutsu row calls 0.44.0 "the latest stable, so the recheck is
inherent" — that is no longer a claim this run tests; 0.44.0 is held fixed so only the engine
changes.

## Where each define comes from

| target | define | source |
|---|---|---|
| jj | `jj -R /tmp/cohort2/jj/repo commit -m probe`, setup and checker as committed, the JJ_* pins | `spike/cohort2/jj/ops/` (copied to `apparatus/jj/`) |
| chezmoi | `chezmoi apply --source /tmp/cz/src --destination /tmp/cz/dest --no-tty`; setup clears chezmoi's own state under `$HOME` | `2026-09-05-userview/apparatus/run-preflight2.sh` |
| gopass | `gopass generate --print=false test/generated 20` over an age/fs store made once and copied in by setup | `2026-09-05-userview/apparatus/run-preflight4.sh` |
| gh | `gh config set git_protocol ssh` with `GH_CONFIG_DIR` the judged root | `spike/go-target/gh-2.97.0.txt` |
| lefthook | `lefthook install`, state `.git/hooks`, `cwd` the repository, seed and checker as committed | `2026-09-21-release-path/apparatus/` (copied to `apparatus/lefthook/`) |
| busybox, direct and via sh | `busybox sed -i s/a/z/ f.txt` over a three-line file | new |

Every operation names its image by absolute path (the refusal text names the linkage only then —
the chezmoi/gopass row). jj, chezmoi, gopass and gh use built-in atomicity except where a checker is named above.

## Deviations, declared

- **Not a shipped build.** The README's "which build a run measures" rule says the release;
  `--observe supervised` is not released. The engine is built from `main` at `01e6760` (the merge of
  PR #664) in the box, ReleaseSafe; binary sha256 `ccb81449…` and shim `8c627c19…`
  (`transcripts/build.txt`). It prints `sideeye 1.6.0` because the version has not been bumped.
- **aarch64 only** (Docker Desktop, linuxkit), privileged, its own cgroup namespace, `--network none`.
- **Repeats**: each target's `preflight --twice --observe supervised --oracle` five times; three
  explores under the same flags when at least one was accepted. Only 5 of 5 accepted and three
  explores with one verdict count toward #217's closing condition; a mix of PASS and FAIL across
  the three does not count as reaching a verdict; an explore that refuses in a world is a refusal.
