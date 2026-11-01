# 0143 — A define declares its controls, and preflight reports which of the checker's legs each one turns red

- **Status:** Accepted (2026-10-31)
- **Refs:** #943 (the owner's ruling on its acceptance case, 2026-10-31); #873, #861 (the hand-written controls);
  ADR 0078 (Sideeye reports what it decided, and infers nothing about the target); ADR 0072 (`[recovery]`, the section
  this one is shaped after); `spike/controls-943/` (the acceptance), `spike/check-controls.sh` (every word).
- **Scope:** the config format (`[controls]`, surface 1 of `docs/contract-freeze.md`), the checker's environment
  (`SIDEEYE_LEGS`), `sideeye preflight`, the preflight document's `controls` field (surface 2).

## Context

A checker is trusted only once each of its legs has been seen failing, alone. Every campaign that wrote one wrote
that proof by hand as well: a script per leg that builds a broken state, a loop running the checker over each, and a
reader of its output. The 2026-10-14 mechanisms run did it for eleven targets (`apparatus/controls.sh`), and the
2026-10-15 authoring run asked each subject to (#873). Which leg a broken state exercises was left to the author, and
when a control turned two legs red, nothing said so: Alembic's leg-a control printed `a=FAIL … d=FAIL` in the
transcript and the coupling was found by a reader.

#943 asked the engine to run the controls a define names and report which leg each turned red. Its acceptance case
was yoyo's two controls from the authoring run, which both graders judged coupled. They were judged against the
**card's** legs — the target's contract as the study wrote it — and the subject's checker, run over them, turns only
its own leg red in both (`runs/python3-yoyo/final/controls.txt`). The engine cannot see a card; ADR 0078 keeps it
from inferring one. The owner replaced the acceptance case with one the engine can see, Alembic's leg-a control
(2026-10-31).

## Decision

**A define may declare `[controls]`, one command per checker leg, and `sideeye preflight --config` runs them on the
state the recording left and reports, per control, which legs the checker turned red — as one word.**

- **The section.** `[controls]`, keys the leg names (letters, digits, `_`, `-`, at most 64), values a command in the string form
  only, as `[recovery]` takes it; a relative command resolves against the toml's directory. It needs `check`. A new
  section, under the additive allowance of surface 1: a define without it reads exactly as before.
- **How the checker reports its legs.** The engine hands every checker `SIDEEYE_LEGS`: under preflight's controls a
  file it removed first, read afterwards; everywhere else a file under the work directory that nothing reads, removed
  before each run, so a checker that writes to it runs under `set -u` in any world. Not `/dev/null`: a checker that
  replaces or removes the file it is handed would, as root, replace or remove the system's. One `<leg> ok` or `<leg> fail` line per leg.
- **Where a control starts.** From `final`, the snapshot of the state the recording left, restored before the
  baseline, before each control, and after the last — the state the hand-written controls built by seeding and running
  the operation, here without running anything again.
- **The words.** The checker runs first on `final` with nothing broken; that baseline is `none` only when it wrote at
  least one leg, every leg `ok`, and exited 0. Otherwise every control reads `baseline_red` and none is run. A control's word is the
  first that applies: `baseline_red`, `control_failed`, `legs_malformed`, `legs_not_reported`,
  `its_leg_not_reported`, `legs_incomplete`, `exit_disagrees`, `none`, then `only_its_leg`, `more_than_its_leg` or
  `not_its_leg`. A signal or exit 126 is not 0.
- **Preflight only, and no exit code.** The words are information for the author, not a refusal: preflight's exit
  code and `outcome` do not move, unless a control leaves the state where the engine cannot rebuild it, which is
  refused as a world's rebuild would be. Explore reads `[controls]`, refusing the same mistakes, and does not run it.

## Consequences

- The Alembic define with its four controls declared reports a, `more_than_its_leg` (a and d), and b, c and d
  `only_its_leg` — the hand-written run's transcript, line for line (`spike/controls-943/`).
- yoyo's two controls read `only_its_leg`. Whether a leg asks what the target promises stays with the author;
  `docs/checker-cookbook.md` Recipe 7 says so with that run as the example.
- `its_leg_not_reported` compares the key with the legs the **baseline** wrote, not the control's run: a checker that
  stops at its first red leg would otherwise turn every misspelt key into `legs_incomplete`, and every early stop into
  a misspelling.
- Nothing outside the state directory is put back between controls, as nothing is between worlds; a control that
  writes elsewhere is seen by the next.

## Alternatives considered

| rejected | why |
|---|---|
| Read the legs off the checker's own output (`a=ok b=FAIL(…)`, the campaigns' convention) | Every existing checker would run unchanged, but a value that holds a space or `=` is misread, and a misread leg is a wrong word printed with confidence. A file of its own is unambiguous. |
| One checker command per leg | Breaks checkers that run the target's recovery once and then judge every leg after it — Recipe 4: the order of the legs is part of the contract. |
| Start each control from the setup's state | Not the state the hand-written controls broke. Alembic's define has no setup, and leg d's control drops a column only revision 2 creates, so it would fail before breaking anything. |
| A subcommand, `sideeye controls` | A second surface (completions, MCP, docs) for a step authors take where they already run preflight. |
| Compare with the target's contract (#943 as filed) | The engine has no contract to compare with, and ADR 0078 keeps it from inventing one. |
