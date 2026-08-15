# Assisted discovery — first cohort results (#118)

Five targets, one agent scout (with DeepWiki available), one measured
window each, 2026-08-14 13:54–14:17 UTC. Per-target logs, proposals,
defines, committed reports, saved cases and replay transcripts live beside
this file under `<target>/`. Every artifact cited below is committed; the
saved cases embed tracked paths and replay from a fresh checkout (verified
after R1 caught the first versions embedding gitignored paths).

## The table

Three clocks, stated separately (R1: the first version mixed them):

| Target | T0 → define | T0 → first verdict | T0 → replay-confirmed | Outcome |
|--------|------------|--------------------|-----------------------|---------|
| buku | 5m02s | 10m26s (after 2 checker narrowings) | 11m29s | strict: UNKNOWN `fchown` · `--allow-unverified`: **FAIL 2/22** (L0: mid-write crash leaves bookmarks.db neither-old-nor-new; ~~buku's own recovery-open printed "file is not a database" — `target-error-line.txt`~~ withdrawn 2026-08-15: that line was the falsification gate's, see `buku/RUNLOG.md` Correction) |
| pass | 2m05s | 2m06s | — | UNKNOWN `child_process_detected` — the report's own words: "the target replaced its own image (exec)" |
| calcurse | 1m25s | 1m25s | 1m49s | **FAIL 1/11, strict oracle agreeing on all 10 operations** — an interrupted `-P --purge` truncates `apts` and destroys the bystander event it never named |
| stow | 1m29s | 1m30s | — | UNKNOWN `symlinkat` |
| devtodo | 1m39s | 2m00s | — | UNKNOWN `fchmodat` (not dodgeable from the define) |

## Human judgement — SCORED (owner, 2026-08-15; two axes)

The ☐ boxes are filled in each RUNLOG. The scoring uses two axes, because
the boxes' single axis turned out to be the lenient one:

- **Question quality (what the boxes ask): 5/5 meaningful.** Every
  proposal represents a contract-grade property (unnamed data surviving an
  operation); none is the "the JSON parses" trap the metadata bar was
  built against.
- **Drivable-slice discovery value (the harsher axis the product decision
  needs)**: calcurse **high — found**; stow high — blocked by symlinkat;
  buku medium — **judgment suspended** (the strict run's fchown refusal
  means the shim's record may be incomplete in exactly the way that could
  fabricate the torn-db world; re-pose after fchown support); devtodo
  medium-low (the lightness is target selection, not question quality);
  pass **low** — the engine-drivable slice of a meaningful contract is the
  near-trivially-atomic rename, the dangerous slice being excluded as
  nondeterministic.

On that axis the number that feeds #118's product decision is **1.5 of 5
drivable slices with discovery value today** (calcurse found; buku
suspended), not "5/5 meaningful".

*Note, 2026-08-15 (after the scoring): both premises of buku's suspension
have since resolved, in opposite directions. The fchown gap closed and the
strict re-run verified the recording (`REMEASURE.md`); the finding itself
was then withdrawn — the "unreadable to buku" leg was the falsification
gate's output, and buku recovers in every world (`buku/RUNLOG.md`,
Correction). The scores above are the owner's and stand as scored;
re-scoring, if any, is the owner's call with `REMEASURE.md` and the
correction as inputs.*

**The failure-mode inversion, recorded**: the metadata gate was designed
against an agent posing vacuous questions. None appeared. The binding
constraint was the JUDGE's reach — engine coverage — which the gate was
never aimed at. That inversion is itself a scoring result.

## Against #118's success signal — NOT yet cleared as designed; the human half is now in

- **Setup time (T0 → define)**: 1m25s–5m02s across all five — inside the
  1–10 minute bar.
- **Meaningful explorations**: the human scoring is now in (section
  above): question quality 5/5, drivable discovery value 1.5/5 today. Read
  strictly, the signal's first half (setup time) cleared and its second
  half splits — the funnel *reliably poses meaningful questions*, but
  "reliably reaches meaningful explorations" is bounded by engine
  coverage, not by the loop. The honest verdict: the signal is cleared
  for the scout side and blocked on the judge side, and the blockers are
  enumerated, issueable engine work.
- **Context, not a ratio claim** (R1: the first version drew an
  order-of-magnitude comparison across unlike scopes): this branch's whole
  apparatus-to-results arc — image build, five windows, re-runs — spans
  roughly 25 minutes of wall clock for five targets; campaign 3's full
  blind arc (seals, covenant reviews, exploration) measured ~1.5 hours for
  one target. The scopes differ in almost every dimension (blindness,
  review discipline, artifact rigor), so the numbers sit here as context.
  The like-for-like cell is declaration work: hours of skilled reading in
  the campaigns versus minutes of scouted define here — with the human
  meaningfulness verdict still owed.

## What the cohort actually found

1. **calcurse**: `-P --purge` — "Read items and write them back", per its
   own help — rewrites `apts` in place through truncation; a crash between
   `open` and `write` destroys events the purge never named. FAIL 1/11,
   oracle agreeing on all 10 operations, case replay-confirmed
   (`replay-transcript.txt`). **Scope caveat (R1)**: "verified" covers the
   declared state root (the data dir); the config dir was deliberately
   ambient outside it and the target writes there too, so the oracle's
   account is of the data subtree, not of every byte the process touches.
   Novelty deliberately unchecked (no tracker search; separate step).
2. **buku (corrected 2026-08-15 — no finding)**: the original entry here
   claimed the db was "unreadable to buku itself in 2/22 worlds". That was
   never measured: the 2/22 is the L0 byte invariant, the unreadable-to-buku
   line was the falsification gate's output over a deliberately corrupted
   db, and an instrumented re-run of the committed define shows buku's own
   recovery-open succeeding in all 22 worlds — both torn worlds carry a
   fully-synced hot journal. The L0 hybrid stands as a byte observation;
   as a contract claim against buku it is withdrawn. Measurement:
   `buku/RUNLOG.md` Correction section and `buku/inspection/`.
3. **Three unsupported syscalls, one per target** — `fchown`
   (buku/sqlite), `symlinkat` (stow/perl), `fchmodat` (devtodo) — are
   outside the trace contract. (R1: the first version dressed these as a
   "`*at` metadata family", which is technically false — fchown is not an
   *at name and symlinkat creates entries rather than changing metadata.
   Three measured absences, no invented class.) Each absence blocked one
   target here; how wide each gap reaches is untested.
4. **pass**: the measured refusal is **exec image replacement** — the
   report says "single process" and "the target replaced its own image".
   That a shell-script CLI class (pass, todo.txt-cli, nb, …) would hit the
   same wall is a reasonable expectation, but it is inference, not a
   measurement of this cohort.
5. **Determinism seams, measured where stated**: buku's add over the same
   pre-state is byte-identical; pass's same-id mv is tree-identical;
   calcurse's purge is byte-identical; devtodo's remove is byte-identical
   across a deliberate 2-second gap while its add/done stamp epoch seconds
   and differ across that gap — the per-second-flaky shape. Refusal-shaped
   paths and their measured/cited reasons: gpg session keys and lock
   salt/IV (pass, buku's lock — cited from scout sources), epoch stamps
   (devtodo — measured). This feeds #84's UNKNOWN-rate work.

## Honest limits and process slips

- One cohort, one scout, five apt-installable targets — no claim beyond
  them. The scout carries general crash-shape class knowledge (declared,
  as everywhere in this repo); the 15-minute budget never bound.
- **The proposal-artifact-first rule was broken on three of five targets**
  (calcurse, stow, devtodo): their `proposals.md` files were written after
  their explorations, with the metadata living in toml/checker comments at
  define time. The first version of this file admitted only calcurse; R1
  caught the other two by file birth times. The RUNLOG timing rows for
  stow and devtodo are corrected accordingly.
- DeepWiki was consulted for two targets and was WRONG once about the
  pinned build (buku's env var) — external repo-understanding output must
  be re-measured against the pinned version, which the loop did.
- The image is pinned by build, not by manifest: the Dockerfile uses a
  mutable base tag and unversioned apt installs (R1). What actually ran:
  buku 4.7+ds-1, pass 1.7.4, calcurse 4.7.1, stow 2.3.1, devtodo
  0.1.20+git20200830, on bookworm-slim as of 2026-08-14.
- Pre-window contact (install + `--version` only) is recorded in
  PROTOCOL.md's target table and the apparatus commit, not per-RUNLOG; the
  rule is therefore auditable only at cohort level.
- stow's and devtodo's checkers were never exercised by an exploration
  (their runs went UNKNOWN before the falsification gate); their red sides
  are unmeasured, and two of their legs were hardened post-R1 (an
  occurrence count and a pipeline-free dangling-link scan).
