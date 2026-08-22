# Cohort-3 define: poetry (target 4)

Target: poetry 2.4.1 (the image's pinned current stable). Probe:
conditions 1–6 machine-green, `../probes/poetry.txt` —
byte-deterministic, closure clean; the forecast measured **0 threads
under `POETRY_VIRTUALENVS_CREATE=false`** with python-discovery forks
remaining (children are oracle-accountable by design; whether the
engine's accounting holds them in practice is measured at explore).
Scout sources: the probe transcript, its committed raw strace, the
engine-free container trials below, and the upstream history readings
(gh api, 2026-08-22). Assisted provenance.

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
runs and fed to poetry's own reader and its documented recovery chain
(the `--regenerate` column was measured in the second trial round, the
same day, after the upstream history reading below forced the chain
question; the drill transcript re-measures the A/B/C/D shapes through
the shipped checker):

| state | `poetry check --lock` | step 1: `poetry lock` | step 2: `poetry lock --regenerate` |
|---|---|---|---|
| A: new lock + old manifest | red: "pyproject.toml changed significantly... **Run `poetry lock` to fix the lock file.**" | rc 0 — **heals**, re-check green | not reached |
| B: empty lock + old manifest | red, same prescription | **rc 1 — fails, and its error says "Regenerate the lock file with the `poetry lock` command."** | **rc 0 — heals**, re-check green |
| C: torn lock (mid-entry) + old manifest | red: a raw TOML parse error, no prescription | rc 1 — fails | **rc 0 — heals**, re-check green |
| D: new lock + empty manifest | red: "Either [project.name] or [tool.poetry.name] is required" — no prescription | rc 1 — fails | **rc 1 — fails. Nothing documented brings the manifest back** |
| E: new lock + torn manifest | red: "Invalid TOML file... Unexpected end of file" | n/a — leg V catches it first | n/a |

## The upstream history (why the chain, and where the finding lives)

The self-prescribing failure in row B is a **known, ruled-on surface**:
issue #1196 ("`poetry lock` should overwrite broken `poetry.lock`,
not error out") reported exactly this irony, PR #6753 fixed it in
1.2.2 (its fixture `tests/fixtures/invalid_lock/poetry.lock` is the
unparseable line "This lock file is broken!"), and poetry 2.0's
semantics change re-split the command: bare `poetry lock` now
preserves the existing lock (so it must read it and fails when it
cannot), `--regenerate` carries the #6753 behavior. The current
upstream test `test_lock_with_invalid_lockfile` **pins both halves as
intended** — bare lock raising "Unable to read the lock file" on the
broken fixture, `--regenerate` exiting 0 on it. What remains is a
stale-message defect, not a recovery defect: `check.py:184` and
`locker.py:358,365` still prescribe the command that fails
(`installer.py:270` already routes through a dynamic
`_lock_fix_command()`), so a user following the tool's own output
loops. That is upstream-report material (a separate, owner-gated
step), **not** a criterion-1 candidate: a FAIL built on "the
prescription failed" would be answered with "intended; use
--regenerate".

**The chain ruling (owner, 2026-08-22, before any engine contact):**
leg R follows poetry's documented recovery chain — the prescription
first, then the documented regenerate — and only the whole chain
failing (or check staying red after it) is the checker's red. The
rejected alternative is recorded under Rejected shapes.

**Where the live prospect actually is**: row D. The write shape puts
`pyproject.toml` — user-authored primary data — through an in-place
truncate-and-write, so a kill between syscalls 3 and 4 leaves an empty
manifest, and the trials show nothing in poetry's documented path can
restore it (both chain steps rc 1: the name/version the rebuild needs
were in the file that was destroyed). The same wound the formatter
half of this cohort sealed twice (black #2479, rustfmt #6041), here on
a manifest mutated as a side effect of dependency management — and the
pre-define scan below found no upstream issue naming it.

## The pre-define novelty scan (recorded 2026-08-22)

All queries `gh api 'search/issues?q=repo:python-poetry/poetry+<term>'`,
titles of the top pages read. Corruption-shaped (first round):
"corrupt lock" 75 / "truncated lock" 20 / "interrupted lock" 19 /
"disk full" 14. Recovery-shaped (second round, added after R1 flagged
the shape gap): **"Regenerate the lock file" 49 — this is the query
that surfaced #1196/#6753 and reversed the finding narrative above**.
Destruction-shaped (third round, for the row-D prospect):
"\"poetry add\" interrupted" 14 (nearest: #6886, ctrl-c corrupts a
*cache artifact* — not the manifest, closed) / "\"poetry add\" crash"
68 / "\"poetry add\" killed" 15 / "atomic in:title" 3 (all three are
download-side) / "\"pyproject.toml\" empty in:title" 2 (unrelated).
Positive control: "cache" 2479. No issue names a crash during
`poetry add` destroying `pyproject.toml`, and none names the row-D
unrecoverable state. The claim-time novelty gate re-runs regardless.

## The property (P1)

**Kill `poetry add --lock <path-dep>` anywhere; the project must come
back through poetry's own documented path.** Legs:

- **guard**: `pyproject.toml` and `poetry.lock` exist;
- **leg V**: `pyproject.toml` parses as TOML (python3 tomllib) — the
  manifest is user-authored primary data; a torn manifest is
  destruction, with no recovery to apply;
- **leg R**: `poetry check --lock`; if red, run poetry's documented
  recovery chain, each step at most once — step 1 `poetry lock` (the
  command check's red prescribes when one is prescribed), and if it
  fails, step 2 `poetry lock --regenerate` (documented in the
  command's own --help: "Ignore existing lock file and overwrite it
  with a new lock file created from scratch") — then re-check. **The
  whole chain failing, or the re-check staying red, is the checker's
  failure.** The undocumented manual deletion of the lockfile is not
  a recovery (the cargo ruling's principle); the documented
  `--regenerate` is one (the chain ruling above);
- **leg T**: the dependency set is old-or-new — the manifest names
  deppkg zero times or exactly once, never a third thing;
- **leg C**: the outside-root dependency fixture is byte-unmutated.

Expected world outcomes, declared ahead — with the leg that names each
(the black and rustfmt R1s both caught wrong-leg declarations, so the
legs here come from the trials, not from intuition): the between-writes
state (A) **heals at chain step 1 and ends green** — poetry's contract
holding. The empty-lock and any torn-lock state **heal at chain step 2
and end green** — the lock is derived data with a documented rebuild,
and upstream's test pins that split as intended; these worlds are
poetry's contract holding too, not findings. The **empty manifest
parses as an empty TOML document, so it passes leg V and falls to leg
R**: check reports the configuration invalid (no prescription), both
chain steps fail (trial D), and **that red is the candidate shape** —
checker-red, the combined atomicity-and-checker form where L0 also
flags the bytes, and user-authored primary data is unrecoverable by
poetry's whole documented path. A **torn** (mid-line) manifest is
**leg-V red** (trial E) — reachable by surgery; at the engine's
syscall-boundary kill points the manifest write is all-or-nothing, so
the engine-reachable manifest destruction is the empty file.

Apparatus reading, frozen before explore: a FAIL whose earliest case's
checker message contains "timed out" or names rc 124 is an apparatus
outcome (a container hiccup crossing the 24–60x margins), not a
verdict; the response is a re-run. The engine cannot distinguish the
two (any nonzero checker exit is a violation), so the reading has to
be frozen here, on the record, before any world exists.

Branch rehearsal: every branch of leg R's chain is seen red or heal
once in the committed drills — step-1 heal (A), step-2 heal (B, C),
whole-chain red (D), and the persistent-red branch ("chain ran, check
still red") via a fabricated missing-README state (check red,
`poetry lock` rc 0, re-check red — measured before the drill was
written). No branch of the checker can fire for the first time during
a real exploration.

## Rejected shapes

- *Prescription-only leg R* (the pre-ruling draft: red as soon as the
  prescribed `poetry lock` fails) — rejected by the chain ruling.
  Upstream's own test pins bare-lock-fails-on-a-broken-lock as
  intended behavior with `--regenerate` as the rebuild, so those FAILs
  would be manufactured candidates; the stale prescription text is a
  message defect to report separately, not a crash-consistency
  counterexample.
- *Unconditional lock regeneration in the checker* — regenerating
  before checking would erase the distinction between A (heals by
  prescription) and D (nothing heals); the conditional chain is the
  tool's own flow.
- *Asserting manifest+lock simultaneity* — poetry's own model treats
  staleness as prescribable (state A); asserting simultaneity would
  manufacture FAILs out of the documented recovery working.

## Stock reproduction

Any finding must reproduce against stock poetry with no apparatus
beyond strace fault injection before it is claimed or reported — the
cohort rule, unchanged. The env pins (`POETRY_VIRTUALENVS_CREATE`,
cache/config paths, the null keyring) are configuration, disclosed in
the launcher.
