# Assisted discovery — first cohort results (#118)

Five targets, one agent scout (with DeepWiki available), one measured
window each, 2026-08-14 13:54–14:17 UTC. Per-target logs, proposals with
their why/what-property/where-from metadata, defines, reports and saved
cases live beside this file under `<target>/`.

## The table

| Target | Window (T0 → verdict) | Outcome | Where the funnel stopped |
|--------|----------------------|---------|--------------------------|
| buku | 11m29s (incl. 2 checker narrowings; replay-confirmed) | strict: UNKNOWN `fchown` · unverified oracle: **FAIL 2/22** — mid-write crash leaves bookmarks.db neither-old-nor-new; buku's own open says "file is not a database"; replay-confirmed | engine (fchown) |
| pass | 2m06s | UNKNOWN `child_process_detected` — shell script execing coreutils/gpg | engine (multi-process) |
| calcurse | **1m49s** (replay-confirmed) | **VERIFIED FAIL 1/11** — an interrupted `-P --purge` truncates `apts` and destroys the bystander event it never named; strict oracle agreed 10/10 | — (clean finding) |
| stow | 1m30s | UNKNOWN `symlinkat` | engine (symlinkat) |
| devtodo | 2m00s | UNKNOWN `fchmodat` (not dodgeable from the define) | engine (fchmodat) |

## Against #118's success signal

- **Setup time**: every window landed between 1m30s and 11m29s — inside
  (buku marginally over) the 1–10 minute bar, against a campaign-measured
  baseline of ~1.5 hours for a full blind arc. The wall the experiment was
  built to measure is down by an order of magnitude.
- **Meaningful explorations**: 2 of 5 funnels reached exploration; both
  produced counterexamples of their declared, metadata-carried property
  (one verified, one unverified-oracle). The other 3 stopped at the
  ENGINE, not at the scout: the questions were posed with metadata in
  under two minutes each, and the judge could not execute them.
- **Human judgement (yotta)**: the meaningful-question scoring column in
  each RUNLOG is deliberately unfilled — that call is not the agent's.

## What the cohort actually found

1. **calcurse (verified)**: `-P --purge` — "Read items and write them
   back", per its own help — rewrites `apts` in place through truncation;
   a crash between `open` and `write` destroys events the purge never
   named. The topydo class from campaign 1, reached in 109 seconds.
   Novelty deliberately unchecked (no tracker search; that is a separate
   step with its own rules).
2. **buku (unverified oracle)**: a mid-write crash leaves the sqlite db
   unreadable to buku itself in 2/22 worlds. Needs the fchown gap closed
   before it can be a verified claim.
3. **Three engine coverage gaps forming one class**: the `*at` metadata
   family — `fchown` (buku/sqlite), `symlinkat` (stow/perl), `fchmodat`
   (devtodo) — is outside the trace contract, and each absence turns a
   whole target family into UNKNOWN. Multi-process targets (pass, and
   every shell-script CLI by construction) are a fourth, separate gap.
4. **Determinism cartography comes free**: the scout measured, per target,
   which operations are byte-reproducible (buku add over same pre-state;
   pass same-id mv; calcurse purge; devtodo remove) and which are
   refusal-shaped and why (gpg session keys; random UIDs; epoch stamps —
   devtodo's being per-second flaky, the worst kind). This is exactly the
   input #84's UNKNOWN-rate work wants.

## Honest limits

- One cohort, one scout, five apt-installable targets — no claim beyond
  them. The scout carried general crash-shape class knowledge (declared,
  as everywhere in this repo); the 15-minute budget was never binding.
- DeepWiki was consulted for two targets and was WRONG once about the
  pinned version's behavior (buku's env var) — external
  repo-understanding output must be re-measured against the pinned build,
  which the loop did.
- buku's FAIL rests on `--allow-unverified`; the report says so and so
  does this file.
- Process slips, recorded: the calcurse proposal artifact was formalized
  after its define (metadata existed in comments; the protocol wants the
  artifact first), and one rc was read through a grep pipe before the
  raw-rc habit caught it.
