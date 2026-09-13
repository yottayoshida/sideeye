# #556 follow-up: what takes `SIGSYS` away under `--observe syscalls`

The measurements behind ADR 0063, all taken on 2026-09-13 in Linux containers on an aarch64
host (the x86_64 rows under `--platform linux/amd64`). Paths written `<scratch>` and
`<worktree>` in the transcripts stood for the host's scratch directory and this working tree.

## Telling the builds apart

`sideeye version` prints `1.3.0` for every build here, so the string identifies none of them;
the shim's sha256, printed at the top of each transcript, does.

| build | what it is | shim sha256 (first 16) |
|---|---|---|
| v1.3.0 | the release tarball | `38eb4e277905e92a` |
| main `39da3cf` | where the probes were first run | `b952c105547c7ef1` |
| main `478c954` | this change's base | `fdfe4df477da1e05` |
| this change | the tree the legs, node and mlr ran on | `c3d161a28aafe710` |
| M1 | the removal gone: `withoutSigsys` always answers null | `2940cc135015e381` |
| M2 | #562's guard gone: a request for `SIGSYS` itself is applied | `30a1cdafb5073bc5` |
| M3 | the bit one position off (unit tests only) | — |
| M4 | the whole mask cleared instead of one bit | `8c089c03526cc7be` |

`mutants/mut556a.diff` … `mut556d.diff` are M1 … M4 against `shim/src/syscalls.zig`.

## Images

- `sideeye-spike:latest` — `spike/Dockerfile`: bookworm, glibc 2.36, Python 3.11, gcc.
- `sideeye-reach:2026-09-07` — `spike/followup-item4/Dockerfile`: trixie, glibc 2.41,
  Python 3.13, mlr 6.13.0.
- `sideeye-joplin:2026-09-13` — `spike/dogfood/2026-09-13-joplin-turns/apparatus/Dockerfile`,
  which arrives with a separate pull request (#558): trixie, glibc 2.41, node 20.19.2, gcc.
- `debian:bullseye-slim` — glibc 2.31: the startup probe (aarch64) and the x86_64 unit tests.

Each transcript prints the libc it ran on.

## What each file shows

| probe | transcript | shows |
|---|---|---|
| `probes/sig556.c`, `probe-sig.sh` | `probe-sig-main.txt` | the doors on main, one forked child each: libc `sigaction(SIGSYS)` and libc `sigprocmask` survive; raw `rt_sigaction`, raw `rt_sigprocmask`, a `SIGUSR1` handler installed with a full `sa_mask`, and a `posix_spawn` child with a write-capable file action die of signal 31 |
| `probe-node.sh` | `probe-node-main.txt`, `node-fixed.txt`, `node-m1.txt` | node's `process.on('SIGUSR2')` handler and `execFile` child: refused on main, accepted on this change, refused again on M1 |
| `probe556.sh` | `probe556-v1.3.0.txt`, `probe556-main-39da3cf.txt`, `probe556-mut-sigaction-guard-off.txt`, `probe556-spike-image.txt` | #556's four Python rows: `-31` on v1.3.0, `FileNotFoundError` on main, `-31` again with the `sigaction` guard off |
| `saoff.c` | `saoff-aarch64.txt`, `saoff-x86_64.txt` | glibc's `struct sigaction` layout and `SIGSYS`'s byte, the numbers `syscalls.zig`'s comptime block pins |
| `spawn556.c`, `probe-spawn.sh`, `probe-clone3.sh` | `probe-spawn-main.txt`, `probe-clone3.txt` | `posix_spawn`'s file actions under the mode: the write-capable one kills the child (glibc 2.36 and 2.41). `probe-clone3.txt`'s "clone family lines" section is empty: the `strace` run it greps wrote nothing that matched, and its stderr was discarded, so why was not found. The clone flags this record cites are `probe-masks.txt`'s |
| `probe-masks.sh` | `probe-masks.txt` | the masks and clone flags glibc 2.41 uses around `pthread_create` and `posix_spawn`, under Docker's default seccomp profile (`clone3` refused, `clone` used) and with it off (`CLONE_CLEAR_SIGHAND`) |
| `probe-startup.sh`, `probe-startup2.sh` | `probe-startup-main.txt`, `probe-startup-bullseye.txt` | the signal calls an exec'd image makes before the shim installs its handler; the second script's header says what the first read wrongly |
| `run-legs.sh` | `legs-4builds.txt` | the two #556 legs, cut verbatim out of `spike/acceptance.sh`, against main `478c954`, this change, M1 and M2 |
| `run-legs-m4.sh` | `legs-m4.txt` | M4: its unit tests, the legs, and the toy's own exit 3 with the shim preloaded directly |
| — | `unit-aarch64.txt`, `unit-x86_64.txt`, `unit-mutants-aarch64.txt` | `shim/src/syscalls.zig`'s tests, built with `zig test --test-no-exec` and run in a container, on this change and on M1 and M3 |
| `spike/dogfood/2026-09-11-syscall-trap-542b/apparatus/mlr.sh`, unchanged | `mlr/main/`, `mlr/fixed/`, `mlr/run-both.txt` | the 542b define, six runs on main then six on this change: 5 refusals and 1 PASS, then 3 and 3, and no run of either died |

## After the second review

| Source | Transcript | What it shows |
|---|---|---|
| `objdump -T` over the libc `ldconfig` names, in `sideeye-spike` | `libc-signal-symbols.txt` | glibc 2.36 exports every signal entry point item (4)(a) names; `sigaction` is the control |
| `mutants/mut556e.diff` (the bit cleared before the guard test), `mut556f.diff` (a copy forwarded without `SIGSYS` in the mask), `mut556g.diff` (the copy made and not forwarded), `mut556h.diff` (the comptime size one off) | `unit-callsite-mutants-aarch64.txt` | the call-site test red on e, f and g at the assertion for its own case, and h stopped by the comptime check |
| — | `unit-aarch64-final.txt`, `unit-x86_64-final.txt` | `shim/src/syscalls.zig`'s tests on the final tree |

- `probe556-mut-sigaction-guard-off.txt`'s shim, sha256 `bc69633f9eb5d65829b4c1fbb99ac9ad0ad7ef6ad4846a2d4bf3cc1541b0efc7`, is main with `sigaction`'s guard taken out — `mutants/mut556-sigaction-guard-off.diff`, against `39da3cf` (the file is the same at `478c954`) — built in `<scratch>/mut/` for the first probe, before the build table above.
- `toy-samask-before-after.txt`: `toy_raw.c`'s `samask` before and after its handler was rewritten onto `raw_write_file`, under strace with no shim — the same calls and exit 0. The legs in `legs-4builds.txt` and `legs-m4.txt` ran the toy from before.
- `probe-clone3.txt` prints neither the shim's sha nor the seccomp setting, and holds two runs of the script one after the other; which build and which profile it ran under are not recoverable from it.

