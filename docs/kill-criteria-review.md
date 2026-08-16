# The kill criteria, reviewed

v1.0 entry criterion 3 (`PRD.md`) requires the kill criteria in DESIGN §18 to
be reviewed against collected data, with none triggered. This page is that
review: each condition quoted, the evidence named, the verdict recorded — the
counter-evidence beside the supporting kind, in the repository's own style.

Two framing notes before the rows:

- **§18's own gate never opened.** Its preamble triggers the analysis "if,
  after a defined dogfood period, Sideeye finds nothing beyond existing
  hand-written adversarial tests" — and the record says otherwise: a
  crash-window bug on a target with no hand-written adversarial tests at all
  (timewarrior#778) and a campaign counterexample set on topydo — those two
  alone contradict the antecedent. (The #84 sweep's fresh FAIL on
  bogofilter-sqlite is not counted here: row 4 records its triage as
  withdrawal-shaped.) The review below runs anyway,
  unconditionally, because criterion 3 asks for the review — not because the
  preamble fired. A reader should know the antecedent was checked, not skipped.
- **This is closer to one instrument read eight ways than eight independent
  measurements.** Rows 1, 4, 5, 6 and 8 draw on the same measurement family —
  the assisted cohort (#118, `spike/assisted/RESULTS.md`) and the UNKNOWN-rate
  sweep (#84, `docs/unknown-rate.md`) — and row 2's only number comes from the
  same cohort. Row 3 stands on the separate loop-closure measurement and row 7
  is an adjudication. Eight verdicts below do not mean eight independent
  confirmations.

What holds this page: acceptance check 11 verifies that every repository path
named here exists (path rot), and nothing more. The numbers are quotations
from their source pages — the UNKNOWN-rate figures are recomputed from the
committed artifacts by check 12 *at their source*, not here — and the
quotations themselves are held by review, the way check 11's own comment says.

## Row 1 — "It is only useful when humans define failure scenarios in bulk."

Two readings, both scored. First, the literal one: Sideeye's input is not
failure scenarios at all — it is invariants (DESIGN §2), and the crash-world
search supplies the scenarios. That is the design claim, though; the honest
question is whether findings only come from bulk *input* of any kind.

The evidence cuts both ways and both cuts are on the record. Bulk-shaped: the
topydo campaign declared thirteen operation forms and twelve produced
counterexamples — a wide net, and the fullest single-target result in the
repository. Not bulk-shaped: calcurse's find came from one declared operation
authored in under two minutes (`spike/assisted/RESULTS.md`), timewarrior's
from the two dogfood legs, and the #84 B-group ran exactly one operation per
target under a uniform minimal protocol — no bulk, no hand-tuning — and still
surfaced a counterexample on bogofilter-sqlite, one of seven explored (its
triage landed withdrawal-shaped, row 4 — what this row takes from it is the
single-operation reach, not the bug's validity).

**Verdict: not triggered.** Single-invariant, single-operation trials find
real bugs; breadth widens the net but is not the precondition.

## Row 2 — "Defining invariants costs about as much as writing ordinary failure tests."

What is measured: authoring time from window start to committed define —
T0 opens after install and a version check, and the pre-window contact is
itself recorded — was 1m25s–5m02s across all five assisted targets
(`spike/assisted/RESULTS.md`).
What that measurement is *not*: those are an LLM scout's times, under the
committed protocol, with the engine's define format already fixed. No
measurement exists of a human writing invariants for a target, and none of
the same author writing ordinary failure tests for the same target — the
comparison this row actually asserts has never been run on either side.

For this row, no data is neutral: the condition claims a measured equality,
and nothing measured supports it. The one cost datum that exists sits on the
minutes scale. What would settle it properly: one target, one author, timed
both ways — an invariant-plus-define against a conventional hand-written
crash test.

**Verdict: not triggered** (no supporting evidence; the comparison itself is
named as unmeasured).

## Row 3 — "Counterexamples are too complex to use for actual fixes."

This row has a direct, adversarial measurement: the loop-closure test. A
context-free coding agent was handed only the counterexample — the report
JSON, the case it names, the declared invariant — and the pinned timewarrior
checkout, and produced a fix that made the judge's own replay pass, feature
intact, audit clean (`spike/loop-closure-timew/`, BUILDLOG 2026-08-13). The
MCP-mediated variant repeated the result the same day, surfacing and fixing
two real adapter bugs on the way. v1.0 entry criterion 2 is met by exactly
this measurement, so this row and that criterion stand on the same artifact —
stated, not hidden.

Upstream consumption is thinner than the in-repo record, and stated
exactly: the one topydo filing (topydo#341, the recovery misfire) carried a
verified reproduction rewritten as plain printf calls — a rewrite made for
reporting etiquette, not because the counterexample needed translation —
and the crash-window destruction was deliberately not re-filed
(topydo#318, a third-party report from 2023, already covers that
phenomenon). In-repo, the committed timewarrior fix patch is rebuilt and
replayed against the counterexample by the `timew-regression` CI job on
every push (`spike/dogfood-timew-replay.sh`, #82) — the counterexample is
stable enough to serve as a standing regression assertion.

**Verdict: not triggered** — the counterexample alone was a sufficient input
for a fix, twice, with no human translation.

## Row 4 — "False positives or environment artifacts make it untrustworthy."

The unit matters, so both units are given. Per FAIL-producing target: six
A-group tools produced FAIL verdicts; one — buku — was withdrawn as a bug
claim (the sqlite journal recovers what the L0 byte judgment condemned;
`docs/target-classes.md` carries the class lesson). Per trial the committed
disposition map (`spike/unknown-rate/outcome-map.tsv`) reads fifteen
reported-upstream, one withdrawn, one kept-unreported of seventeen — but
twelve of the fifteen are topydo rows inheriting one campaign's disposition,
so the per-target count is the honest denominator: one withdrawal in six.

The withdrawn class then repeated, and was caught the same way: the #84
sweep's fresh FAIL on bogofilter-sqlite was triaged with the tool's own
reader as checker and recovery held in every explored world including the
three violating ones (`spike/followup-144/artifacts/checker.log`, one line
per world) — withdrawal-shaped, the same lesson on a second sqlite store. So
the repository's known false-positive class is exactly one: journaled stores
judged by file bytes under L0-only configuration, twice confirmed, twice
self-corrected before any upstream claim went wrong, and documented as a
class lesson with the checker recipe (`docs/checker-cookbook.md`).

One disposition is deliberately not in this row's numerator: devtodo is
kept-unreported on target-selection fairness (this project does not file
experiment-born reports against small, effectively dormant OSS) — a
reporting-policy withdrawal, not a finding-validity one; the counterexample
stands in-repo.

Environment artifacts: the sweep's refusals name their reasons —
watson's baseline_violates_invariant is the target's own nondeterministic
writer, the pass control's child_touched_state_dir is the engine refusing a
class it cannot observe. Refusals with named reasons are the UNKNOWN
discipline working, not artifacts minting verdicts.

**Verdict: not triggered** — one understood class, caught by the project's
own apparatus both times it appeared.

## Row 5 — "Reproducibility is too low for findings to serve as evidence."

Three independent re-executions of the same committed defines exist. The
REMEASURE run (`spike/assisted/REMEASURE.md`): one engine release after
authoring, three of the four blocked assisted defines — stow, devtodo,
buku — reached verified, replay-confirmed counterexamples; the fourth
(pass) stayed refused on the deliberately untouched exec gap, unchanged as
a control should be; and calcurse, the one define verified *before* the
gaps closed, re-measured to the identical FAIL. The v10 re-record then
returned identical verdicts and oracle agreement for all four again, each
replay reproducing in a fresh container. The #84 sweep: the same defines
re-run a further time in fresh containers reproduced the verdict pattern —
twelve topydo FAILs plus the ls PASS, and FAIL on buku, calcurse, devtodo
and stow (`docs/unknown-rate.md`, A-group table). And continuously: the
saved topydo cases replay inside the pinned image, and the timewarrior
record/FAIL/PASS legs re-run on every push to main and every pull request
(the `timew-regression` job, #82).

Reproducibility has a versioned edge, stated rather than hidden: a trace
contract bump invalidates saved cases loudly — they refuse as
case_no_longer_applies instead of replaying against the wrong contract —
and re-recording under the new contract returned the same verdicts
(`spike/assisted/REMEASURE.md`, the v10 re-record section). Findings
survive contract bumps; saved case files are versioned artifacts that must
be re-recorded, by design.

One instability is on the record and belongs here: the pass control's refusal
*reason* moved across engine releases — child_process_detected under v8,
child_touched_state_dir under v10. The verdict class (a refusal) is stable;
its name is contract-versioned. A reader comparing old and new transcripts
will see different strings for the same refusal.

**Verdict: not triggered.**

## Row 6 — "Setup is too heavy for ordinary software."

The #84 funnel, all stages, no stage summarized away: twenty targets
machine-selected → thirteen never reached an explore — two at W1 (the
package would not install in the pinned container: setup weight in the
strictest sense, counted against this row, not excused), nine at W2 (the
documentation names no local-file state — domain mismatch, not setup), two
at W3 (no non-interactive state-changing command) → seven explored → four
verdicts. The wall grounds are quoted per target in the committed NOTES
(`docs/unknown-rate.md`, funnel rules).

For a target inside the domain, the measured cost of arrival is small: the
uniform define is three small files, and authoring ran minutes per target
(row 2). The README-to-first-exploration budget is criterion 6's — separate
and not yet measured; this row does not borrow it. The heavy part of the
funnel was acquisition — finding targets whose state the domain covers — and
that cost is published as the funnel itself.

**Verdict: not triggered** — with W1's two-in-twenty install failures counted
against this row explicitly rather than absorbed into the walls.

## Row 7 — "No UX difference over existing specialized tools can be demonstrated."

This is the one row where absence of data is not neutral: the wording makes
failure-to-demonstrate itself the trigger, so it cannot be scored "no
evidence, therefore fine" the way rows 2 and 5 can. It is scored as an owner
adjudication, and the asymmetry is stated first.

What is measured, in this repository: onboarding on the minutes scale (row
2); define authoring and fix production both driven end-to-end by an agent
with no human translation (#118, `spike/loop-closure-timew/`); and the
refusal discipline — when the engine cannot judge, it returns a named reason
(the closed unknown_reason set of `docs/report-schema.md`) instead of a
silent pass. What is not measured: no head-to-head against an existing
crash-consistency tool has ever been run. The established tools in this
space drive file systems and kernel-level record/replay and assume that
arena; Sideeye's arena is ordinary file-backed CLI software with a
three-file define. A shared benchmark between the two arenas has not been
designed, and §16 says out loud that the everyday-developer-experience claim
is exactly what Sideeye exists to test — this page does not upgrade that
"unproven" into a comparative win.

**Adjudicated by the project owner, 2026-08-16: not triggered.** The measured
in-repo differences plus the structural arena difference are accepted as the
demonstration the row asks for, and the absence of a head-to-head is recorded
here rather than argued around. This is an adjudication, not a measurement; a
real head-to-head, if one is ever designed, supersedes it in either
direction.

## Row 8 — "UNKNOWN dominates."

The condition in full: "if a large share of runs on supported targets end
UNKNOWN, Sideeye cannot function as a gate, whatever its detection power."

Measured by #84 (`docs/unknown-rate.md`), owner-set threshold recorded with
the data: A-group 1 of 28 (3.6%); B-group 3 of 7 (42.9%) against a two-part
threshold — target-origin UNKNOWNs at most one of seven (measured zero) and
overall at most 50% — both parts holding, criterion 4 met.

The margins, out loud rather than in a footnote: the B-group margin is one
trial — a single additional UNKNOWN reads four of seven (57.1%) and fails
part 2. And the row's wording carries no platform qualifier, while the
measurement does: on the only platform with real-target runs (Linux aarch64,
in containers) UNKNOWN does not dominate; the macOS column is *derived* —
39.3% A-group, 85.7% B-group, because no oracle exists there and every
strict PASS derives to UNKNOWN. No macOS run exists, so the derivation is
not a trigger; it is this row's open flank, and a macOS-measured sweep would
have to face this row again on its own numbers.

**Verdict: not triggered** on the measured platform, with the one-trial
margin and the macOS flank both named.

## Calibration

§18's calibration demand — at least one deliberately average target, because
judging Sideeye on omamori alone conflates "the tool is weak" with "the
target is hardened" — is discharged on both branches. The average target,
timewarrior (no hand-written adversarial tests), yielded a real
crash-consistency bug. The hardened half was re-measured under contract v10
on 2026-08-16 (#141): all four unguarded omamori writers explore fully and
hold, the v8-era walls gone exactly as predicted, with the reports committed
(`spike/followup-141/artifacts/`) and the surface pinned against silent
movement (`spike/dogfood-omamori-surface.sh`). DESIGN §18's calibration
paragraph carries the full result; this page only needs its conclusion:
zero-findings-on-omamori landed on the survivable side, with the mechanism
named.

## The verdict

All eight rows reviewed against the collected data: **none triggered.** Rows
1, 3–6 and 8 are scored on committed measurements with the counter-evidence
and margins stated; row 2 is scored on the recorded absence of the very
comparison it asserts; row 7 is an owner adjudication whose no-data
asymmetry and missing head-to-head are disclosed above. This review is what v1.0 entry
criterion 3 asks for, and the criterion is checked on it.

None of the rows closes permanently. A future measurement landing on a
row's trigger side — a sweep where target-origin UNKNOWNs dominate, a
false-positive class that isn't caught in-repo, a head-to-head that shows no
difference — reopens this page, and per the PRD's own rule the analysis
ships instead of the release.
