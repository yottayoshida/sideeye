# Cohort-3 define: poetry, revision 2 (`poetry version patch`)

Target: poetry 2.4.1, unchanged. **This revision is not cargo-r2's
kind.** Cargo's r2 answered a refusal by swapping one piece of
apparatus and kept the operation; here the operation changes — from
`add --lock` to `version patch` — because the primary's outcome was
not a wall but a claim-reading structure: its FAIL's earliest world
was the mid-write lock (L0-only, checker-healed), and the write shape
(lock first) makes that ordering invariant for every run of `add`.
The checker-red manifest world the primary recorded at its crash
point 4 can only stand as the earliest, single-shape exhibit under an
operation whose **only** in-root write is the manifest.
`poetry version patch` is that operation, measured. Owner-approved
2026-08-22 (the deferred revision question in `../poetry/RUNLOG.md`,
taken up by name), before any engine contact with this define. Scout
sources: the primary's record, the committed revision probe below,
and the poetry CLI reference (`version patch`: bumps the version in
pyproject.toml). Assisted provenance.

## Standing under the FAIL-freeze rule (the ruling this file must carry)

The frozen charter says, in the same PROTOCOL bullet as the revision
mechanics: **"a FAIL freezes the define — later revisions cannot
produce a criterion-1 claim for that target"** (cohort-3 PROTOCOL,
restating cohort 2's "Once any explore of a target reaches a FAIL
verdict, later define revisions cannot produce a criterion-1 claim
for that target: the question would no longer precede the answer.
UNKNOWN and refusal iteration stays free"). Poetry's explore reached
a FAIL verdict before this revision existed. **Therefore nothing this
revision measures is, or can become, a criterion-1 candidate or
claim** — owner ruling 2026-08-22, on the record here before the
define freezes; the ruling exists because this file's first draft
cited the revision rule's mechanics while omitting this sentence, and
the define's R1 review caught the omission.

What this revision is for, restated under that ruling: a **sealed
minimal reproduction** of the manifest wound the primary already
measured — one crash point, one violating world, checker-red through
poetry's whole documented recovery chain, with the define frozen on
main before the engine ran — as upstream-report material behind the
standing per-report owner gate. The record's evidentiary value (the
mini-seal, the drills, the earliest-by-construction structure) is
unchanged; only its accounting is: recorded, never claimed.

## The revision probe (committed: `probe.txt`, raw `poetry-r2.strace`)

The operation changed, so the probe evidence is re-established under
the primaries' seven-condition harness (cohort2 `probes/lib.sh`
predicates, machine-judged 1–6): exit codes 0/0, non-no-op,
version 0.1.1 recorded **with poetry.lock byte-identical to the
pre-state** (the operation does not touch it), round-trip through
poetry's own reader (`poetry version --short` returns 0.1.1;
`check --lock` exits 0 — **the bumped version does not stale the
lock**), byte-determinism across two runs >=2s apart, closure clean
(unattributed 0), and **0 threads, 0 clones** under the define's
configuration (`POETRY_VIRTUALENVS_CREATE=false`) — no
python-discovery forks either; this operation spawns nothing.

## The write shape (probe strace, lines 4736-4737)

`poetry version patch` mutates the state root in exactly one
truncate-and-write, no temps, no renames, no lock contact:

1. `openat(pyproject.toml, O_WRONLY|O_CREAT|O_TRUNC)` — 2. one
   104-byte `write`.

The engine-reachable crash states are therefore: **old manifest**
(kill before 1) and **empty manifest** (kill between 1 and 2). At
syscall granularity the single write is all-or-nothing, so a torn
manifest is surgery-reachable only. **There is no earlier in-root
mutation, so a violating world at the empty-manifest point is the
run's earliest by construction** — the primary's claim-reading lesson
(which worlds stand first is a property of the run, not of a world),
applied before freezing this time. Under the FAIL-freeze ruling above
this buys evidentiary cleanliness for the report, not candidacy: the
sealed record shows the wound as the operation's only failure shape,
with no noise world in front of it.

## The property (P1)

**Kill `poetry version patch` anywhere; the project must come back
through poetry's own documented path.** Legs:

- **guard**: `pyproject.toml` and `poetry.lock` exist;
- **leg V**: `pyproject.toml` parses as TOML (python3 tomllib) —
  user-authored primary data; a torn manifest is destruction, with no
  recovery to apply;
- **leg R**: `poetry check --lock`; if red, run poetry's documented
  recovery chain, each step at most once — step 1 `poetry lock`, and
  if it fails, step 2 `poetry lock --regenerate` — then re-check. The
  whole chain failing, or the re-check staying red, is the checker's
  failure. **The chain ruling is the primary's, inherited unchanged**
  (`../poetry/proposals.md`: upstream pins bare-lock-fails as
  intended and `--regenerate` as the rebuild);
- **leg N**: the version is old-or-new — the manifest's version line
  is exactly `0.1.0` or `0.1.1`, never a third thing.

Expected world outcomes, declared ahead: the pre-write world (old
manifest) is **green**. The **empty manifest** parses as empty TOML
(leg V green — the primary's trials pinned this), the configuration
is invalid, the whole chain fails (the primary's trial row D and this
define's `R-red-chain-empty-manifest` drill, both measured), and
**that red is the expected FAIL shape** — checker-red, the combined
atomicity-and-checker form where L0 also flags the bytes, earliest by
the write-shape argument above, and under the FAIL-freeze ruling
**recorded, never a candidate**. In user terms: kill `poetry version
patch` between its truncating open and its write, and the entire
user-authored manifest — dependencies, configuration, everything, not
just the version line — is destroyed, and nothing in poetry's
documented path brings it back.

Apparatus reading, frozen before explore (the primary's, sharpened
after this define's R1 flagged a collision): the checker annotates a
timed-out step with the words "this step timed out" **only when the
step's rc was actually 124 or 137** — the legend is conditional, so
the tokens cannot appear in an ordinary red. A FAIL whose earliest
case's checker message carries that annotation is an apparatus
outcome (a container hiccup crossing the 24–60x margins), not a
verdict; the response is a re-run.

Branch rehearsal: nine for nine in the committed `checker-drills.txt`
— greens on old and new, both engine-unreachable heal branches
re-rehearsed in this define's own state (step-1 heal via a
staleness-inserting surgery carrying check's verbatim prescription;
step-2 heal via an empty lock carrying the verbatim
self-prescription — rehearsed because branch rehearsal is per-define,
not per-copied-code), the whole-chain red (the candidate shape), the
persistent-red branch (missing-README surgery: check red, step 1
rc 0, re-check red), leg V (torn), leg N (a third version), guard
(missing lock).

## The pre-define novelty scan (recorded 2026-08-22)

All queries `gh api 'search/issues?q=repo:python-poetry/poetry+<term>'`,
titles of the top pages read. Version-shaped (this revision):
"\"poetry version\" interrupted" 18 / "\"poetry version\" crash" 130 /
"\"poetry version\" corrupted" 55 / "\"version patch\" empty" 16 —
none names a crash during `poetry version` damaging the manifest.
Inherited from the primary's recorded rounds (same day):
destruction-shaped — "\"poetry add\" interrupted" 14 (nearest #6886:
a *cache artifact*, closed) / "\"poetry add\" crash" 68 / "\"poetry
add\" killed" 15 / "atomic in:title" 3 (all download-side) /
"\"pyproject.toml\" empty in:title" 2 (unrelated); positive control
"cache" 2479. No issue names in-place manifest rewriting or its
crash-destruction. The claim-time novelty gate re-runs regardless.

## Rejected shapes

- *Reading this revision as a fresh probe-slot target* — it is not:
  the cohort's five primaries and their order are frozen in
  PROTOCOL.md; this directory exists under the revision rule (a new
  directory, its define on main before its explore) with the
  operation change and its reason declared here, owner-approved. The
  probe harness was still re-run in full because probe evidence
  attaches to an operation, not a tool.
- *A lock-conservation leg* (`poetry.lock` byte-unchanged) — the
  operation measurably never touches the lock, so the leg could only
  fire on engine misbehavior L0 and the closure already watch;
  asserting more than the documented contract is the shape the
  primary's Rejected list warns against.

## Stock reproduction

Any finding must reproduce against stock poetry with no apparatus
beyond strace fault injection before it is claimed or reported — the
cohort rule, unchanged. The env pins are configuration, disclosed in
the launcher.
