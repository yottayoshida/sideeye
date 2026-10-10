# The platform probe — the record behind docs/cli.md's table (#697)

Read by `spike/platforms/RUNS-RULE.md`, committed with the apparatus before this run.

## The runs

One dispatch, and the only one: `spike-platforms.yml` run **38018694987**, `jobs: all`, at
`ebde6c5a` (the merge commit of #777, the apparatus), engine **v1.10.0** installed by
`install-sideeye.sh` (digest checked against the release). All three jobs completed:

| job | runner | conclusion | record |
|---|---|---|---|
| `linux (ubuntu-24.04, x86_64)` | Ubuntu 24.04.5, kernel 6.17.0-1022-azure | success | `x86_64/` |
| `linux (ubuntu-24.04-arm, aarch64)` | the same, aarch64 | success | `aarch64/` |
| `wsl2` | Windows Server 2025 | success | `wsl2/` |

Each directory is the job's artifact as uploaded, unedited: on the Linux runners `runner.txt`,
the install log, `binary.txt`, the Rocky 8 legs' `dnf` logs and the Alpine leg's `apk` log; on
WSL2 `wsl.txt`, `wsl2-kernel.txt` and the package and install logs; per measured leg `env.txt`,
`summary.txt` and the three explores' text and JSON; and for Alpine as shipped only
`alpine-bare/version.txt`. Paths under `/home/runner/work/_temp` are the runner's.
`macos-minos.txt` is not from the run (see below).

## WSL2 started

`wsl2/wsl.txt`: WSL 2.7.14.0 as the runner had it, updated by `wsl --update` to 3.0.1 before the
import; the optional features VirtualMachinePlatform, Microsoft-Windows-Subsystem-Linux and
Microsoft-Hyper-V all `Enabled`; the runner image `windows-2025-vs2026` version 20260925.250.1
(from the job's log, not `wsl.txt`); Ubuntu 24.04's WSL image (sha256 `8251e27f…`) imported with
`--version 2`; `uname -r` → `6.18.40.1-microsoft-standard-WSL2` (6.18.33.2 before the update); **`started: yes`**.
Measured as root and without systemd (`env.txt`'s cgroup line is `/non-systemd`), with the engine
in `/opt` and the state in `/s` on the distribution's own filesystem. `wsl --version` was not
asked again after the update; 3.0.1 is the version `wsl --update` announced.

## The cells

The control is each runner's `host` leg (Ubuntu 24.04, glibc 2.39, dash, uid 1001 inside a
cgroup delegated to it). In all three modes, on both runners, it gave the right answer: FAIL,
the earliest violation after the `open` of `/s/st/a.txt` and before its `write`,
`oracle_verified`, 2 operations agreed. Every cell below that says FAIL is that same FAIL.

| leg | default | `--observe syscalls` | `--observe supervised` |
|---|---|---|---|
| host, x86_64 and aarch64 | FAIL | FAIL | FAIL |
| rocky8-privileged (glibc 2.28, bash, root), both | FAIL | FAIL | FAIL |
| rocky8-defaults (docker's default privileges), both | FAIL | FAIL | SETUP ERROR: "needs a cgroup v2 the engine can create cgroups in" |
| alpine-bare (Alpine 3.22, musl), both | — the binary does not start: `sh: /se/sideeye: not found`, exit 127 | | |
| alpine-gcompat (musl 1.2.5, gcompat, busybox 1.37), both | FAIL | FAIL | UNKNOWN `recording_run_failed` |
| wsl2 (Ubuntu 24.04 in WSL2, x86_64) | FAIL | FAIL | FAIL |

- **Alpine with `gcompat`, supervised**: the refusal says "the operation exited 1 during the
  recording run". The operation did not run: the first line of `explore-supervised.txt`, on both
  CPUs, is musl's loader saying `cannot load __filter-exec: No such file or directory` — the
  engine's own `sideeye __filter-exec` started as that loader asked to load `__filter-exec`.
  Why: under `gcompat`, `/lib/ld-linux-*.so.*` re-executes musl's loader with the program as an
  argument, so `/proc/self/exe` names musl's loader (read on the maintainer's machine on
  2026-10-10, `readlink /proc/<pid>/exe` of a running engine; not in this record).
- **Alpine with `gcompat`, default**: the shim found itself beside the engine (`--shim
  /se/libsideeye_shim.so` in the replay line) and counted dd's `write`.
- **`binary.txt`**: on both CPUs the engine and the shim ask for `GLIBC_2.28` and nothing newer.

## Read against the rules

- The control was the right FAIL in every mode on both runners, so no mode goes back to the
  owner.
- WSL2 started on the first dispatch and agreed with the x86_64 control in all three modes:
  **supported**.
- A container with docker's default privileges agreed in default and syscalls and was a setup
  error in supervised: **supported**, the cell naming each mode.
- Alpine is **declined** on the owner's ruling; its cell records both legs.
- Nothing here was re-run; no apparatus fault occurred.

## Read for the table's other rows

- **macOS**: the probe does not run it. The `aarch64-macos` asset's engine and shim both carry
  `LC_BUILD_VERSION` `minos 13.0` (`macos-minos.txt`: `otool -l` on the maintainer's machine,
  the asset's digest checked, 2026-10-10). The release
  that built v1.10.0 ran its demo on the `macos-26-arm64` image (run 37732954029, job
  `build (aarch64-macos)`), and CI's macOS job runs on the same image (run 38018689655): macOS 26
  is where it has run, 13 to 15 are where it is allowed to and has not.

## What came before, and is not this record

A dry run on the maintainer's machine (aarch64, Docker Desktop) on 2026-10-10 replaced the
define's shell redirect with `dd` (RUNS-RULE.md says why). It is not in the repository and
nothing here rests on it.
The measurement posted on #697 the same morning used the shell redirect and found the default
mode refusing under `gcompat`; that was busybox's `printf`, not musl.
