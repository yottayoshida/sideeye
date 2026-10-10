# The platform probe, second series — how it is run and read, decided before the dispatches it governs

The runs of `.github/workflows/spike-platforms.yml` after 2026-10-10's single dispatch, which
measure the rows `docs/cli.md`'s table left unmeasured or "not run" (ADR 0105, amended). These
rules were committed with the apparatus, before any of those runs, except the items dated
below, each added after a run and before the dispatch it governs. `RUNS-RULE.md` governs the
2026-10-10 record and is not edited; where the two speak to the same thing, this file governs the
new runs and that record stands as it was read.

## Which runs count

- **Per leg, the first run that left a result counts.** A result is: a `summary.txt` with a line
  per mode, each carrying a verdict (a mode with no verdict line — a timeout — is not one); for the
  legs that ask whether the binary starts, its `version.txt`; for `hardened-mcp`, a `tools/call`
  answer (`"id":2`) carrying a verdict; for a source build, its log ending in an exit status and,
  where it built, the summary and the demo's exit status. A leg with a result is not measured
  again; a re-dispatch names only the side whose legs are an apparatus fault
  (`jobs: linux|container|vm|macos|wsl|build`). Every run is listed in the record, completed or
  not, with what stopped it.
- **An apparatus fault** is anything that keeps a leg from its result: a script error, a host step
  of `vm.sh` that did not exit 0, a download, digest or package failure (including an apt or dnf
  lock), a VM whose data disk holds no `done` mark or no complete summary, a runner job failing in
  a brownout of `macos-14` (2026-10-12, 16, 19, 23, 26, 29 and 30, 14:00–24:00 UTC; the image is
  retired on 2026-11-02). It is fixed and that side re-dispatched.
- **Where the same stop recurs it is a result**, under these conditions only: every host step
  exited 0, the guest's kernel and cloud-init both printed to the console (`vm.txt`'s console
  line), the VM ran under KVM, and it stopped twice at the same last `vm-inner:` mark on the
  console (the marks follow the packages and the measurement; a packages mark with a non-zero exit
  is a package failure, an apparatus fault, never a result); or a guest that printed its kernel and
  cloud-init and no `vm-inner: start` twice, at the same last console line; or a build that
  failed twice with the same compiler error, not a network or package error; or an explore that
  timed out twice in the same mode. A stop under TCG is never a result.
- **A leg added after the first dispatch** (added 2026-10-10, after run 38031881569 and before the
  dispatch it governs): `wsl1-shim`, which follows WSL1's refusal "pass --shim" once, is measured
  in a later `jobs: wsl` dispatch — the one exception to re-dispatching only an apparatus fault's
  side. In the record, only `wsl1-x86_64/wsl1-shim/` is added beside what run 38031881569 counted;
  everything else that dispatch writes goes under `spike/platforms/2026-10-10b/runs/<run id>/` and
  is listed and read for what it says about the dispatch (whether WSL1 started, whether it refused
  again, a fault), not counted — the legs it re-runs keep the result they first counted. "Once"
  means one `--shim` leg for the one refusal; a `wsl1-shim` that leaves no result follows the rules
  above (an apparatus fault re-dispatched, the same stop twice a result). Its control is the x86_64 `host` leg of run
  38031881569 (`measure.sh` and `define/` are the same at both commits). If WSL1 does not start in
  that dispatch, or does not refuse the shim again, `wsl1-shim` is recorded as not reached, with the
  run id, and WSL1's cell rests on its base leg alone. WSL1's cell names both: the base leg's
  refusal and `wsl1-shim`'s modes.
- **A probe added after the second dispatch** (added 2026-10-10, after run 38035850147 and before
  the dispatch it governs): `wsl1-statx.txt`, written by `statx-probe.py` after WSL1's base leg. It
  asks WSL1's kernel, by raw syscall, the calls the two refusals rest on (`src/posix.zig`: the shim
  search's `statx`, `AT_SYMLINK_NOFOLLOW` with `TYPE|UID`; the `PATH` search's `access(X_OK)` —
  glibc's, the `access` syscall on x86_64, asked with `faccessat` beside it — and `statx`
  following links with `TYPE`), and `newfstatat` beside them as its control, on
  `/usr/bin/dd` and the shim. It is not a leg and carries no verdict: it is read for why `wsl1` and `wsl1-shim`
  refused, and a cell that cites it cites it as that cause. It is measured in a later `jobs: wsl`
  dispatch whose other output goes under `spike/platforms/2026-10-10b/runs/<run id>/` as above;
  only `wsl1-x86_64/wsl1-statx.txt` is added beside the counted record. A control that does not
  answer 0 is an apparatus fault, and so is a run where WSL1 does not start.
- **Legs added after the second dispatch** (added 2026-10-10, after run 38035850147 and before
  the dispatch it governs): on each macOS runner, the default mode three more times with `--work`
  moved — `macos-NN-work-tmp` under `/tmp` (short, through the symlink), `macos-NN-work-private-tmp`
  under `/private/tmp` (short, physical), `macos-NN-work-tmpdir-resolved` under `$TMPDIR` resolved
  (its own length, physical). All three default legs of run 38031881569, the control's included,
  were UNKNOWN `oracle_saw_nothing` with `--work` under `$TMPDIR` as given (`/var/folders/…/T//…`:
  through the `/var` symlink, and with a doubled slash from `$TMPDIR`'s trailing one). Two causes
  fit and the legs tell them apart: the path's length (`docs/cli.md`: fs_usage cuts long pathnames
  from the left) and its spelling (the engine names the trace file `<--work>/trace-record.bin` as
  given, `src/main.zig`, and matches fs_usage's physical paths to it after removing only the data
  volume's firmlink prefix, `src/fsusage.zig`). `-work-tmp` differs from fs_usage's spelling by
  the symlink alone; `-work-tmpdir-resolved` by neither.
  Neither is a finding until the legs answer. They are measured in a later `jobs: macos` dispatch;
  only the nine `macos-NN/macos-NN-work-*/` directories are added beside the counted record, and
  the rest of that dispatch goes under `spike/platforms/2026-10-10b/runs/<run id>/`. The default
  legs of run 38031881569 keep their UNKNOWN; their control was not FAIL, so the mode is the
  owner's (above), and these legs are read for the owner beside them, each `macos-26-work-*` the
  control of the same leg on 14 and 15.
- **Ubuntu 20.04 on aarch64** (added 2026-10-10, after run 38031881569 and before the dispatch it
  governs): the aarch64 runners have no `/dev/kvm` (every aarch64 VM of that run says `accel:
  tcg`), so its stops can never be a result. `vm.sh` boots that image with `-cpu cortex-a72`
  instead of `max`. If it leaves no result in the next `jobs: vm` dispatch, its cell goes back to
  the owner with both runs' `vm.txt`, rather than taking a reason the list below does not give.
- **x86_64 WSL2's base leg was decided on 2026-10-10** and is not measured again. If WSL2 does not
  start in a run of this series, the legs that needed it are recorded as "the runner's WSL2 did
  not start in run N" with the `wsl.txt` lines.
- **WSL1 started** when `uname -r` exits 0 naming Microsoft's kernel and not WSL2's; **WSL2 on
  Windows on ARM** by `RUNS-RULE.md`'s rule for WSL2. One that does not start is decided once and
  recorded as the runner's.
- **systemd** counts as started when a line of `ps -p 1`'s standard output is exactly `systemd`
  after `/etc/wsl.conf` turns it on (its content is in `wsl.txt`) and the distribution is
  restarted; otherwise the systemd legs are recorded as not started, once.

## How a cell is read

- **The control** for every leg is the `host` leg of the Ubuntu 24.04 runner of the same CPU, from
  the counted `linux` run at the same commit — whichever dispatch that was; `wsl1-shim`'s is named
  in its item above. x86_64: the x86_64
  containers, VMs, WSL legs, the Actions container, the Alpine source build on x86_64. aarch64:
  their aarch64 counterparts and WSL2 on Windows on ARM. macOS 14 and 15 are read against
  `macos-26`.
- **A VM** is also read against its `<image>-container` leg, the same userland as root on the
  runner's kernel; the two count as a pair from the same run (a `jobs: vm` re-dispatch re-runs
  both). The two compare by upstream versions — glibc's, strace's and coreutils' — from
  the package lists in the record (coreutils by the package that owns `dd`, since Rocky's
  container images carry coreutils-single); a different packaging revision of the same upstream version is
  recorded, not a fault; a different upstream version is an apparatus fault. The VM runs as root in
  cloud-init's cgroup, the container as root in its own namespace, so a cell says "booted"
  against "the same userland on the runner's kernel", not "the kernel alone".
- The right answer is still FAIL at the pair after the `open` of `a.txt` and before its `write`,
  `oracle_verified`. **A control that is not that FAIL in a mode** sends that mode back to the
  owner; nothing is concluded from it.
- **A leg measured on 2026-10-10 and again here** (the 24.04 runners' `host`, `rocky8-*`,
  `alpine-*`) that answers differently goes back to the owner; the table keeps 2026-10-10's cell
  until the owner rules.
- **dd**: each leg's `env.txt` names its dd. Ubuntu 26.04's may be uutils; where a cell differs and
  the dd explains it, the cell says so and is not read as the platform's answer.
- **A row where the binary does not start** (no loader at its path, a glibc too old) or that
  started and agreed with the control in no mode goes to the owner for its word, as musl did.

## Reasons an unmeasured row or a "not run" cell may give

Fixed here, before the runs; `docs/cli.md`'s rows cite one, with its evidence:

1. **No hosted runner** offers it — cited by the runner-images page that lists the runners.
2. **The owner's ruling**, dated — 2026-10-10: Intel macOS is declined and not measured; NixOS is
   measured in the `nixos/nix` forms and not booted as a VM; the CPUs the release does not build
   are built from source and not run.
3. **The runner does not provide it** — cited by a run id and the record's line (a WSL that did
   not start, a systemd that did not become PID 1).
4. **The engine has no code for it** — cited by the file and line that say so.

An apparatus fault is not a reason.
