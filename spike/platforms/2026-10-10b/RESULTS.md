# The platform probe, second series — the record behind docs/cli.md's table (ADR 0105, amended)

Read by `spike/platforms/RUNS-RULE-2026-10-10b.md`, written before the first of these runs, with
the items dated in it added after a run and before the dispatch each governs. The 2026-10-10
record (`../2026-10-10/`) stands as it was read. Engine: the **v1.10.0** release, installed by
`install-sideeye.sh` (digest checked against the release), except the source builds, which name
their commit.

## The runs

Every dispatch of `spike-platforms.yml` in this series, completed or not:

| run | jobs | commit | what it left |
|---|---|---|---|
| 38031881569 | `all` | `ca6bdbdf` (#780) | 30 jobs. 28 left their results. Two apparatus faults: `vm (ubuntu-24.04, rocky9)` was cancelled at the job's 120-minute limit inside the runner's own `apt-get` (its `vm-apt.txt` empty, `-qq`); `vm (ubuntu-24.04-arm, ubuntu2004)` reached QEMU's 5400 s limit under TCG with the console's last line GRUB's `error: no suitable video mode found.` and no kernel output |
| 38035850147 | `wsl` | `f57083d4` (#781) | `wsl1-shim`, the leg added after the first dispatch, counted. The rest is under `runs/38035850147/`, listed and not counted: WSL1 started and refused the shim again as in the first run; `wsl2-arm64` did not start; the extra WSL2 legs answered as they first did |
| 38042197677 | `vm` | `6af3ed06` (#790) | All 14 VM jobs completed. Counted: the x86_64 Rocky 9 pair and the aarch64 Ubuntu 20.04 pair (the first run's two apparatus faults); the other twelve are under `runs/38042197677/`, listed, not counted |
| 38042203156 | `wsl` | `6af3ed06` | Cancelled before any job: the workflow's concurrency group keeps one pending run, and the next dispatch (38042208601) replaced it. Re-dispatched below |
| 38042208601 | `macos` | `6af3ed06` | Cancelled before any job, replaced in the pending slot by 38042951771 |
| 38042951771 | `linux` | `314bf8c0` (#789) | Another session's dispatch; cancelled before any job, replaced in the pending slot by 38042972486 |
| 38042972486 | `wsl` | `6af3ed06` (#790) | `wsl1-statx.txt` counted (WSL1 started, refused as before, the control answered). The rest under `runs/38042972486/`, listed: `wsl2-arm64` did not start; the other legs answered as they first did |
| 38043239184 | `linux` | `314bf8c0` (#789) | Another session's dispatch, to see the hardened legs with `--user`; listed, not counted (it came before the rules item that counts them) |
| 38043673051 | `macos` | `40e91a20` (#792) | The nine `macos-NN-work-*` legs counted. The rest under `runs/38043673051/`, listed: the default legs and the demo answered as they first did |
| 38043722536 | `linux` | `40e91a20` (#792) | `hardened-cli` and `hardened-mcp` counted for the page's current form (`linux-*-user/`); the rest under `runs/38043722536/`, listed |
| 38049858888 | `wsl+container+build` | `f1171f37` (#803) | Counted: the aarch64 `container:` leg (`container-ubuntu-24.04-arm/`), the armel, ppc64le and s390x builds, WSL2 on Windows on ARM with WSL installed (`wsl2-arm64-installed/`), and the import record of WSL2 as imported. `wsl2-nosystemd-*` not reached: the check read PID 1 `init(probe)` as not WSL's init, an apparatus fault (#808). The rest under `runs/38049858888/`, listed: every re-run leg answered as it first did |
| 38050789067 | `wsl` | `d48f306f` (#808) | Counted: `wsl2-nosystemd-root` and `-user`, with `wsl-38050789067.txt` and `wsl-nosystemd.txt`. The rest under `runs/38050789067/`, listed: every re-run leg answered as it first did, and WSL2 on Windows on ARM again could not start (`HCS_E_HYPERV_NOT_INSTALLED`) |

Each directory here is a job's artifact as uploaded, unedited, named after the job
(`linux-x86_64/` is `linux (ubuntu-24.04, x86_64, all)`, `vm-ubuntu-24.04-arm-rocky9/` is
`vm (ubuntu-24.04-arm, rocky9)`); `runs/<run id>/` holds what a later dispatch wrote that the rules
do not count. Paths under `/home/runner/work/_temp`, `/var/folders` and `D:\a` are the runners'.

## The control, and what "the right FAIL" is

The control is the `host` leg of the Ubuntu 24.04 runner of the same CPU (`linux-x86_64/host`,
`linux-aarch64/host`: kernel 6.17.0-1022-azure, glibc 2.39, uid 1001 in a delegated cgroup). In
all three modes, on both CPUs, it gave the right answer: FAIL, the earliest violation after the
`open` of `/s/st/a.txt` and before its `write`, `oracle_verified`, 2 operations agreed. Every
cell below that says **FAIL** is that FAIL — the same pair, `oracle_verified` — unless it says
otherwise (Ubuntu 26.04's, below), read from the JSON reports, not the text. Of the 204 explores these runs counted, 152 are that FAIL; the other
52 are named where they occur.

## The legs 2026-10-10 measured too

The `host`, `rocky8-privileged`, `rocky8-defaults` and `alpine-gcompat` legs, both CPUs, answered
as on 2026-10-10, mode by mode (`summary.txt` against `../2026-10-10/`): the hosts and the
privileged Rocky 8 FAIL in all three modes; Rocky 8 with docker's defaults FAIL in default and
syscalls and refuses supervised for its cgroup; Alpine with `gcompat` as below. The rules keep
2026-10-10's cells for them; nothing differed to send back.

## The cells, by the table's rows

### Kernels older than 6.17

- **Runners**: Ubuntu 22.04 (6.8.0-1064-azure, glibc 2.35), both CPUs: FAIL in all three modes.
  Ubuntu 26.04 (7.0.0-1012-azure, glibc 2.43), both CPUs: FAIL in all three modes,
  `oracle_verified`, but at another pair — after a `truncate` and before the `write` — because its
  `dd` is uutils' (`env.txt`: `dd (uutils coreutils)`): the oracle agreed on 4 operations on the
  file, a truncate of its own among them, where GNU's dd makes 2 (4 crash points rather than 2).
  The rules read that difference as the dd's, not the platform's.
- **Virtual machines**: each image booted on its own kernel, beside its own userland in a
  privileged container on the runner's 6.17 (the `-container` leg). The two of every pair carry the
  same upstream glibc, strace and coreutils (`<image>-container-pkg.txt`, `<image>-vm-disk/pkg.txt`).
  x86_64 ran under KVM (18–44 s a boot), aarch64 under TCG (234–945 s).

| image | kernel | default | syscalls | supervised | its container on 6.17 |
|---|---|---|---|---|---|
| Debian 13 | 6.12.111 | FAIL | FAIL | FAIL | FAIL ×3 |
| Rocky 10.2 | 6.12.0-211 | FAIL | FAIL | FAIL | FAIL ×3 |
| Debian 12 | 6.1.0-53 | FAIL | FAIL | FAIL | FAIL ×3 |
| Ubuntu 22.04 | 5.15.0-198 | FAIL | FAIL | SETUP ERROR | FAIL ×3 |
| Rocky 9.8 | 5.14.0-687 | FAIL | FAIL | SETUP ERROR | FAIL ×3 |
| Ubuntu 20.04 | 5.4.0-216 | FAIL | FAIL | SETUP ERROR | FAIL ×3 |
| Rocky 8.10 | 4.18.0-553 | FAIL | FAIL | SETUP ERROR | FAIL ×3 |

  Both CPUs. Two pairs are from the `vm` re-dispatch (run 38042197677), their first runs' partial
  directories under `runs/38031881569/`: x86_64 Rocky 9.8, and aarch64 Ubuntu 20.04, booted with
  `-cpu cortex-a72` (`vm.txt`: 471 s). In both Ubuntu 20.04 pairs libc6 is 2.31-0ubuntu9.17 in the
  container and 9.18 in the VM: the same upstream version, a packaging revision apart. All eight
  SETUP ERRORs are the same sentence: "`--observe supervised` needs a kernel that accepts a
  seccomp user-notification listener with SECCOMP_FILTER_FLAG_WAIT_KILLABLE_RECV (Linux 5.19 or
  later), and this one does not" — the floor `docs/cli.md` already states.

### glibc versions

The containers above put glibc 2.28 (Rocky 8.10), 2.31 (Ubuntu 20.04), 2.34 (Rocky 9.8), 2.35
(Ubuntu 22.04), 2.36 (Debian 12), 2.39 (Rocky 10.2) and 2.41 (Debian 13) under the release on
6.17, as root: FAIL in all three modes, both CPUs. With the runners' 2.35, 2.39 and 2.43, that is
ten versions from 2.28 to 2.43.

**Older than 2.28**: in CentOS 7 (glibc 2.17) and Debian 9 (2.24), both CPUs, the engine does not
start: `version 'GLIBC_2.25' not found`, then `GLIBC_2.27`, then `GLIBC_2.28` (`centos7/version.txt`,
`debian9/version.txt`).

### musl

- **The release binary**: as on 2026-10-10 — it does not start on Alpine 3.22 (`sh: /se/sideeye:
  not found`, exit 127); with `gcompat`, default and syscalls FAIL, supervised UNKNOWN
  `recording_run_failed` (the engine's own `__filter-exec` started under musl's loader).
- **Built from source on Alpine 3.22** with Zig 0.16.0, `-Doptimize=ReleaseSafe`, both the
  v1.10.0 tag (`37a0588f`) and main at `ca6bdbdf`, both CPUs (`build-ubuntu-24.04*/alpine-src-*`):
  FAIL in all three modes, and `sideeye demo` FAIL (1 of 6 worlds), in all four builds. The
  engine and shim are linked against musl's loader (`build.txt`: `interpreter
  /lib/ld-musl-*.so.1`). The shim entered the demo's toy in both — the FAIL needs the trace of its
  operations: v1.10.0's demo compiled it with Alpine's `cc` (`demo.txt`: "compiled the planted-bug
  tool with cc"), main's wrote the one it carries (ADR 0101), where ADR 0101 expected a static
  toy on musl that the shim could not enter.

### NixOS's forms (`nixos/nix`, Nix 2.35.2)

Both CPUs, as root:

- **As shipped** (no loader at the path the binary names): `cannot execute: required file not
  found`, exit 127.
- **With `nix-ld`** (nix-ld at the loader's path, `NIX_LD` naming Nix's glibc loader): FAIL in
  all three modes.
- **Through the loader by name** (a wrapper that runs `<Nix's glibc>/lib/ld-linux-*.so.*
  /se/sideeye`): SETUP ERROR in all three modes,
  "the shim is half the product, and none was found" — `/proc/self/exe` names the loader, so the
  search looks beside it.
- **The same with `--shim`**: default and syscalls FAIL; supervised UNKNOWN `recording_run_failed`,
  the engine's re-execution of itself (`__filter-exec`) going through `/proc/self/exe` to the
  loader.

### Containers

- **GitHub Actions' `container:`** (`rockylinux/rockylinux:8.10`, as the job's container), x86_64
  (run 38031881569) and aarch64 (run 38049858888, `container-ubuntu-24.04-arm/`): default and
  syscalls FAIL; supervised SETUP ERROR, "needs a cgroup v2 the engine can create cgroups in".
  Their control is run 38031881569's `host` of the same CPU (`measure.sh`, `define/` and
  `install-sideeye.sh` are the same at both commits).
- **`docs/mcp.md`'s hardened container as it read on 2026-10-10** (`--network=none --read-only
  --tmpfs /tmp:exec --cap-drop=ALL --security-opt no-new-privileges`, the state on the `/work`
  mount, as root), both CPUs: through the CLI, default and syscalls FAIL and supervised the same
  cgroup SETUP ERROR; through `sideeye mcp`, the `tools/call` answer FAIL, `oracle_verified`, the
  same pair. The page has since added `--user` (#789, ADR 0114), and `mcp-container.yml` runs the
  page's block as written on both CPUs whenever the page, its Dockerfile or that check changes.
- **The same in the page's current form** (`--user`, uid 1001; run 38043722536, `linux-*-user/`),
  both CPUs: through the CLI, default and syscalls FAIL and supervised the cgroup SETUP ERROR;
  through `sideeye mcp`, FAIL, `oracle_verified`, the same pair. Its control, the same dispatch's
  `host` legs, FAIL in all three modes.

### macOS

`macos-14` (14.8.9), `macos-15` (15.7.9) and `macos-26` (26.6.2), Apple silicon, GNU `dd` from
Homebrew (`/bin/dd` is protected by SIP), `--oracle-fs-usage`:

- `sideeye demo`: FAIL (1 of 6 worlds) on all three.
- The default mode with `--work` under `$TMPDIR` as given: UNKNOWN `oracle_saw_nothing` on all
  three, the control included — "no thread in the fs_usage capture wrote to the shim's trace file".
- The default mode again, run 38043673051, with `--work` moved to tell the path's length from
  its spelling (`macos-NN-work-*/`, each `env.txt` naming the directory as given and resolved):

  | `--work` under | spelling | length | all three versions |
  |---|---|---|---|
  | `$TMPDIR` as given (`/var/folders/…/T//…`), the counted leg above | through `/var` | long | UNKNOWN: no thread wrote to the shim's trace file |
  | `/tmp` (`-work-tmp`) | through `/tmp` | short | the same |
  | `/private/tmp` (`-work-private-tmp`) | physical | short | UNKNOWN `oracle_saw_nothing`, a later stage: "the capture carries an operation on a descriptor it never saw opened … write F=1 B=0xd", and "it is a defect in Sideeye" |
  | `$TMPDIR` resolved (`-work-tmpdir-resolved`) | physical | long | the same as `/private/tmp` |

  The length does not matter and the spelling does: the engine names its trace file
  `<--work>/trace-record.bin` as given and matches fs_usage's physical paths against it (#795 —
  the default `--work`, `/tmp/sideeye-work`, is spelled through `/tmp`). With a physical `--work`
  the subject is found, and GNU dd's write on descriptor 1, where it moves its output file, is
  refused as unresolved (#796). Both are Sideeye's, on every macOS version the probe ran; neither
  says anything about 14 or 15 that 26 does not.

### WSL

- **WSL1** (run 38031881569, `windows-2025`): WSL updated to 3.0.1, the image imported with
  `--version 1`, `uname -r` 4.4.0-26100-Microsoft, **started**. All three modes SETUP ERROR: "the
  shim the search found could not be classified — neither its kind nor its owner could be read".
  Its next step, `--shim` (run 38035850147, `wsl1-shim`): all three modes SETUP ERROR, "operation:
  no executable file named dd is on PATH", with `/usr/bin/dd` there (`env.txt`). Why
  (`wsl1-statx.txt`, run 38042972486): WSL1's kernel answers `statx` with `ENOSYS`, both forms, on
  `/usr/bin/dd` and on the shim, while `access(X_OK)`, `faccessat(X_OK)` and `newfstatat` answer
  0. On Linux the engine reads a file's kind through raw `statx` and nothing else
  (v1.10.0 `src/posix.zig:454`, `statNoFollow`; `:504`, `isRegularFollowing`; no other path on
  Linux), so the shim search cannot classify the shim and the `PATH` search passes over a `dd` it
  cannot type — the second refusal names a cause that is not the one.
- **WSL2 on Windows on ARM** (`windows-11-arm`): "The Windows Subsystem for Linux is not
  installed" to every `wsl` command, `started: no` (run 38031881569, `wsl2-arm64/wsl.txt`; the
  same in 38035850147), with VirtualMachinePlatform, Microsoft-Windows-Subsystem-Linux and
  Microsoft-Hyper-V all `Enabled`. With the WSL 3.0.1 arm64 package installed (run 38049858888,
  `wsl2-arm64-installed/`: the digest matched, `msiexec` exit 0, its log ending "Installation
  completed successfully", `wsl --version` 3.0.1.0), the import fails: "WSL2 is unable to start
  since virtualization is not enabled on this machine", `HCS_E_HYPERV_NOT_INSTALLED` — the
  runner's virtual machine does not pass virtualization on. `started: no`.
- **WSL2 on x86_64, its other forms** (the base leg is 2026-10-10's): the state under `/mnt/c`
  (the Windows drive), as root: FAIL in all three modes. An ordinary user with its own install,
  in a logind session (`env.txt`: `cgroup: /user.slice/user-1001.slice/session-c2.scope`), not in
  a delegated cgroup: default and syscalls FAIL, supervised the cgroup SETUP ERROR. With systemd
  turned on and PID 1 read (`wsl-systemd.txt`: `PID 1: systemd`, `running`): root FAIL in all
  three modes, and the ordinary user inside a cgroup delegated to it FAIL in all three modes.
- **systemd, read again.** The `cgroup: /non-systemd` line that 2026-10-10's record read as
  "without systemd" is the same in `wsl2-systemd-root`, where PID 1 is systemd, and the user leg
  above, measured before the workflow turned systemd on, is in a logind session: Ubuntu's WSL
  image starts systemd itself, so the legs read as without it ran with the image's own setting.
  The import record says so (run 38049858888, `wsl2-x86_64-extra/wsl-38049858888.txt`):
  `/etc/wsl.conf` as imported holds `[boot]` `systemd=true`, and PID 1 is `systemd`; that run's
  `wsl --update` installed 3.0.1 and its rootfs digest is the one before.
- **WSL2 without systemd.** With `systemd=false` written and the distribution restarted, PID 1 is
  WSL's own `init(probe)` (run 38050789067, `wsl-38050789067.txt`, `wsl-nosystemd.txt`; the first
  try, in run 38049858888, read that name as not `init` and skipped the legs — an apparatus
  fault, #808). As root: FAIL in all three modes. As an ordinary user, its own install, the
  systemd leg's sudo rule removed: default and syscalls FAIL, supervised the cgroup SETUP ERROR.
  Their control is run 38031881569's x86_64 `host`.

### Other CPUs and Windows

Built from the v1.10.0 tag with Zig 0.16.0, `-Doptimize=ReleaseSafe`, each for Zig's default CPU
for its target (not Debian's baseline), not run (the owner's ruling, 2026-10-10). The first three
in run 38031881569, the last three in run 38049858888 — with riscv64 and armhf, the release
architectures of Debian 13 the release has no asset for:

- `riscv64-linux-gnu.2.28` and `s390x-linux-gnu.2.28`: build (`exit 0`), the engine and the shim.
- `arm-linux-gnueabihf.2.28`, `x86-linux-gnu.2.28` and `arm-linux-gnueabi.2.28` (armel): the
  engine builds (`file`: an ELF 32-bit executable) and the shim does not —
  `shim/src/common.zig:687: expected 32-bit integer type or smaller; found 64-bit integer type`
  and `shim/src/syscalls.zig:441: expected type 'u32', found 'u64'`.
- `powerpc64le-linux-gnu.2.28`: the engine builds and the shim does not —
  `shim/src/ops.zig:909: unable to perform tail call: compiler backend 'stage2_llvm' does not
  support tail calls on target architecture 'powerpc64le'`, the `vfork` wrapper's
  `@call(.always_tail, …)`.
- **Windows** (`windows-2025`, native): 10 errors, the first `src/posix.zig:214: unsupported OS`
  (`@compileError("unsupported OS")`).

## Read against the rules

- The control was the right FAIL in every mode on both CPUs, so no Linux mode goes back to the
  owner. macOS's control was not FAIL in the default mode, so that mode went back to the owner,
  with the legs above: macOS 14 and 15 read **supported** on the demo, as macOS 26 does, the cell
  naming #795 and #796 (the owner's ruling, 2026-10-10).
- Rows that agreed with the control in at least one mode and refused the rest with a reason the
  docs state (supervised's kernel or cgroup) read **supported**, the cell naming each mode.
- Rows where the binary does not start (glibc older than 2.28, NixOS as shipped, musl's release
  binary) or that agreed with the control in no mode (WSL1) went to the owner for their word
  (2026-10-10): glibc older than 2.28, musl and WSL1 stay **declined**, each cell saying what was
  measured (musl: built from source, all three modes and the demo); NixOS is **supported with
  nix-ld**, the cell naming the forms that do not run.
- No leg was re-measured after it counted. The two apparatus faults of run 38031881569 were
  fixed (#790) and their side re-dispatched; both pairs then left their results.
