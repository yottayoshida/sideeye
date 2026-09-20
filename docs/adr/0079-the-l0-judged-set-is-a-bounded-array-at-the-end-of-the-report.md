# 0079 — The L0 judged set is a bounded array at the end of the report

Status: Accepted (2026-09-20)

## Context

ADR 0078 ruled that the repeated authoring cost #618 measured is **updating the judged set**,
and that the part Sideeye can remove is reporting it rather than deciding it. It filed the
work as #638 rather than building it beside its own justification, and left three questions
open: the bound on the field, that the summary sentence stays as it is, and whether reporting
the set removes the cost at all.

This ADR answers the first. The other two are unchanged: `buildL0Note` keeps its three-name
cap (ADR 0004), and whether a subject that can see the set authors a correct define is a
second experiment.

The set itself is `L0Plan.files[].rel` (`src/engine/judge.zig`): every path present in **both**
the pre and post snapshots, whose kind on both sides is one the built-in invariants compare,
minus what `[define] scratch` declared. The engine already computes it once, in one place, and
reports only its size.

## Decision

**A bounded array of the L0 judged set, named for L0, written last in the JSON report.**

Two new optional fields, present on any run that reached classification:
`l0_judged_paths` (string[]) and `l0_judged_paths_omitted` (integer).

**Named `l0_`, not bare `judged_paths`.** `judgeL1` judges the post-only entries' durability
and the pre-only entries' absence; neither enters `L0Plan.files`. A run with a marker therefore
has paths that are judged and would not appear under a bare name. `docs/report-schema.md`
states that a field whose meaning changes gets a new name rather than changing silently, so a
bare name would make including the L1 set later a break. The prefix keeps that door additive.

**Last in the document, after `not_tested`.** This is the only field in the report whose length
grows with the state tree. Every other position displaces something: placed beside `scratch` —
where its presence rule and its meaning would put it — it pushes `message`, `next_step` and
`earliest` back, which are the fields a reader of a FAIL needs first. Written last it moves
nothing. The earlier draft argued the opposite from a measurement (the `lmdb-utils` subject read
`head -c 3000` of its report at `07:49:40`); adversarial review showed that measurement argues
against the early position, not for it, and that a 3000-byte prefix of this document is not
valid JSON in any case.

**Bounded at 1000 entries** (owner ruling, 2026-09-20) **and at 64 KiB of names**, whichever
binds first, with the remainder counted rather than dropped silently. The state tree has no entry ceiling — `max_state_tree_bytes` bounds held
memory at 256 MiB, which a tree of many small files reaches at a count in the millions — so an
unbounded array would be the one field that scales with the target's tree. Truncation takes a
prefix in `rel` order, which `finalizeEntries` guarantees is sorted — as far as whichever
ceiling binds first allows, and nothing at all if the names could not be allocated.

**A truncated run does not name its judged set, and the page says so.** The promise this field
makes is "the whole set, or a prefix of it and a count of the rest", never "the whole set" and
never a fixed count — which of the two ceilings stopped it is not something a reader has to
work out. A
non-zero `l0_judged_paths_omitted` is itself the actionable reading: a define judging more than
a thousand paths is not one a person is authoring carefully, and the remedy is to narrow the
state directory rather than to read the list.

**Presence is carried by a flag of its own, not derived from `l0`.** Review asked the
question, and it is a fair one: `l0_note`'s default already reads "not classified (the run was
refused before L0 classification)", so the fact exists. Deriving from it means comparing prose,
which puts the same judgement in two places and lets one of them lie the day the sentence is
reworded — the shape this repository has been bitten by before. Deriving it properly would mean
splitting `l0_note` into an enum plus a string, which is a change to the account field and
outside what this decides. A boolean beside the two fields is the small honest version.

**The array is written through `jsonArrayField`, and that is deliberate.**
`spike/check-report-schema.py`'s fifth claim reads only the `jsonString(w, arena, X)` calls in
`buildJson`'s own body and requires each argument to be a shared value; `jsonArrayField`'s
internal call is outside that body, so this design does not touch the claim (measured: 33 call
sites, no violations). Inlining the array into `buildJson` — which a later reader might do
thinking it clearer — is what would turn the claim red, so it is recorded here rather than
learned from CI.

## Alternatives considered

| rejected | why |
|---|---|
| **Unbounded array** | The report would scale with the target's state tree — the only such field. Adding a bound afterwards removes content a consumer could see, which surface 2 treats as a break (the `oracle_verified_across_runs` withdrawal is the precedent). |
| **A byte budget *instead of* a count** | Both are kept, and the review that pressed for the byte budget was right about why. An entry count does not bound the document — `contract.max_path` is 4096, so a thousand names is four megabytes before `jsonString` expands a control byte sixfold — and **the MCP server reads the report with a 4 MiB cap, answering a larger one with a tool error rather than a verdict** (`src/mcp.zig`). Until this field nothing in the report grew with the target's tree, so that ceiling was unreachable; a count-only bound would have made it reachable and turned a PASS into "sideeye produced no report". The count stays because it is what a frozen-surface page states plainly and a consumer reads as "at most N"; the byte ceiling is what keeps the promise true. |
| **A count plus a path to a side file** | The acceptance case is a PASS, and a PASS saves no exhibit, so this needs a new artefact and a new write path. Two files to open for a fact the report already holds. |
| **An entry per path carrying its form** (`standard` / `history`) | ADR 0078's decision is to report the **set**. The forms are already in `l0`'s prose as two counts with up to three names. A field added speculatively cannot be withdrawn without a ruling. |
| **Naming the set in the text report's `atomicity` line** | Ruled out by ADR 0078: the line caps names at three by design (ADR 0004) and reversing it does not reach `genisoimage`'s fourteen. |

## Consequences

- **The freeze audit's extraction cannot see either name, and the sweep this ADR points at is not
  prompted by it.** `spike/freeze-audit/surface-sets.sh` matches a schema field as
  ``^| `[a-z_]+` ``, which no name holding a digit satisfies — so `l0` and `l1` have been outside
  the extracted set since long before this change, and these two join them. Widening the pattern
  moves the extracted set away from the pin, and `check-freeze-audit.sh` says plainly that moving
  the pin is a sweep's job and not a change's. **Not filed as an issue**: `docs/freeze-audit.md`
  already carries the channel for exactly this — a "For the next sweep" note, as `setup_error_reason`
  has since #518 — and a second channel for the same message is a second place to forget. The note
  is added there, and `docs/contract-freeze.md` says the mechanism does not cover these names so
  the sentence about the sweep is not read as a guarantee.

- Surface 2 gains two optional fields under the additive allowance (#320). No closed set, so no
  ruling of the kind `setup_error_reason` and `recovery.result` needed.
- No row in `spike/freeze-audit/surface-changes.tsv`. Not because additive changes have no rows
  — `sc-06` is one — but because a row for a change made after the pin fails
  `check-freeze-audit.sh`; the row arrives when a sweep re-reads the surfaces and moves the pin.
- `spike/check-report-schema.py` holds both fields in both directions. They are emitted together
  on every classified run so neither can be documented and never generated.
- The set's own definition becomes testable at the classification boundary: the acceptance
  fixtures contain no post-only path, no pre-only path and no unjudged kind, so an
  implementation emitting "the post snapshot minus scratch" would pass all of them. A unit test
  beside `judge.zig`'s existing "L0 ignores files the operation legitimately creates or deletes"
  is what separates the two.
