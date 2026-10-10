# 0105 — The platform table says supported, unmeasured or declined

- **Status:** Accepted (2026-10-10)
- **Refs:** #697 (from the 2026-10-05 whole-product review); ADR 0101 (the demo's toy, whose
  static build on a musl host was left to #697); `.github/workflows/spike-unknown-rate-x86.yml`
  and `spike-fsusage.yml` (measurement workflows that are not CI).
- **Scope:** `spike/platforms/`, `.github/workflows/spike-platforms.yml`; the table itself lands in
  `docs/cli.md` with the record of the first run.

## Context

The README says "macOS on Apple silicon, Linux on x86_64 and aarch64", and nothing anywhere says
what happens on the platforms an adopter is likely to bring next: Alpine and other musl systems
(the usual CI base image), Intel Macs, Windows, WSL2, older glibc, other CPUs. A measurement on
2026-10-10 (posted on #697) found that on Alpine the release binary does not start at all — it
names glibc's loader — and that with `gcompat` it starts, while `--observe supervised` refuses
with a reason that blames the operation for the engine's own failure. That measurement used a
shell redirect as its operation, and its default mode refused `oracle_missed_operation`; a
dry run of this ADR's probe on the same machine, with `dd` in place of the redirect, was judged
FAIL in the default and syscalls modes at the same pair of operations as Ubuntu and Rocky 8,
`oracle_verified` — the redirect had measured busybox's `printf`, not musl. Neither run is in
the repository; the probe's first dispatch is the record. None of that is written down.

## Decision

`docs/cli.md` carries one table, one row per platform, each row one of three words:

- **declined** — the release publishes no asset for it and none is planned. On the owner's ruling
  (2026-10-10): musl (Alpine), Intel macOS, native Windows, and the CPUs the release matrix does
  not build (armv7, i386, riscv64, …). Linux with glibc older than 2.28 is declined because the
  builds target 2.28. A declined row says what was and was not tried — for musl, what `gcompat`
  does; for musl and Intel macOS, that building from source was not tried (and, from ADR 0101,
  that on a musl host the demo's toy would build static, where the shim could not enter it).
- **unmeasured** — an asset exists for the CPU and the kernel, and it has not been run there:
  WSL1, WSL2 on Windows on ARM, and NixOS — where the binaries name the FHS loader path, which
  NixOS provides only through a compatibility layer (nix-ld or an FHS environment); how they
  behave there is not known.
- **supported** — an asset exists and the probe's define gave the right answer there, mode by
  mode, at the same commit as the release target's own leg. The Linux release targets rest on two
  things:
  each release runs its asset's `sideeye demo` on the platform it ships for (`release.yml`), and
  the probe runs them as adopters install them — the x86_64 and aarch64 runners themselves, and
  Rocky 8 for the glibc 2.28 floor. CI builds the engine from source and tests it on x86_64 Linux
  and on macOS on every push; it builds the aarch64 Linux target without running it. How a cell
  is read, including what happens if a release target's own leg answers wrong, is
  `spike/platforms/RUNS-RULE.md`, written before the first dispatch. macOS arm64 is the one
  release target the probe does not run: it rests on the release's `sideeye demo` on macOS and on
  CI's macOS job, which builds and tests the engine from source on every push.

WSL2 is measured on GitHub's Windows runner, once, because the issue asks for one measurement.
It may not start there: WSL2 runs its kernel in a virtual machine, GitHub's page on its hosted
runners calls nested virtualization possible but not officially supported, and Ubuntu's WSL
documentation says hosted runners do not run the current WSL because it needs a logged-in
user's session. Which, if either, applies is what the run records: what the runner reports
about WSL and virtualization, and the import itself. If WSL2 does not start, the row is
unmeasured and its cell quotes that record.

## Alternatives considered

- **Ship a musl build** (engine and shim): a second build of each, a shim linked against musl for
  musl targets, and the supervised mode's self re-execution made to work where the binary is
  started through another loader. A separate piece of work, not taken here.
- **Write the table from reading alone**: the Alpine result — a binary that does not start, and a
  refusal that misreports its own cause — was not readable from the tree.
- **Measure on the maintainer's machine**: no glibc control in the same run, and nothing in the
  repository that re-runs it.
- **One pull request, with the workflow also run on `pull_request`**: the measured tree would not
  be a merged commit; #696 measured at the apparatus's merge commit, and this does the same.

## Consequences

- An adopter on Alpine reads "declined" and why, before trying; the CI quickstart links to the
  table.
- The supervised mode's refusal under `gcompat` (the filter installer re-executes
  `/proc/self/exe`, which names musl's loader there, and the refusal reports the operation's exit
  status) is recorded, not fixed: it is a refusal on a declined platform, not a wrong verdict.
- The table names the release it measured. A release that changes what runs where re-reads it.

## Amended 2026-10-10: unmeasured means a hosted runner cannot take it

The first table left four rows unmeasured and several cells "not run" that GitHub's hosted runners
could take: older kernels (as virtual machines, with KVM), macOS 14 and 15, WSL1, WSL2 on Windows
on ARM, NixOS's loader forms, a container as GitHub Actions starts one and as `docs/mcp.md`
hardens one, WSL2 off its own filesystem, as an ordinary user and under systemd, and building
from source where no asset exists. The definition is narrowed, from the table rewritten on the
probe's record (until then the first table stands as it was written):

- **unmeasured** — an asset exists for the CPU and the kernel, and the platform cannot be run on
  the hosted runners this project measures on, the owner has ruled it out, or the engine has no
  code for it. The row names which,
  from the fixed list in `spike/platforms/RUNS-RULE-2026-10-10b.md`; an apparatus fault is not one.
- **The owner's rulings of 2026-10-10**: Intel macOS is declined and not measured (hosted runners
  `macos-15-intel` and `macos-26-intel` exist); NixOS is measured in the `nixos/nix` container's
  forms — no loader, nix-ld, glibc's loader named on the command line — and not booted as a
  virtual machine; the CPUs the release does not build are built from source and not run.

The probe grows by the jobs that take those rows (`.github/workflows/spike-platforms.yml`), and
the table is rewritten from their record. The 2026-10-10 record and `RUNS-RULE.md` stand as they
were read.
