# The platform probe, second series — how it is run and read, decided before the dispatches it governs

The runs of `.github/workflows/spike-platforms.yml` after 2026-10-10's single dispatch, which
measure the rows `docs/cli.md`'s table left unmeasured or "not run" (ADR 0105, amended). These
rules were committed with the apparatus, before any of those runs, except the one item dated
below, which was added after the first of them and before the dispatch it governs. `RUNS-RULE.md` governs the
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
