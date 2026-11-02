# 0150 — A declared rerun invariant decides a crash world

- **Status:** Accepted (2026-11-01)
- **Amends:** ADR 0078 (it declined templates for the judged set; this adds one built-in invariant a define may
  declare instead of writing it), ADR 0072 (a recovery still decides no verdict; this is not a recovery).
- **Refs:** #942; #861 and #873 (the checkers this does by hand); ADR 0043 (`scratch`), ADR 0091
  (`nothing_could_fail`).

## Context

The defects found through a checker in #861 (useradd, dpkg-divert, Alembic) and #873 (yoyo) have one shape: run the
tool again from the crash state, and it fails, or leaves the state broken. Each checker ran the operation again by
hand and read the result. Writing that checker is the heaviest part of a define, and DESIGN.md's L0 section left
"a future built-in invariant stated in terms the correct program can actually satisfy" open for it.

The owner ruled (2026-11-01) that a built-in invariant may decide a verdict when a define opts in.

## Decision

1. **`invariant = ["rerun"]` in `[define]`, or `--invariant rerun`.** An array, so a second built-in can join under
   the same key; `rerun` is the one name, and any other refuses as a define error.
2. **Two reference runs, before the worlds.** The operation is run with no shim and no trace, from the state the
   define starts from (restored as every world is), twice; and once more from the first run's result. Each run is
   held in a cgroup of its own where the engine can make one, under `--world-timeout`, with the environment's pin
   library and nothing else preloaded. If the two runs from the start do not end alike — exit status, names, kinds,
   contents, `scratch` excluded — the run is refused `baseline_run_failed` (`second_run_diverged`): nothing fixed
   would be compared against.
3. **Each world, and the baseline.** After the checker, the crash state is restored and the operation run once more
   the same way, and its state sampled twice, refusing `state_not_quiescent` when the samples differ. The world passes when the run ends as the first reference or as the second, compared as above,
   except that a path the crash left — present in the crash state, absent from the start and from that reference,
   and unchanged by the run — is counted rather than compared. Otherwise it fails as a checker fails: it can be
   `checker_earliest`, its case is saved, and in the un-killed baseline world it is `baseline_violates_invariant`.
4. **The checker's falsification probe does not apply.** It exists to catch a checker that passes whatever it is
   given; the comparison is the engine's own, held by its tests and acceptance's toys.
5. **Surfaces.** A config key and a flag (surface 1); the report's `invariants` and `rerun` (surface 2, optional
   fields); a saved case at version 10 carrying `define.invariant` (surface 4). No MCP tool's input names it; a
   toml given to `sideeye_explore_config` can declare it, and a version 10 case replays with it.

## Alternatives considered

- **Reported beside the verdict only, as a recovery is.** The owner ruled for a verdict.
- **On by default.** An operation that does not end alike twice would be refused wherever it is used.
- **Exclusive with `check`.** The useradd checker reads legs the rerun does not; both are wanted there.
- **The recording's final state as the first reference.** It was written with the shim loaded and not from a
  restored state, while every world is restored and re-run without it, so the two would differ wherever a restore
  does (a directory's owner bits, which it adds).
- **Comparing the crash's leftovers too.** A temporary file a crash leaves under a random name is what a correct
  program leaves; every target writing through such a name would fail.
- **Permission bits in the comparison.** The snapshot comparison every other part of the engine uses does not
  judge them.

## Consequences

- A define can reach FAIL on "the next run does not recover" without a checker. Measured on toys
  (`spike/toys/toy_rerun.c`, acceptance): a lock left by the crash FAILs, a rename-into-place PASSes, a mkstemp
  rename PASSes with its leftovers counted, and an operation writing the time is refused before the worlds.
  Measured on #861's defines with their checkers removed (2026-11-01, Docker, the 2026-10-14 snapshot of Debian
  trixie, `--oracle`; useradd without its libfaketime pin, both runs on one day): useradd PASS over 71 worlds by
  L0 alone, FAIL with the rerun invariant from world 5 (the run again exits 10, `etc/group` differs); dpkg-divert
  PASS over 12 worlds, FAIL from world 11 (`usr/bin/tool` left beside its diversion); Alembic `nothing_could_fail`
  by L0 alone, FAIL from world 15 (the run again exits 1); and #873's yoyo 9.0.0 define, `nothing_could_fail` by L0
  alone, FAIL from world 28 (the run again exits 1). All four reach FAIL without their checkers, as #942 expected.
- Each world runs the operation one more time, so a run takes about twice as long, and under `--oracle` the
  world's strace (ADR 0149) is paid once, by the world, not by the rerun.
- An operation that varies only by chance between runs can still FAIL a world it happened to vary in; the second
  reference run and the baseline narrow that, and `scratch` or a pin removes it.

## Residual windows

None: this adds a way to fail a world and changes nothing about what the witnesses see.
