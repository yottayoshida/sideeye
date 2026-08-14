# SCOUT — the assisted-discovery loop for agents (#118)

You are an agent asked to test whether a repository's stateful CLI survives
crashes. You may read anything: source, docs, tests, issue trackers, an
external repository-understanding service. **You propose the question;
Sideeye answers whether it survives hostile execution.** Nothing you
believe enters a verdict — Sideeye's PASS/FAIL/UNKNOWN is deterministic and
does not consult you.

## The loop

1. **Timestamp your start** (`date -u`). From here your reading is on the
   clock (~15 minutes to step 3).

2. **Scout the repo for the five things Sideeye needs:**
   - where the persistent state lives (a directory the tool reads AND
     writes — not caches, not scratch; note which is which);
   - which commands write that state, and especially which touch **more
     than one file in one operation** (cross-file transactions are the
     richest crash windows);
   - what the documentation **promises** about that state (conservation,
     consistency between files, "always valid X" claims);
   - whether an fsck / doctor / verify / undo / repair command exists —
     those are checker material AND crash-recovery contracts worth testing;
   - whether writes look deterministic (random IDs / timestamps in
     filenames or bytes defeat the byte-reproducible baseline — expect a
     recording refusal and say so up front rather than discovering it).

3. **Write at most 3 proposals.** Each MUST carry, separate from anything
   Sideeye will judge:
   - **why**: why this operation is interesting (what could plausibly go
     wrong at a crash);
   - **what property**: the user-visible or documented property your
     checker will represent (not "the file parses" — a contract someone
     relies on);
   - **where from**: the doc sentence / test / code path the claim came
     from.
   A proposal without all three does not count.

4. **Define.** Pick the strongest proposal. Write the explicit
   `sideeye.toml` (state root, setup, operation argv, check, and
   `expected_status` when the documented outcome is a refusal) and a
   checker that **fails closed**: a missing store is a failure, an anchored
   exact match beats a substring, and every failure message names its leg.

5. **Falsify and preflight.** Run Sideeye's checker falsification and
   `sideeye preflight`. An UNKNOWN is a define bug until proven otherwise:
   fix, record the fix, retry. Do not weaken the checker to make UNKNOWN go
   away — narrow the claim instead.

6. **Explore.** Run the exploration. Whatever comes back — counterexample,
   UNKNOWN, or null — record it with the proposal metadata. A null is a
   result, not a failure of yours.

## Measured lessons from the first cohort (2026-08-14)

- `sideeye preflight` takes define-surface flags, not `--config`; once a
  toml exists, go straight to `explore` — it answers strictly more.
- The operation child inherits the ENGINE's environment, not your setup
  script's exports. If the target resolves its store through an
  environment variable, export it where you launch the engine (a zero-op
  PASS with "nothing changed the state directory" is the tell).
- Prefer targets/forms with explicit path FLAGS over environment plumbing.
- Probe determinism with a `sleep 2` between the two runs — epoch-stamping
  targets are byte-identical within a second and flaky across one, the
  worst refusal shape.
- Write the proposal artifact BEFORE the define, not as comments in the
  toml. A proposal without its own metadata artifact does not count.
- Capture the engine's exit code before piping its output through
  grep/head — the pipe's exit code is not the engine's.
- mkdir the state root (and the report's directory) before `explore`; the
  engine stops at state resolution otherwise.

## What you must not do

- Call any of this "blind". It is assisted; the word blind belongs to
  ADR 0012's sealed protocol and nothing here qualifies.
- Put yourself in the verdict: no "the LLM thinks this is a bug" anywhere.
  If you believe something is broken, write a checker that a deterministic
  engine can use to prove it.
- Write a checker whose only claim is that the target's own output looks
  plausible. Anchor it in a property from step 3's metadata.
