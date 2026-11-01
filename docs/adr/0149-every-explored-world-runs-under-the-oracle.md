# 0149 — Every explored world runs under the oracle

- **Status:** Accepted (2026-11-01)
- **Amends:** ADR 0002 (the open path its Consequences record, and its cost), ADR 0053 (the alternative "Give the
  explored worlds an oracle"), ADR 0065 (the window its last section narrowed). Notes on those pages point here.
- **Refs:** #940; ADR 0119 (a world is held to the recording's operations), ADR 0141 (strace found on `PATH`),
  ADR 0145 (`docs/silent-windows.md`).

## Context

Under `--oracle` only the recording ran under strace. An explored world was held to the recording's operations
before its crash point (ADR 0119) and to what its own shim recorded, so a target that did something in a world
that the recording never did, through calls the shim does not see, reached a verdict on the shim's account alone.
ADR 0002 wrote that path down with its cost — "an oracle on all N+1 worlds" — and `docs/silent-windows.md` lists it
as `explored-worlds-no-oracle`.

Measured 2026-11-01 (Docker, Debian trixie with strace 6.13, aarch64): `spike/toys/toy_world_branch.c` writes one
file into the state through `syscall(2)` in the world armed at crash point 2 and nowhere else. On the build before
this change it is PASS, 5 of 5 worlds, with the oracle agreeing on the recording's 4 operations.

The owner ruled on the cost (2026-11-01): every world, whenever `--oracle` is given.

## Decision

1. **Under `--oracle`, every explored world runs under strace as the recording does**, the baseline included: the
   same arguments, the engine's variables passed with `-E`, the capture at `oracle-world-<k>.txt` in the work directory,
   removed once the world agrees and kept when it is refused.
2. **The world is held to its capture as the recording is**, each refusal naming the world: no output
   (`oracle_saw_nothing`); a boundary or a move between cgroups the capture shows (`child_process_detected`); a
   process leaving the process group outside the world's containment; a process other than the subject changing
   the state where the recording admitted no child (`child_touched_state_dir`); a call this version does not model
   (`unsupported_syscall_observed`); and the subject's operations compared class by class with the observer's
   (`oracle_missed_operation`, `oracle_saw_phantom`). Of the three conditions under which a child's operations are
   crash points (ADR 0053), the first — both witnesses name the same writers — is asked again in each world where the
   recording admitted children, so a child the shim was not loaded into that writes only in a world is refused there.
   The two that read waits are not: the crash point's kill cuts them short, and a world inherits the recording's
   answer on them, as before.
3. **The crash point's own call is not counted.** Under `--observe supervised` the engine withholds the call and
   kills the run, so strace prints it with no result (`= ?`, or `<unfinished ...>` with or without a resumed half
   that ends `= ?`). The last call of the thread the world's `kill_landed` record names, left that way, is dropped
   from the capture's account, whether that thread is the subject's or a child's. Any other call the kill cut short is counted, so an operation the observer missed there is
   refused rather than passed. Under the shim the crash point stops before its call, which strace never prints.
4. **The shim's own opening of the run's cgroup files is not a move.** In a contained world the shim opens
   `cgroup.kill` and the step-aside `cgroup.procs` at start and moves the descriptor above the relocation floor at
   once (`F_DUPFD`). That pair is recognised; the same path opened by anything else, or opened and not moved on the
   next line of that process, is a move, because the world's environment hands the path to the target too.
5. **The report** gains `oracle_worlds` (integer), the number of worlds compared, present when every world was;
   the `oracle` sentence adds "and agreed in each of N explored world(s)". Additive under surface 2 of
   `docs/contract-freeze.md`. The `processes` clauses about a world say "which strace watched too" under `--oracle`.
6. **Not changed**: `--oracle-fs-usage` (macOS) watches the recording only — fs_usage needs `sudo` and a sentinel
   handshake per capture — and a run without an oracle is the weaker claim `--allow-unverified` already names.

## Alternatives considered

- **The oracle on the failing world only.** It runs after a FAIL and never on a PASS, which is where the promise
  is.
- **One world in k, or a flag that turns it on.** Each leaves the path open in the runs that do not take it; the
  owner chose every world.
- **strace in a process group of its own (`-DD`).** In a contained world the kill writes `cgroup.kill`, which reaches
  strace wherever its group is; and it is not needed: killed with its tracee by `kill(0, SIGKILL)` or by
  `cgroup.kill`, strace 6.8 and 6.13 kept the line of every completed call (2000 of 2000 renames, measured
  2026-11-01), its last line being the call that killed.

## Consequences

- A world that does something the observer did not record is UNKNOWN under `--oracle`. `toy_world_branch` is
  refused in world 2 (`oracle_missed_operation`); the same rotation without the branch is PASS with
  `oracle_worlds` 5 under `--observe wrappers`, `syscalls` and `supervised` (acceptance).
- Every run under `--oracle` pays strace in each world, and a Linux run that found strace on `PATH` (ADR 0141) is
  such a run; `--no-oracle` leaves it out. Measured 2026-11-01 (Docker on one laptop, aarch64, root, medians of three, the build before against this one, both with `--oracle`): `git commit` over 68 crash points 0.63 s to 4.56 s (7 times), `spike/toys/toy_scale.c` over 102 crash points 0.25 s to 4.51 s (18 times) and over 300 crash points 1.00 s to 31.03 s (31 times) — 40 to 100 ms more per world, so the lighter a world, the larger the ratio. The owner kept every world with these figures in
  hand (2026-11-01).
- `docs/silent-windows.md` keeps `explored-worlds-no-oracle` for `--oracle-fs-usage` only.
- Where the engine cannot make cgroups, a child that leaves the process group in a world and outlives it keeps
  strace, and so the world, running until it exits, as it already did for the recording; `--world-timeout` bounds
  it.

## Residual windows

- Under `--oracle-fs-usage` an explored world still runs with no second witness, as before this decision.
- A target that opens the run's step-aside `cgroup.procs` itself and moves the descriptor above the floor the way the shim does is taken for the shim, so a move it then makes out of the cgroup is not refused there.
