# Results — 2026-10-10, the targets that check a mode, on #678's build

#678: restore put back names, bytes and link targets and not permission bits, so a target whose behaviour
depends on a mode under `--state` ran its second run and its worlds from 0644 where its recording had the
setup's mode, and `preflight --twice` refused it. The 2026-10-03 run met two such tools and built a probe
with no target (`spike/dogfood/2026-10-03-user-data/`). All three were run again on the build under test —
branch `auto/b_cc4c998976e3-b` at `e9d5bfb9` with #678's working tree, built for aarch64 Linux
(`sideeye version` says 1.10.0, the version this build inherits; it is not the release; the base and the
sha256 of the `src`/`shim` diff and of the two binaries are in `transcripts/build.txt`) — with the defines
that run used, copied unchanged into `apparatus/defines/` (the probe's `run.sh` command is its toml here).

`apparatus/run.sh` does what that run did first — `preflight --twice` with the strace oracle, asked again
under `--observe supervised` when the default refusal names that mode, as the 2026-10-03 `entry.sh` did for
a static image — and then the page's `explore --config … --oracle /usr/bin/strace --json`, following the
next step once. The box (`apparatus/Dockerfile`) holds the two tools from the release assets that run used
(`/downloads.sha256`) and no engine.

| target | 2026-10-03 (v1.7.0) | `preflight --twice` here | explore here |
|---|---|---|---|
| the mode-bit probe (a 0755 script in the state) | `recording_run_failed`: the second run could not exec it, and it was 0644 afterwards | **recording accepted**, 4 operations; still 0755 afterwards | UNKNOWN `nothing_could_fail`: it only creates `log`, and no checker is declared |
| upx 5.2.1 `-q /s/upx/prog` (a copy of `/usr/bin/bash`) | `recording_run_failed` (supervised): `CantPackException: file not executable` | **recording accepted** (supervised), 34 operations; `prog` 0755 afterwards | **FAIL** 1/35 under `--observe supervised` (the step): crash point 34 of 34, after `unlink(prog)` and before `rename(prog.upx)`, `prog` gone |
| argocd 3.5.3 `context work --config config` (a 0600 config) | `recording_run_failed` (supervised): `config file has incorrect permission flags -rw-r--r--` | **recording accepted** (supervised), 2 operations; `config` 0600 afterwards | **FAIL** 1/3 under `--observe supervised` (the step): crash point 2 of 2, `config` opened truncating and killed before its `write`, holding neither content |

Both tools are statically linked (`file -L` in `transcripts/explore/<t>/engine.txt`), so the default mode
refuses them `no_shim_marker` and names `--observe supervised`, as it has since ADR 0090.

The two FAILs are not put forward upstream: neither loses bytes nothing gives back. upx's compressed copy
stays beside the missing name as `prog.upx`; argocd's config holds login state a user re-establishes by
logging in again.

Not run: dotter 0.13.5, whose `kill_did_not_land` #690 measured as a cache kept outside the state, not a
mode; upx on a FAT mount (`docs/target-classes.md`), which needs a loop-mounted filesystem this box does not
have.

ADR 0109's cost reading — an explore over 2,000 state files, before and after, three pairs — is
`apparatus/cost.sh` and `transcripts/cost.txt`.

Records: `transcripts/build.txt`; `transcripts/explore/<t>/{twice,twice-supervised}.{txt,rc}` with the
state listed before and after, `{default,followed}.{txt,json,rc}`, `engine.txt`, `seed-*.log`; `transcripts/cost.txt`.
