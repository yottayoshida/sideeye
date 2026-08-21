# Criterion 1, second cohort — the campaign protocol (#183)

This directory is a criterion-1 search under the provenance gate (ADR 0017,
tracked by #140), not a wall-measurement experiment: cohort 1
(`spike/assisted/`) measured how high the wall between a fresh repo and a
first meaningful exploration is; this cohort exists to produce — or to fail
to produce, honestly — one qualifying find. Everything below was committed
before any probe, explore, or target-behavior measurement. Pre-freeze
contact with the targets was install plus `--version` only — the cohort-1
pre-window rule — and it happened once, in this file's own image build
(versions recorded under Versions below). That order is the point: the
rules that decide what counts are not allowed to know the results.

## Targets and selection (hard gate cleared 2026-08-21)

Selection followed the owner rule quantified 2026-08-16 (≥500 stars, more
than one contributor, activity within the last month — all three — and the
owner's sign-off before any measured contact). The candidate list went to
the owner with the numbers below and was approved on 2026-08-21; the public
record is <https://github.com/yottayoshida/sideeye/issues/183>.

| Target | Stars | Contributors | Latest activity (measured 2026-08-21) |
|--------|-------|--------------|----------------------------------------|
| BorgBackup (borgbackup/borg) | 13,629 | ≈324 (GitHub contributors list) | push 2026-08-20 |
| Mercurial (mercurial-scm.org, off GitHub) | n/a — see note | multi-contributor; ~20-person sprint, May 2026 | release 7.2.4, 2026-08-11 |
| Jujutsu (jj-vcs/jj) | 31,102 | ≈364 | push 2026-08-21 |
| KeePassXC (keepassxreboot/keepassxc) | 28,479 | ≈389 | push 2026-08-12 |
| Bun (oven-sh/bun) | 95,530 | ≈451 | release 1.4.0 (stable), 2026-08-20 |

Mercurial note: the stars threshold is a GitHub proxy that does not exist
for off-GitHub hosting, and the eligibility rule as written
(`spike/assisted/PROTOCOL.md`) admits no substitute. Its owner is its
amender: at sign-off the owner ruled, for this cohort only, that the bar
the proxy stands for — demonstrably alive, at scale, multi-contributor —
is cleared by the primary record at
<https://www.mercurial-scm.org/news/2026>: releases 7.2 (2026-01-29)
through 7.2.4 (2026-08-11), and the London sprint recap reporting ~20
daily participants (May 2026). The general rule text is deliberately not
edited; a future off-GitHub candidate faces the same explicit ruling, not
a precedent applied silently.

**Order** (amended from the selection-day sequence on the same day, before
any measured contact; the reasoning is recorded on #183): **Borg →
Mercurial → Jujutsu → KeePassXC → Bun**. Composition is frozen — no
swaps, no substitutions, no additions. A target that walls yields its slot
to the next; it does not leave the record. If every target walls or nulls,
that outcome is published as §18 material under #140's honesty note — the
freeze is what makes an empty-handed cohort publishable.

## Provenance: assisted, scout named

Every claim from this cohort carries the assisted label. The scout is an
external LLM analysis provided by the owner at selection (2026-08-21),
whose sources are the targets' own documentation: KeePassXC
`docs/topics/DatabaseOperations.adoc`, the Borg FAQ and README transaction
claims, `hg help recover`, the Jujutsu architecture and tutorial pages, and
the Bun lockfile docs — plus this repository's own apparatus analysis of the
same date (recorded on #183). Blind is off the table for the whole cohort
and no run under this protocol may ever be described with that word.

## The probe gate (engine-free, before any define exists)

Each target, in cohort order, gets a probe before its define is written.
The probe is normal execution only — no kill, no crash, no checker, no
engine — so no failure of any target can be observed and the provenance
gate stays clean: what the probe measures is fitness for this apparatus,
not the target's crash behavior.

One committed transcript per target (`probes/<target>.txt`, raw output)
must pin **all seven** of the following. All seven or the probe has not
passed — a transcript missing any condition is a failed probe (re-run it
or record the wall), never a partial pass:

1. **Exit codes** of both runs, matching the operation's success convention.
2. **Non-no-op**: the state tree after the run differs from before it.
3. **Artifact count**: exactly the expected number of new artifacts
   (archives, changesets, entries) exist afterward.
4. **Content round-trip**: the artifact reads back with the bytes/content
   that were put in.
5. **Byte determinism**: two runs from the same pre-state, started two or
   more seconds apart, leave state trees that `diff -r` reports identical.
6. **State-root closure**: from one `strace -f` run, every mutating path is
   listed; every persistent write lands inside the candidate state root, or
   is excluded with a written reason showing it is scratch/cache that does
   not feed the next invocation, the checker, or recovery.
7. **Ambient reset**: the client state living outside the state root (e.g.
   `BORG_BASE_DIR`, `$HOME` caches) is named, and the reset procedure that
   makes runs comparable is shown in the transcript.

The strace run doubles as the shim-visibility forecast: threads, forks and
raw-syscall patterns are noted, because the engine will refuse what the
shim cannot see and it is cheaper to know first.

**Positive control, before any probe result is accepted**: a
known-nondeterministic operation (the pre-declared candidate is unpinned
`borg create`) goes through the same determinism check and must split —
and this runs **first**, before the first target's probe verdict counts.
A probe harness that has never flagged anything proves nothing about the
probes it passed (the repo rule: a new guard is falsified against its own
predicate before it is trusted).

### Probe plans, fixed here (operation, pre-state, state root, expected artifacts)

The pass conditions above are only unarguable if what is being probed is
fixed before the probe runs. Per target — apparatus plumbing (exact env
variable names, temp paths) may be corrected at probe time with the
correction recorded in the transcript, but the operation, the pre-state
shape, the candidate state root and the expected artifacts are frozen
here:

1. **Borg** — pre-state: `borg init --encryption=none` repo inside the
   state root; a three-file source tree with pinned mtimes **outside** it.
   Operation: `borg create --timestamp 2026-01-01T00:00:00
   <repo>::probe <src>`. State root: the repo directory. Expected: exactly
   one new archive; `borg list` names it; `borg extract` round-trips the
   source bytes. Ambient: `BORG_BASE_DIR` under a reset-between-runs
   directory.
2. **Mercurial** — pre-state: an `hg init` repository with two committed
   files (pinned `--date`, pinned user, `HGRCPATH` pointing at a fixed
   file) and one modified working file. Operation: `hg commit` with pinned
   `--date`, user and message. State root: the **whole `.hg`**. Expected:
   exactly one new changeset; `hg cat` round-trips the committed bytes.
3. **Jujutsu** — pre-state: a `jj git init` repository with one committed
   change and one modified working file. Operation: `jj commit` with a
   fixed message, identity and timestamps pinned via jj's documented
   reproducibility environment (exact names read from jj's docs at probe
   time and recorded). State root: the whole `.jj`. Expected: exactly one
   new commit and one new operation-log entry; `jj file show` round-trips.
4. **KeePassXC** — pre-state: a `keepassxc-cli db-create` database (probe
   password on stdin — the probe is manual; stdin is not the engine).
   Operation: `keepassxc-cli add` of one entry. State root: the directory
   holding the `.kdbx`. Expected: the entry listable by `keepassxc-cli
   ls`; determinism expected to fail (pre-declared).
5. **Bun** — pre-state: a minimal project (`package.json`) inside the
   state root; a dependency tarball prepared **outside** it. Operation:
   `bun add` of that local tarball, cache directory pointed at a
   reset-between-runs ambient path, no registry access. State root: the
   project directory. Expected: the dependency present in `node_modules`,
   the lockfile updated, `bun pm ls` names it.

A target that fails its probe records a **named wall**: which condition
failed, the raw evidence, and a re-check against the latest upstream stable
before the wall is called terminal (a wall measured only on a distro
package is a fact about the package until the current release confirms
it). Then the next target runs. Walls are outcomes, not detours.

Pre-declared expectations, so the later reading is not post-hoc (evidence
on #183): Borg's `time_end` is start plus a monotonic duration and is
stored in archive metadata (read in `1.4-maint` and `1.4.5`
`src/borg/archive.py`) — its determinism probe is expected to fail.
KeePassXC's save is encrypted with fresh randomness per write — same
expectation. Bun is expected to be heavily multi-threaded with possible
libc bypass. Mercurial (state root: the **whole `.hg`**, never a
`.hg/store` slice — a store-only root would restore the store while
`.hg/dirstate` still points at a commit the store no longer has) and
Jujutsu are the surviving-candidate hypotheses, and stay hypotheses until
their probes pass.

## The mini-seal, sharpened for #140

Cohort 1's mini-seal (PROTOCOL.md of `spike/assisted/`, 2026-08-15) ordered
the claim: define pushed, then explore, then artifacts pushed. #140's gate
is stricter than the claim — the define must be committed before this
project observes **any** failure of the target in execution. This cohort
therefore adds:

- **No engine explore before the define is pushed.** Probes are engine-free;
  the first `sideeye explore` against a target happens only after its
  complete define (toml + checker + setup + launcher) is on main.
- **A define revision is a new target directory** (`borg/` → `borg-r2/`),
  never an in-place edit. The verifier anchors a define at its introduction
  and D2 demands blob identity between that point and the artifacts; an
  in-place fix is structurally red. A new directory is an `A` event on the
  first-parent line under every merge style — a delete-and-re-add inside
  one merge collapses to `M` and moves no anchor. After the revision
  merges and before exploring, `git log --first-parent --diff-filter=ACR
  -- spike/cohort2/<dir>` must show the introduction standing on main
  (`verify-assisted.sh` has no dry-run mode; without artifacts it exits 2).
- **A FAIL freezes the define.** Once any explore of a target reaches a
  FAIL verdict, later define revisions cannot produce a criterion-1 claim
  for that target: the question would no longer precede the answer.
  UNKNOWN and refusal iteration stays free, through new directories.
- **Honesty bound, stated plainly**: the freeze above is discipline plus
  public history, not machinery. Nothing here can prove what happened on a
  private disk first — the same bound `verify-seals.sh` and
  `verify-assisted.sh` carry. What the public history does show is checked
  at claim time, and precisely:
  - `verify-assisted.sh spike/cohort2/<target>` green proves the
    define **as the verifier defines it** — the toml, checker and setup —
    strictly precedes the artifacts, byte-identical. The launcher is
    outside D1, and D2 holds it only when it exists at the define anchor —
    a launcher introduced after the anchor and edited between explore and
    artifacts would show D3 nothing but its introduction. This cohort
    closes that gap by rule rather than by reading: **the launcher ships
    with the define** — an `ops/` without its `explore.sh` is not a
    complete define and does not open exploration. Present at the anchor,
    the launcher is held byte-identical by D2 like everything else, and a
    launcher revision is a define revision (new target directory).
  - This file is outside the verifier's define set entirely; its history
    is the only thing holding it. The claim transcript therefore includes
    `git log --first-parent -p -- spike/cohort2/PROTOCOL.md` — full
    patches, so every post-freeze amendment is visible inside the claim
    itself, not merely datable. And one rule about amendments binds them
    in advance: **an amendment made after a target's first explore cannot
    change how that target's outcome is read.**

## Claim reading, frozen before the first explore

- A **criterion-1 candidate** is a run whose saved case — the earliest
  violating world, the only one the engine saves — has the **declared
  checker** as its violated invariant: the target's own documented recovery
  was followed and its documented promise still broke.
- An **L0-only FAIL** (a byte-form violation on a path the target's own
  contract recovers or rewrites) is recorded as a precision-limit
  observation and never claimed. This is the checker-cookbook's #35 ruling
  (git's `COMMIT_EDITMSG`, measured 2026-08-11) applied cohort-wide, in
  advance. The per-world attribution apparatus of `spike/followup-144` is
  the reference when a report needs the full world-by-world story.
- L0's reach is narrow by design (DESIGN §12: files present in only one
  snapshot are unconstrained; append-extended files are judged by history
  preservation). This rule does not predict L0 noise; it fixes the reading
  in case it appears.
- Everything downstream of a candidate is unchanged from the standing
  gates: novelty (recorded tracker search with a positive control),
  per-report owner approval before any upstream filing, author
  confirmation, fix, replayed regression case (#82 machinery).

## Checker rules for this cohort

- The checker runs **directly on the crashed state** (the engine snapshots
  and judges L0 before the checker runs; buku's checker recovery-opening
  the crashed db is the precedent). No scratch copies — a copied repo is a
  relocated repo to tools that track their own paths.
- **Documented recovery first, then assert.** For a Borg-shaped target:
  remove the stale lock a killed process leaves (`borg break-lock` — the
  documented step for exactly that, and only that: it is lock removal, not
  repair), then check the repository, then assert the pre-existing
  archive's presence and its extracted bytes. Content conservation claims
  attach to the extraction comparison, never to a structure check alone.
- **Every leg is seen red once, separately** — one corrupted-byte drill
  does not falsify six legs. The engine's own falsification gate
  (`checker_not_falsified`) stays the second net, not the first.
- The checker must pass the un-killed baseline world (the engine refuses
  otherwise), so every assertion must hold on the operation's normal
  outcome.

## Versions

The image (`Dockerfile` here) is pinned by BUILD, not by manifest: the base
tag is mutable and apt packages are unversioned, so a rebuild may drift.
The freeze build (2026-08-21, arm64) measured: borg 1.4.0 (apt trixie;
upstream stable is 1.4.5 — the re-check rule below covers the gap),
Mercurial 7.2.4, jj 0.44.0, keepassxc-cli 2.7.10, Bun 1.4.0, strace 6.13,
Python 3.13.5. That install-and-`--version` pass is the only pre-freeze
target contact. The versions that actually run are re-recorded in each probe
transcript and RUNLOG. Three pins are exact, fetched on the host by
`fetch-artifacts.sh` (the build machine's TLS-intercepting proxy broke
in-container pip verification — measured, 2026-08-21 — and a stock
container's curl shares the same trust store, so the same failure is
inferred, not measured: curl was dropped from the image instead.
Downloads run host-side; the script carries the pins and the Dockerfile
re-verifies every copy): Mercurial 7.2.4 by PyPI's published
sdist sha256, Bun 1.4.0 by upstream's SHASUMS256.txt, jj v0.44.0 by a hash
measured from the 2026-08-21 download — upstream ships no checksum asset
for it, so that pin is first-download trust, stated as such.
Any FAIL, and any wall that terminates a target, is re-confirmed against
the latest upstream stable before it is recorded as final.
