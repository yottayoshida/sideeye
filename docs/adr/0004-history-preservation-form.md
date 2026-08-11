# ADR 0004 — A second L0 form: history preservation for files that only grow

- **Status:** Proposed
- **Supersedes:** nothing. Adds a per-file judgement form beside the pre-or-post rule
  that DESIGN §12 and ADR 0003 left untouched
- **Scope:** the engine's L0 judgement and its report only. The shim, the trace format
  and the oracle comparison are unchanged; trace contract stays v4

## Context

With observation complete (#18, #19), the first real target explores 143 worlds and is
refused by the judgement model itself. omamori's audit line carries a timestamp and an
HMAC chain, so re-running the operation writes different bytes; L0's byte comparison
reads every crash world as a hybrid, and the baseline gate — correctly — reports
`UNKNOWN baseline_violates_invariant` rather than a false `FAIL 138 of 142` (#24).

Measured before decided (2026-08-11, an external measurement of omamori outside this
repository, recorded here with its date because this repo cannot re-verify it): running
`omamori exec -- /bin/true` twice from one restored state, plus one straced run, shows

- `audit.jsonl` is the only non-reproducible file, and its shape is a **strict
  extension**: the pre content is a byte prefix of the post content;
- `audit.jsonl.hwm` is rewritten, but atomically (temp + `rename`) and with
  deterministic content (`0` → `1`) — the standard rule already holds for it;
- the audit line is written through 134 separate `write(2)` calls, so a kill lands
  mid-line and leaves a torn tail;
- `omamori audit verify`, fed a log with a half-written last line, prints
  "chain intact. (1 torn lines skipped)" and exits 0 — torn tails are tolerated by the
  target's own verifier, by design.

So the class that would need a per-world fresh baseline or L2 delegation — a
**non-reproducible rewrite** — has no representative in the first real target, and the
narrow fix closes the whole measured gap.

## Decision

### 1. Classification, once, from the snapshots alone

`classify(pre, post)` builds an `L0Plan` before any world is judged. A file present in
both snapshots is judged by the **history-preservation form** iff

- its pre content is non-empty, and
- its post content differs from its pre content, and
- its pre content is a byte prefix of its post content.

Every other shared file — unchanged, shrunk, diverged, or empty in pre — keeps the
standard pre-or-post rule. Both the judgement and the report read from the same
`L0Plan`; there is no second place where the classification is computed.

### 2. The form's invariant: history is preserved

For a history-form file, the crashed state must contain the path **as a file** whose
content still **begins with the pre content**. A missing path is a violation (as
before); a path replaced by a directory or any non-file is a violation; content that no
longer starts with the pre content is the new violation `rewritten` — "its recorded
history is no longer a prefix of its content".

The appended tail is deliberately not judged. Whether a torn tail is acceptable is the
target's recovery semantics — domain knowledge — and belongs to an L2 checker, exactly
as DESIGN §12 already delegates leftover temporaries. No upper length bound is imposed:
a re-run may legitimately append a different amount, and a bound would manufacture
false positives.

### 3. The name claims what is checked, nothing more

The form is named **history-preservation**, not "append-only". A snapshot proves a
shape, never a write mechanism. To a snapshot judge this distinction is not observable
even in principle: the intermediate states a sequential rewrite leaves behind are
byte-identical to the states a true append leaves behind. Mechanisms that produce
*different* states are still caught — a rename-rewrite is atomic (pre or post only), an
unlink-recreate passes through `missing`, a truncate-rewrite passes through states that
no longer begin with pre and lands in `rewritten`.

### 4. What the baseline gate stops refusing — and what it still refuses

For history-form files, a baseline world whose content differs from the recorded final
no longer violates L0 (that is the point of the form: the prefix check does not depend
on the appended bytes). The relaxation is exactly that wide and no wider: a
non-reproducible **rewrite** — different bytes, not an extension — stays on the
standard rule, still violates in the baseline world, and still ends in
`UNKNOWN baseline_violates_invariant`. The acceptance suite pins this boundary with a
toy that rewrites a file with different bytes every run.

### 5. The report says which form judged which file

A single `l0` note, present in text and JSON alike, reports the classification: how
many files held pre-or-post, how many were judged by the history form, and which ones
(bounded). Before classification exists the note says so explicitly, so an early
UNKNOWN never carries an invented classification. Whenever the history form is in play,
`not tested` grows "appended tails (files under the history form)" — a PASS headline
must not stand without its narrowing. This is an addition to the experimental report
schema; the trace contract version is untouched (nothing about the shim↔engine
byte stream changed).

## Alternatives considered

- **Per-world fresh baseline** (issue direction 1): run an un-killed world per
  exploration and compare against it. Rejected: measured unnecessary — the prefix check
  does not depend on any baseline bytes — and it doubles every exploration for a class
  with no known representative.
- **L2 delegation** (issue direction 3): when the baseline shows non-reproducibility,
  downgrade L0 to advisory and let the checker judge. Rejected for now: its target
  class (non-reproducible rewrites) has no real representative yet, and "L0 saw a
  hybrid" must not silently vanish. The baseline gate remains the honest refusal for
  that class; the direction is recorded in #24's closing comment and waits for a real
  target to design against.
- **Declaring file classes in configuration**: breaks L0's zero-configuration identity;
  belongs to the `sideeye.toml` discussion (v0.3).
- **Including empty-pre files in the form**: `startsWith(anything, "")` is vacuously
  true, so the form would silently stop checking such files entirely. Keeping them on
  the standard rule preserves the atomic-write check, and a non-deterministic fresh log
  ends in the same UNKNOWN it ends in today — an honest refusal instead of a silent
  no-check.

## Consequences

- omamori's exploration reaches a real verdict; with `--check "omamori audit verify"`
  the target's own verifier judges every torn-tail world (predicted PASS, per the
  measurement above — a deviation is a finding).
- L0's zero-config detection narrows, deliberately: a torn tail on a history-form file
  was a FAIL for a deterministic target and is now outside L0. The narrowing is stated
  in every report (`l0` note + `not tested`), in DESIGN §12, and here.
- A file whose clean run happens to end as an extension of its pre content is judged by
  the weaker form even if it is not a log. The report names it; nothing weakens
  silently.
- The known standard-rule edge — a crashed file replaced by a directory can slip
  through when the pre or post content is empty — is unchanged by this ADR (the history
  form checks kind; the standard form is out of scope here) and is tracked as its own
  issue.
