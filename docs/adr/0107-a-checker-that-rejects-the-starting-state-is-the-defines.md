# 0107 — A checker that rejects the starting state is the define's, not the target's

- **Status:** Accepted (2026-10-10)
- **Refs:** #756 (met on the 2026-10-09 follow-ups 2 dogfood run, xmake); ADR 0091 (the last
  addition to `unknown_reason` and the shape of its ruling); ADR 0093 (the `cwd` observation, whose
  checker shape now meets this refusal first); DESIGN §14-13 (the falsification gate).
- **Scope:** `src/main.zig` (`phaseChecker`), `src/contract.zig` (`UnknownReason`),
  `src/report.zig` (the marked re-emission both probes share).

## Context

Before any world, the engine falsifies a declared checker: it restores the starting state,
corrupts it, and requires the checker to fail. Nothing asked the checker to *accept* the state the
define starts from. A checker that refuses that state fails in the world killed before the first
operation, and the report read as the target's FAIL: `earliest crash point 1 of N`,
`after (start)()`, `the checker exited non-zero after restart`. Measured on xmake: its first checker
accepted only `theme = "plain"`, the value the operation writes, while the seed held
`theme = "default"`; the run said FAIL 2 of 4, one of them world 1. With the checker fixed to
accept the seeded value, the same define FAILs 1 of 4.

The world before the first operation holds exactly the restored starting state — nothing the target
did is in it — so a violation there cannot be the target's.

## Decision

1. **The other side of the gate.** After the falsification has passed, the engine restores the
   starting state and runs the checker on it — the restored copy every world starts from, not
   what setup left; what a restore does not carry is `docs/cli.md`'s to say, and #678 is changing
   it — with the falsification's environment and working directory. Exit 0 passes and prints nothing. Anything else refuses the run before any
   world, as UNKNOWN `checker_rejects_initial_state`; the checker's output is re-emitted with each
   line marked `start: `, as the falsification's are marked `falsify: `.
2. **A new member of `unknown_reason`**, by owner ruling (2026-10-10). The candidates said
   something false: `checker_not_falsified` means the checker accepted a corrupted state, whose
   remedy — make the checker stricter — is the opposite of this one's, and an agent or a reader who
   acts on the reason alone would be sent the wrong way; `baseline_violates_invariant` names the
   world that was never killed.
3. **Steps.** `fix_define` under every observation mode — no run of the operation has touched the
   state it judged, so `--observe syscalls`'s step for the baseline's checker layer does not apply —
   with the `cwd` observation of ADR 0093 for a toml that declares no `cwd`. An exit of 126 takes
   `environment`, as the falsification reads it: the engine's fork stub exits 126 too.
4. **Placement.** After the falsification and after `checker_note` is written: every refusal the
   gate already had keeps its place and output, and a refusal here leaves the note
   (`falsified before the run (corrupted state -> check failed)`) true. The note is not extended —
   the README's demo block and `docs/cli.md`'s real output carry it, `spike/check-readme-demo.py`
   compares them with the demo line by line, and the README has no words to spare.
5. **Where it is raised.** `explore` and `replay`, both of which run `phaseChecker`. Never
   `preflight`, which does not run the checker.

## Alternatives considered

- **Reuse `checker_not_falsified`** — rejected by owner ruling (decision 2).
- **Reuse `baseline_violates_invariant`** — rejected: a different world.
- **Report a crash point 1 violation as the define's when world 1's state equals the starting
  state** — rejected: every world would run first, and a write the account does not hold makes
  world 1 differ from the starting state, which would let the shape through unrefused.
- **Extend `checker_note`** with "starting state -> check passed" — rejected (decision 4).

## Consequences

- **Surface 2** gains a member (35 → 36), the sixth break, recorded in `docs/contract-freeze.md`.
- **Surface 3**: such a run exited 1 (FAIL); it exits 2. The mapping is unchanged.
- **Surface 4**: a case saved at crash point 1 of such a define before #756 is refused
  `checker_rejects_initial_state` on replay rather than reproduced. Read as an honest refusal.
- A checker that rejects every state — always non-zero, or a relative argument that names nothing
  where it ran (ADR 0093) — is refused here, before any world, where it used to run every world and
  be refused at the baseline. The baseline's checker layer, and its `cwd` observation, remain for a
  checker that accepts the starting state and rejects the one the operation leaves.
- Every exploration and replay with a checker runs it once more. Against N worlds, (N+2)/(N+1).
- The one recorded FAIL this changes is xmake's first define (`spike/dogfood/2026-10-09-followups-2/`):
  searched under `spike/` for an earliest crash point of 1, five lines, all of them that define's.
  Re-measured the day this was written, in a Debian trixie container with xmake from apt (the
  record is in the pull request that carries this ADR): the define FAILs 2 of 4 at crash point 1
  on the build before it and is refused `checker_rejects_initial_state` on this one, its `start: `
  line saying `theme is 'default'`; the fixed checker FAILs 1 of 4 at crash point 2 on both.
