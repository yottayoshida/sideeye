# Cohort-3 define: poetry (target 4)

Target: poetry 2.4.1 (the image's pinned current stable). Probe:
conditions 1–6 machine-green, `../probes/poetry.txt` —
byte-deterministic, closure clean; the forecast measured **0 threads
under `POETRY_VIRTUALENVS_CREATE=false`** with python-discovery forks
remaining (children are oracle-accountable by design; whether the
engine's accounting holds them in practice is measured at explore).
Scout sources: the probe transcript, its committed raw strace, and the
engine-free container trials below. Assisted provenance.

## The write shape (committed probe strace, lines 12383-12388)

`poetry add --lock` mutates the state root in exactly four syscalls,
**lock first, manifest second**, both in place, no temps, no renames:

1. `openat(poetry.lock, O_WRONLY|O_CREAT|O_TRUNC)` — 2. one 441-byte
   `write` — 3. `openat(pyproject.toml, O_TRUNC)` — 4. one 162-byte
   `write`.

The engine-reachable crash states are therefore: **empty lock + old
manifest** (kill between 1 and 2), **new lock + old manifest** (between
2 and 3 — the lock knows the dependency the manifest does not), and
**new lock + empty manifest** (between 3 and 4).

## The pre-define trials (engine-free, 2026-08-22, in-container)

Each crash-reachable state was fabricated by file surgery from normal
runs and fed to poetry's own reader and its prescribed recovery:

| state | `poetry check --lock` | prescribed recovery | after recovery |
|---|---|---|---|
| A: new lock + old manifest | red: "pyproject.toml changed significantly... **Run `poetry lock` to fix the lock file.**" | `poetry lock` rc 0 | check green — **heals** |
| B: empty lock + old manifest | red, same prescription | **`poetry lock` rc 1 — fails** | still red |
| C: torn lock (mid-entry) + old manifest | red: a raw TOML parse error, no prescription | **`poetry lock` rc 1 — fails** | still red |
| D: new lock + empty manifest | red: "Either [project.name] or [tool.poetry.name] is required" | n/a — the manifest is the primary data | — |
| E: new lock + torn manifest | red: "Invalid TOML file... Unexpected end of file" | n/a | — |

**The finding-shaped facts**: state A is poetry's own model working —
the tool detects staleness, prescribes its recovery, and the recovery
heals; a world landing there is green and rightly so. States B and C
are the same prescription **failing on exactly the states a crash
produces**: `poetry check --lock` tells the user to run `poetry lock`,
and `poetry lock` then refuses — the project is stuck until the user
deletes the lockfile by hand, a step no error message and no document
prescribes. The pre-define novelty scan (recorded 2026-08-22:
"corrupt lock" 75 / "truncated lock" 20 / "interrupted lock" 19 /
"disk full" 14, titles read; positive control passed) found no issue
naming this recovery failure.

## The property (P1)

**Kill `poetry add --lock <path-dep>` anywhere; the project must come
back through poetry's own documented path.** Legs:

- **guard**: `pyproject.toml` and `poetry.lock` exist;
- **leg V**: `pyproject.toml` parses as TOML (python3 tomllib) — the
  manifest is user-authored primary data; a torn or empty manifest is
  destruction, with no recovery to apply;
- **leg R**: `poetry check --lock`; if red, run the recovery the tool
  itself prescribes — `poetry lock` — exactly once, then re-check.
  **The prescribed recovery failing, or the re-check staying red, is
  the checker's failure** ("documented recovery first, then assert" —
  poetry prints its own recovery, so following it is the rule's
  letter). The undocumented manual deletion of the lockfile is not a
  recovery (the cargo ruling's principle);
- **leg T**: the dependency set is old-or-new — the manifest names
  deppkg zero times or exactly once, never a third thing;
- **leg C**: the outside-root dependency fixture is byte-unmutated.

Expected world outcomes, declared ahead — with the leg that names each
(the black and rustfmt R1s both caught wrong-leg declarations, so the
legs here come from the trials, not from intuition): the between-writes
state (A) **heals and stays green** — poetry's contract holding, not a
finding. The empty-lock and any torn-lock state are **leg-R red** (the
prescription fails — trials B and C). The **empty manifest parses as
an empty TOML document, so it passes leg V and falls to leg R**: check
reports the configuration invalid ("[project.name]... is required" —
no prescription in that error), leg R still attempts poetry's only
documented lever once, and its failure on an empty manifest is the
recorded red. A **torn** (mid-line) manifest is **leg-V red** (trial
E: a raw TOML parse error). Every red is checker-red — criterion-1
candidate shapes, the combined atomicity-and-checker form where L0
also flags the bytes.

## Rejected shapes

- *Unconditional lock regeneration in the checker* — regenerating
  before checking would erase the distinction between A (heals by
  prescription) and B/C (prescription fails); the conditional form is
  the tool's own flow.
- *Asserting manifest+lock simultaneity* — poetry's own model treats
  staleness as prescribable (state A); asserting simultaneity would
  manufacture FAILs out of the documented recovery working.

## Stock reproduction

Any finding must reproduce against stock poetry with no apparatus
beyond strace fault injection before it is claimed or reported — the
cohort rule, unchanged. The env pins (`POETRY_VIRTUALENVS_CREATE`,
cache/config paths, the null keyring) are configuration, disclosed in
the launcher.
