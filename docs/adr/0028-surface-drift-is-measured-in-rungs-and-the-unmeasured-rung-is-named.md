# 0028 — Surface drift is measured in rungs, and the unmeasured rung is named

Status: Accepted (implementing PR merged with the 2026-08-27 re-sweep, which is the
first sweep to measure the five surfaces rather than read them)

## Context

`docs/freeze-audit.md` decides, for every open issue, whether resolving it would
touch one of the five surfaces frozen at v1.0. For three sweeps that decision was a
**reading of the issue**: someone opened the body and judged it against
`docs/contract-freeze.md`.

The 2026-08-27 sweep measured that method against the window it was auditing and
found it cannot answer the question.

**`#324` is the counterexample**, and its body is committed as evidence in
`spike/freeze-audit/capture-2026-08-27-issue-324-body.json` — the sweep's raw
capture deliberately excludes bodies, so a negative claim about one has to carry
its own source. Measured there, on both the raw text and a whitespace-normalised
copy (a phrase wrapping across a line break is invisible to a line-oriented
search, a mistake made twice during this sweep in both directions): the body
contains `unknown_reason` zero times, "closed set" zero times, and
`trace_too_large` zero times. Its resolution added `trace_too_large` to the
`unknown_reason` closed set — the one part of surface 2
that the additive allowance explicitly does not cover, so the one part where a
post-tag addition is a breaking change under any reading. What moved the surface
was the **resolution**, not the issue text. No reading of `#324`, however careful,
returns anything but `none`.

Measuring instead found **five** closed-set additions in the window, one new report
field, and two trace-contract bumps. A peer session working the same window had
accounted for three of the five from its own work; two had been counted by nobody.
The audit's own table, at that moment, recorded zero movements on any surface.

A second finding made the reading unreliable in a different direction: the
**declaration itself moved three times inside the window**. Surface 2 gained the
additive allowance and the closed-set exemption on 2026-08-26 (`0e035eb`) — eight
days into a window that opened on 2026-08-18, so most of the sweep's readings lean
on a rule newer than the snapshot they classify. Surface 3 was rewritten
(`9f04932`). Surface 4's previous text was measured against the code and found
**wrong** (`975e2fd`). Nothing recorded which revision of the declaration any sweep
had read.

The first attempt at a measurement then overclaimed, and an adversarial review
rejected it. It diffed narrow syntactic proxies — key names, enum members, a
version constant, tool names — and called that "diffing the five surfaces". The
refutation is in the same window: **`#273` moved the exit-code surface while the
`ExitCode` enum stayed byte-identical**, because what changed was which path
returns which code. One stated figure ("toml keys 15 → 15") was not reproducible at
all: the accepted key set is the six names surface 1 lists, and the extractor had
been counting quoted strings.

## Decision

**Surface drift is measured, and the measurement reports in three rungs that are
kept separate because they support different claims.**

1. **Blob identity.** If *every* file a surface is defined by is byte-identical
   across the window, the surface did not move — enumerated names *and*
   behavioural clauses, because the behaviour lives in those files too. This is
   the only rung that can settle a surface outright, and on this window it
   settles none of the five. The first draft claimed it settled surface 1 on
   `src/config.zig` alone; review measured that the clauses that claim named —
   the split-on-spaces rule, the argv form's verbatim passing, relative-path
   resolution — are in `src/main.zig`, which changed. The lesson is the rung's
   own precondition: identity of *a* defining file is not identity of the surface.
2. **The enumerated diff**, for files that did change, with each extraction defined
   in the script rather than described in prose. It answers "which names appeared
   or disappeared" and claims nothing else.
3. **The named residue**, printed as unmeasured on every run and stated on the
   page: field presence rules and meanings, which call site returns which exit
   code, the two MCP input schemas, the `isError` derivation rule, and the shape of
   an old case's refusal. These are held by review and by `spike/acceptance.sh`.

   **Amended 2026-08-30 (#369): per clause, not per surface.** The paragraph above
   named five paragraphs' worth of residue and left the reader unable to tell, for
   any one clause, whether a check watched it or nobody did — "held by review and by
   `spike/acceptance.sh`" is true of the set and says nothing about a member.
   `spike/freeze-audit/clause-checks.tsv` now answers that per clause, and this rung
   prints only what is unpinned plus the leftover half of what is pinned in part.
   Three consequences follow. The output shrinks as checks are written rather than
   staying a fixed five paragraphs. `held` has three values, because two would
   force every partially covered clause to read as covered — the misreading that
   prompted #369. And **this rung retires itself**: when the file holds no unpinned
   and no partial row, the run says so and the ladder collapses to two rungs.
   What stays unmeasured is whether the enumeration is complete; a clause is one
   independently checkable assertion, which matches no boundary in the declaration,
   so no check can find a row that was never written. The output says that too.

**Two revisions are pinned beside the snapshot, and they fail differently.** The
declaration's revision is pinned and the gate **fails** (exit 1) if it has moved: a
reading taken against another revision is a reading of another promise, so the
sweep is invalid rather than stale. The measured `src/contract.zig` revision is
pinned too, and a later movement of the closed set is **drift** (exit 3), not a
failure: the sweep was correct when taken and is now out of date. The first version
of that leg compared the window's base against `HEAD` and so would have exited 1
the moment the next member landed, reporting a stale audit as a broken one.

> **Superseded in part, 2026-08-30 (#371):** the paragraph above no longer describes
> the gate. The two pins no longer fail differently — a moved declaration is
> **staleness**, reported at the end beside drift, and both exit 3. "Invalid rather
> than stale" was the reading that made it exit 1, and exiting there stopped every
> leg behind it: `main` carried an unrecorded frozen-surface movement (`config_keys`
> gained `cwd`, #395) from 2026-08-29 with nothing reporting it, because the leg that
> would have was never reached. The message that came with exit 1 also told whoever
> saw the red to move the pin, which only a sweep can honestly do. What survives here
> unchanged is the reasoning in "Three costs" below: the declaration pin is a
> maintenance obligation, and discharging it is a sweep's job. Exit 3 is still red.

This is also the only mechanism in the audit that can see a frozen surface move
**without any issue changing state**. `--live` asks the tracker about issues, so it
is blind to that by construction, and the page had described the gap rather than
closing it.

**Attribution is a human judgement recorded per change, not a parse.** `git log -G`
answers "which commits contain a matching diff", never "which issue required this
line". The commit-subject convention carries issue and PR numbers unevenly (of the nine commits this sweep
attributes changes to, three have no trailing parenthetical, and among the rest it
is sometimes the PR and sometimes the issue — `7ed5c97` ends with an issue number,
`8b75ad7` with an issue and then a PR), so parsing it is not a
rule. Changes live one per row in `spike/freeze-audit/surface-changes.tsv` with the
commit, the causing issue or issues, the legality and the evidence; one change in
this window names no causing issue, because attributing it to the issue that rode
the same commit would be association rather than cause.

**Three rules the drift script follows because its own instruments lied while it was
being written, every one of them in the direction of "everything changed":**

- Brace the revision. `"$REV:path"` under zsh drops the path — `:s` is a history
  modifier — and `git show` then prints the commit's *diff*, in which every line of
  the file carries a `+`. The first closed-set measurement read "29 members added"
  that way; five had been added.
- Assert the base extraction is non-empty before reporting any difference. A diff
  against an empty set is indistinguishable from a total rewrite, and this is the
  check that catches the previous failure on its own.
- Use `-G`, not `-S`, for a value edit. `-S` counts occurrences, so changing a
  constant's value on a line whose text is otherwise unchanged is invisible:
  `git log -S 'contract_version: u32'` returned zero commits for a window in which
  that constant moved twice.

## Alternatives Considered

**Keep reading the issues, more carefully.** Rejected on the measurement: `#324`'s
information is not in its body. This is not a precision problem that care fixes.

**Call the enumerated diff a measurement of the five surfaces.** Rejected by review
and then by the window itself (`#273`). The cost of the overclaim is worse than the
gap it hides, because a page that says "no surface moved" when one did is the exact
failure this audit exists to prevent.

**Map every clause of the declaration to the acceptance check that pins it, in this
sweep.** The honest complete answer, and out of scope here: it is a piece of work
per clause, and doing it inside the sweep would put a new check inside the change it
polices. Filed instead, with rung 3 naming the clauses so the gap is visible where
it matters. One instance is already recorded on the page: the acceptance leg for a
case recorded under an old contract asserts an exit code and a message string, and
does not assert the refusal's `unknown_reason` value or the absence of a verdict —
though its own success message says "never a verdict".

**Record surface movements in `audit.tsv` alongside the issue rows.** Rejected: a
change is (surface, item, kind, before, after, commit, issues, legality), issues and
changes are many-to-many, and the disposition column is already a class-dependent
enum the gate checks. The first draft folded legality into that column and lost four
of the window's five closed-set additions.

## Consequences

The audit can now state, and a reader can recompute, which frozen surfaces moved in
a window and which did not — and exactly which parts of that question it did not
answer. Sixteen active rows in this sweep carry a surface forecast other than
`none`, against zero on the previous sweep's thirteen; that is a larger population
read against the same declaration, not a change of standard.

The gate gains a leg that would have caught the original defect: the measured
closed-set additions must be exactly what the change ledger records.

Three costs, stated:

- **A forecast cannot be checked.** An active row says what resolving the issue as
  filed *would* move. Only the next sweep's measurement can confirm or correct it.
- **The residue is real and stays.** Behavioural clauses are read. The page says so
  in the same place it reports the measurement, which is the only honest
  arrangement while the clause-to-check map does not exist.
- **The declaration pin is a maintenance obligation.** Any change to
  `docs/contract-freeze.md` now turns the gate red until a sweep re-reads the
  surfaces and updates the pin in the same commit. That is the intended cost: it is
  what makes "which yardstick did you use" answerable.

Sunset: delete rung 3's list, and this ADR's third rule, when every clause of the
declaration has a named check pinning it. At that point the residue is empty and the
ladder collapses into two rungs.
