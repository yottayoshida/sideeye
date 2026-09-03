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
  confirmations. *(Re-checked 2026-08-26, and on the instrument the note
  holds more firmly rather than less. The three selection cohorts that
  arrived after this page was written are not the independent instrument they
  look like: cohort 3 states that
  "the probe gate of cohort 2 applies … with one substitution", and cohort 4
  applies cohort 2's seven conditions "with their predicates **sourced in
  place** (`spike/cohort2/probes/lib.sh`; no fork, no copy: the cohort-2
  drills and this cohort's runs exercise the same lines)". They share engine,
  observer, probe-gate predicates and the same owner and scout, so **they are
  not three independent apparatuses**: a systematic error in the shared gate or
  the engine would appear in all three alike. That is what the quotations
  settle and the limit of it — twelve distinct targets, their own checkers and
  their own explored verdicts are new information about the world whatever
  instrument read them, and nothing here says otherwise. #240 expected this
  note to weaken with the cohorts added; on the instrument axis it does the
  opposite. Which rows their measurements reach is the re-review section
  below.)*

What holds this page: acceptance check 11 verifies that every repository path
named here exists (path rot), and `spike/check-criterion3-status.sh` holds the
criterion-3 state markers below (next paragraph); nothing else does. The
numbers are quotations from their source pages — the UNKNOWN-rate figures are
recomputed from the committed artifacts by check 12 *at their source*, not
here — and the quotations themselves are held by review, the way check 11's
own comment says (`docs/adr/0039-quoted-figures-are-held-by-review.md`
records why that stays the rule, and what would reopen it).

`PRD.md` carries the one current status of criterion 3; this page carries the
dated state markers it cites — appended after the last, so file order is the
timeline — and `DESIGN.md` §18 the definition.
`spike/check-criterion3-status.sh` holds the three to that split: PRD's
current-status marker must equal this page's last state marker, every H2
section after `## The verdict` whose heading carries a `(YYYY-MM-DD` date
carries exactly one state marker, and neither this page nor §18 may carry a
current-status marker of its own. The page's whole marker sequence is pinned
inside that script, so **recording a new state touches three files in one
pull request**: the marker here, PRD's current marker, and the pin. The
markers are HTML comments, invisible when rendered; the prose beside them is
held by review, the same way the figures are. The check retires if PRD's
marker is ever generated from this page, or if this page stops carrying dated
state markers (#356).

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

**The A-group figure quoted above is g1's and is now one generation old**
(2026-08-26, #239). The A-group was re-swept as generation g2 over a corpus
of 36 trials and measured **2/36 (5.6%)**; both figures stay published with
their dates. The B-group is unchanged — g2 does not cover it — so the
threshold this row is scored against has not moved. **This row is not
re-scored here.** Re-scoring a met criterion inside a measurement change is
the move #240 exists to do deliberately, with every row's previous verdict
quoted beside its new one; this note records that the quotation aged, and
nothing more.

The margins, out loud rather than in a footnote: the B-group margin is one
trial — a single additional UNKNOWN reads four of seven (57.1%) and fails
part 2. And the row's wording carries no platform qualifier, while the
measurement does: on the only platform with real-target runs (Linux aarch64,
in containers) UNKNOWN does not dominate; the macOS column is *derived* —
**39.3% A-group as derived from g1** (36.1% from g2, which this row is not
scored against; see the generation note above), 85.7% B-group, because no
oracle exists there and every strict PASS derives to UNKNOWN. No macOS run exists, so the derivation is
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
<!-- criterion-3-state: 2026-08-16 met -->

None of the rows closes permanently. A future measurement landing on a
row's trigger side — a sweep where target-origin UNKNOWNs dominate, a
false-positive class that isn't caught in-repo, a head-to-head that shows no
difference — reopens this page, and per the PRD's own rule the analysis
ships instead of the release.

## Re-review (2026-08-26) — three selection cohorts

**Current state of v1.0 entry criterion 3: reopened, re-score pending owner
adjudication.** Everything above this line — the eight rows, the calibration
note and the closing verdict of "none triggered" — is the review of
2026-08-16 and is left exactly as it was written, including its date. This
section sits after it rather than inside it, so that the historical
conclusion stays legible as a conclusion and this one does not overwrite it.
What follows is what has been measured since, row by row, and which rows it
lands on. *(Superseded 2026-08-27 — both rows were adjudicated in the section
at the end of this page: neither is triggered and criterion 3 stays met. This
paragraph and everything under it are the state as it stood on 2026-08-26,
left as written.)*
<!-- criterion-3-state: 2026-08-26 reopened -->

What has been measured since: **twelve targets across three selection
cohorts** (#183 2026-08-21, #209 2026-08-22, cohort 4 2026-08-23), each
under a freeze published before it ran, producing **thirteen outcomes** —
five walls that stood (KeePassXC, Jujutsu, Bun, cargo, unison), one wall
lifted by declared apparatus and turned into a verdict (Borg, #200), and
**seven verdicts**. Borg appears twice because it produced both, which is
why `spike/cohort2/RESULTS.md` records "five targets, six recorded
outcomes" for that cohort rather than a single number. Records:
`spike/cohort2/RESULTS.md`, `spike/cohort3/RESULTS.md`,
`spike/cohort4/himalaya-r2/RESULTS.md`.

**Two of the eight rows carry evidence on their trigger side** — rows 4
and 6. Per the closing rule stated above, that reopens this page, and per
the PRD's own rule the consequence for the release is the owner's. **This
section does not re-score anything**; what the two rows gained is material,
stated as location and counter-evidence separately, below the table.

| Row | New evidence from the cohorts | Trigger-side? | Verdict (2026-08-16) | Re-review |
|---|---|---|---|---|
| 1 — bulk failure scenarios | Seven verdicts, each from a define carrying **exactly one** operation file — `spike/cohort2/hg-r4/ops`, `spike/cohort3/black/ops`, `spike/cohort4/himalaya-r2/ops` and the rest, one `.toml` apiece — against the thirteen the corpus's own topydo define carries (`spike/blind-hunt/declaration/topydo/ops`). No cohort target was given a scenario set | no | `not triggered.` Single-invariant, single-operation trials find real bugs; breadth widens the net but is not the precondition | Corroborated, unchanged — seven further single-invariant verdicts |
| 2 — invariant cost vs ordinary failure tests | Authoring cost is now visible per target — black, rustfmt, papis and poetry all reached verdicts from their first frozen define (poetry's second define exists as a sealed manifest-only shape under the FAIL-freeze ruling, not to reach a verdict it already had: `spike/cohort3/poetry-r2/RUNLOG.md`), while Mercurial's took four revisions (`spike/cohort2/RESULTS.md`, `spike/cohort3/poetry/RUNLOG.md`) — but no cohort ran the comparison this condition names | no — the comparison is still unmeasured, as the row already records | `not triggered` (no supporting evidence; the comparison itself is named as unmeasured) | Unchanged; the cohorts add authoring data and do not close the gap the row names |
| 3 — counterexample complexity | black's earliest violating world is the empty file between the truncating `open` and the single `write`; upstream fixed and closed himalaya from the filed report the same day (pimalaya/io-maildir@b4e9080, released as 0.3.1) (`spike/cohort3/RESULTS.md`, `spike/cohort4/himalaya-r2/RESULTS.md`) | no | `not triggered` — the counterexample alone was a sufficient input for a fix, twice, with no human translation | Corroborated — a third counterexample-to-fix, this one produced by upstream from the report rather than in-repo |
| 4 — false positives / environment artifacts | Borg: FAIL 3/119, every violation L0-only, **all three in the relocated client cache's in-place rewrite** — "the client cache the apparatus itself relocated", moved inside the judged root by the define's r2 so worlds could run at all; Borg's documented transactional contract held in all 119 worlds (`spike/cohort2/RESULTS.md`, `spike/cohort2/borg-r3/RUNLOG.md`) | **yes** — the violating worlds sit inside a directory the measurement apparatus relocated, which is this row's subject; located below | `not triggered` — one understood class, caught by the project's own apparatus both times it appeared | **Reopened — re-score pending (owner adjudication)** |
| 5 — reproducibility | **All seven** verdicts record an identical re-execution, each in its own ruling: Mercurial and Borg (`spike/cohort2/hg-r4/RUNLOG.md`, `spike/cohort2/borg-r3/RUNLOG.md`), black, rustfmt, poetry and papis (`spike/cohort3/black/RUNLOG.md` and its siblings — poetry across three explores with identical verdicts), and himalaya (`spike/cohort4/himalaya-r2/RESULTS.md`) | no | `not triggered.` | Corroborated on seven further targets, with nothing withheld: the first draft of this row claimed a gap at Mercurial, which came from scanning the cohort RESULTS pages and not the per-target rulings |
| 6 — setup weight | Mercurial's define took four revisions to reach a verdict (r1 SETUP ERROR at state resolution, r2 sendfile, r3 utimensat, r4); Borg's wall fell only to a three-piece declared apparatus plus three define revisions. Against this, cohort 3's black and rustfmt each reached a reproduced verdict in minutes from their first frozen define, both passing their probes first time; papis is on neither side (below) (`spike/cohort2/RESULTS.md`, `spike/cohort3/RESULTS.md`) | **yes** — arrival cost on two in-domain targets was four define revisions and a three-piece apparatus, against this row's basis of three small files and minutes per target; located below | `not triggered` — with W1's two-in-twenty install failures counted against this row explicitly rather than absorbed into the walls | **Reopened — re-score pending (owner adjudication)** |
| 7 — UX difference | None bearing on the condition. No head-to-head against an existing crash-consistency tool was run in any cohort; the absence the 2026-08-16 adjudication disclosed persists across twelve further targets | no new data either way; an absence continuing is not a new measurement | `Adjudicated by the project owner, 2026-08-16: not triggered.` | Unchanged; the missing head-to-head is still missing, and is still disclosed rather than argued around |
| 8 — UNKNOWN dominates | The cohort verdict targets **are** the eight defines that entered the A-group at generation g2 (hg, borg, black, papis, poetry twice, rustfmt, himalaya): the A-group rate reads **2/36 (5.6%)** against g1's **1/28 (3.6%)**, the added refusal being himalaya's `oracle_saw_phantom`. The walls did not enter the denominator — jj, Bun and cargo are class-excluded, KeePassXC and unison produced no committed define. B-group is unchanged at 3/7 (`docs/unknown-rate.md`, `spike/unknown-rate/class-exclusions.tsv`) | no — the threshold is evaluated on B-group data alone and g2 covered A only, so neither part moved; and a wall is not a run, which is what this row's wording counts | `not triggered` on the measured platform, with the one-trial margin and the macOS flank both named | The figure is already in the row's own g2 note (#239); what this adds is where those eight defines came from. Verdict unchanged, and the one-trial margin on B stands untouched |

**One inherited expectation, settled here rather than left dangling.** Row 8's
own g2 note (added by #239) says that re-scoring a met criterion inside a
measurement change "is the move #240 exists to do deliberately, with every
row's previous verdict quoted beside its new one". This section quotes every
previous verdict as that note anticipated, and stops there: the re-score
itself is raised as pending because two rows turn out to carry trigger-side
evidence, and adjudicating those inside a documentation change is the move the
note was guarding against in the first place.

One observation from row 8 that belongs on the record without being scored
here: the A-group's two refusals split as one target-origin (watson's own
nondeterministic writer) and one **apparatus collision** — himalaya's
declared `no-accel-copy.so` answering the copy primitives the shim
interposes as of #244. The threshold's origin classification has two
categories, target-origin and define-budget, and an apparatus superseded
by the engine is neither. The threshold is unaffected (it is set from
B-group data only), and this is noted as a gap in the classification's
coverage rather than as a movement in this row.

### Row 4's trigger-side evidence, located

**Location.** Borg's verdict is FAIL in 3 of 119 explored worlds, every
violation L0-only, and `spike/cohort2/borg-r3/RUNLOG.md` records where all
three are: `ambient/.cache/borg/<repo-id>/chunks`, the client cache's
in-place rewrite caught mid-write. The cache is inside the judged root
because the define's second revision put it there — at r1 it lived outside
the state root, so every world met a cache newer than its rolled-back
repository and refused before the kill could land on any operation. The
measurement could not run until the cache moved, and the violations are in
the thing that moved. The ruling's own words are "the client cache the
apparatus itself relocated" and "the multi-write shape, #35's class,
tinted further by our own apparatus".

**Counter-evidence, from the same record.** Three items, all in the ruling
rather than added afterwards. Borg's documented transactional contract
held in all 119 worlds — stale-lock removal exactly when a lock existed
(14 worlds, all succeeded), `borg check`, byte-identical conservation of
the pre-existing `base` archive, old-or-new listing, new-side content; the
checker ran everywhere and failed nowhere. The file the violations sit in
is not repository state and is explicitly rebuildable: deletion is Borg's
own documented handling, and the checker's leg R0 exercises exactly that
in every world. And nothing was claimed — no criterion-1 candidate,
recorded as a precision-limit observation under the claim rule frozen
before any cohort explore ran, with the apparatus notes requiring any
finding to reproduce against stock borg under strace fault injection
before it could be reported. None was.

What separates this from the row's existing "one understood class" is the
source. buku and bogofilter-sqlite were the *target's* journal contract
being judged by file bytes. Here the judged bytes are in a directory the
apparatus moved to make the measurement possible at all. Whether that is
the same class, a second class, or an artifact tinting a verdict — the
distinction the row draws when it says refusals with named reasons are the
UNKNOWN discipline working, "not artifacts minting verdicts" — is the
adjudication this section leaves open.

### Row 6's trigger-side evidence, located

**Location.** This row's supporting basis is that for a target inside the
domain the measured cost of arrival is small — "the uniform define is
three small files, and authoring ran minutes per target". Two cohort-2
targets measured otherwise. Mercurial's define took four revisions to
reach a verdict, each refusal committed as evidence: r1 a SETUP ERROR at
state resolution, r2 a `sendfile` refusal worked around by a declared
`sitecustomize`, r3 a `utimensat` refusal that ripened #190, then r4.
Borg's wall did not fall to a define at all — it fell to a three-piece
declared apparatus (libfaketime realtime-x0 plus sitecustomize pins on
`time.monotonic` and `os.urandom`), and the define then took three
revisions on top of that.

**Counter-evidence.** Cohort 3's black and rustfmt each reached a
reproduced verdict from their first frozen define, in minutes — the record
says so for both in those words — and both passed their probes on the first
attempt. That is this row's basis holding as written, on two targets of a
later cohort.

papis is deliberately not offered as a third, though counting define
revisions alone would put it there. Its define is a single revision, but its
*plan* was amended after target contact and before its accepted probe: the
original `--set` form made a purely local `papis add` depend on the network,
because papis 0.16's arxiv importer treats the local path as a candidate
identifier and validates it over HTTPS, so the plan was rewritten to carry
the same metadata through a frozen YAML fixture and `--from yaml`
(`spike/cohort3/RESULTS.md`, "The papis amendment"). No minutes figure is
recorded for it either. Which unit this row is scored in — define revisions,
or arrival cost as the records describe it — is part of what is being left
open, and papis is the target that makes the two units disagree. The two heavy targets are also the two
whose walls this project chose to attack deliberately (#200 reopened
Borg's determinism wall as its own decision), so the arrival cost is
partly a consequence of target selection rather than a property of
ordinary software.

The open question the row's wording turns on is whether declared apparatus
counts as setup. Apparatus is the instrument's cost, not the target's; the
row is about the target's. Both readings are available on the same
measurement, and choosing between them moves a v1.0 entry criterion, which
is why it is not chosen here.

### What this section does not do

- **No verdict above is changed**, and no wording in rows 1–8 is edited.
- **`PRD.md`'s criterion-3 status is not rewritten.** Its "met
  (2026-08-16)" stands as the dated statement it was; a dated reopen note
  is appended beside it.
- **The re-score is pending owner adjudication**, recorded here, in
  `PRD.md` and in `DESIGN.md` §18 — the three places that carry the reopen
  rule — so that no one of them can read as settled while another reads as
  open.
- **#240 stays open.** It asked for a re-scored review; what this delivers
  is the material for one.

## Adjudication (2026-08-27)

*Noted 2026-09-03 (ADR 0043, #261): a define can now declare its scratch paths (`[define] scratch`), so the class row 4's case was filed under, "tools with non-durable scratch files", no longer decides a verdict on its own. Nothing below is re-scored: the ruling's basis — the checker carries the target's real integrity claim, and held — is what scratch leaves untouched, because the key adds no knowledge, only a verdict that is not decided by files nobody depends on.*

The two rows the section above put on a trigger side were adjudicated by the
project owner on 2026-08-27, under #240. **Neither is triggered, and v1.0
entry criterion 3 stays met.** **No dated text above this line is overwritten.** The 2026-08-16 review, its
closing verdict, and the 2026-08-26 re-review with its `pending` cells are all
left as the dated records they are; the one edit above is a superseded note
appended to the 2026-08-26 section's opening paragraph, which adds a pointer
and removes nothing. This section is what supersedes them.
<!-- criterion-3-state: 2026-08-27 met -->

Both rulings are recorded the way the criterion-1 adjudication of #305 was —
the reading taken, the readings rejected and why, and what the chosen reading
gives up. Row 6's ruling is a definition that binds future cohorts, so its
normative wording lives in `DESIGN.md` §18, where criterion 3's conditions
are defined; this page carries the reasoning.

### Row 4 — the reading taken

**Borg's case is a second example of a class this repository already carries,
not a new one, and the row is not triggered.** The class is "tools with
non-durable scratch files" (`docs/target-classes.md`), recorded from git's
`COMMIT_EDITMSG` as precision limit #35, with the recipe already written:
"A scratch file is not a counterexample — and only a checker knows which is
which" (`docs/checker-cookbook.md`). Borg's own ruling had already classified
it that way — "the multi-write shape, #35's class, tinted further by our own
apparatus" — which the re-review above did not notice.

What Borg adds to the class is one property it did not have before: **the
scratch path is one the target creates, relocated into the judged root by the
measurement setup.** Borg still chooses and creates
`ambient/.cache/borg/<repo-id>/chunks`; what the define's r2 changed is where
`BORG_BASE_DIR` points, which brought that path inside the state root the
engine rolls back. The class now records that a scratch file can enter the
judged set that way, and not only by sitting there from the start.

Three things carry the not-triggered reading, and the order matters because
only the third is about this project's discipline:

1. **The violating file is outside the durable repository state Borg's
   transactional claim covers.** It is a client cache, not repository state,
   and deletion is Borg's own documented handling for it — the cache is not
   uncovered by every Borg contract, it is uncovered by the one the verdict
   was judged against. That is a property of the product under test, not of
   how it was measured.
2. **A checker carrying that transactional claim ran in all 119 worlds and
   held in all of them** — stale-lock removal exactly when a lock existed (14
   worlds, all succeeded), `borg check`, byte-identical conservation of the
   pre-existing `base` archive, old-or-new listing, new-side content. What
   covers this case is a check, not a judgement made afterwards.
3. **The claim rule then kept it out of the numerator** — recorded as a
   precision-limit observation, no criterion-1 candidate, nothing reported.

**What support 2 does not include, said here rather than left to a reader.**
The checker also attempts the documented deletion-and-rebuild before its legs
(`spike/cohort2/borg-r3/ops/check.sh`), and an earlier draft of this section
offered that as the support. It does not carry the weight: the `rm -rf` is
unchecked, and the committed drill transcript records it failing on
permissions in a scratch run while execution continued
(`spike/cohort2/borg-r3/checker-drills.txt`). The transcript proves the
checker ran 119 times and that its legs held; it does not prove that leg's
deletion succeeded each time. The support above is therefore the contract
legs, which the transcript does measure.

**Rejected: that this is the same class as buku and bogofilter-sqlite.** That
class is a journaled store whose mid-transaction bytes its own journal
recovers — the strictness comes from judging the *target's* contract by file
bytes. Here the bytes are in a path the apparatus placed inside the judged
root. Same remedy, different cause, and folding them together would lose the
apparatus property that is the only new thing in the record.

**Rejected: that the row is triggered.** The row asks whether false positives
or environment artifacts make the tool untrustworthy. An artifact did reach a
verdict, and that is why this row was reopened at all — but the verdict was
covered by a checker leg, disclosed by its own ruling, and never turned into
a claim. Untrustworthy is what happens when an artifact reaches a *claim*.

**What this reading gives up.** It accepts that a FAIL verdict can carry a
world tinted by the measurement setup without the row moving, provided a
checker carrying the target's own integrity claim ran and held. Two things it
does not buy. It does not establish that the relocated file's documented
recovery was exercised successfully — that leg is unchecked, as above — so a
future case whose only defence is "the target documents a recovery" is not
covered by this reading. And if a relocated path is ever judged by the
built-in form with no checker carrying the target's claim at all, the row
reopens.

### Row 6 — the reading taken

**Declared apparatus is the instrument's cost, not the target's setup, and
the row is not triggered.** The condition asks whether setup is too heavy for
ordinary software; clock pins, entropy pins and userspace answers to kernel
copy primitives are what the measurement needs in order to observe anything,
not what a user must do to their software. The binding definition, including
what it excludes, is in `DESIGN.md` §18.

**Rejected: that declared apparatus counts as setup.** Counting it turns the
condition into a measure of this tool's instrumentation cost, which is a real
thing worth measuring and is not what §18's condition says. Note which sense of
the word is being excluded: Borg's cache relocation, which the row-4 ruling above
calls "the apparatus itself relocated" after the record's own phrasing, was the
define's r2 rather than a protocol declaration — so it is **not** declared
apparatus under §18's definition and is **not** excluded by this ruling. It is a
define revision, and the next rejection is what disposes of it. The definition in
DESIGN is deliberately narrow so that the exclusion cannot be widened later:
apparatus must be declared in the public protocol before the define ran and
must constrain the environment, and anything touching the target's own
installation, configuration or state is setup.

**Rejected: that define-revision cost belongs to this row.** Excluding
apparatus still leaves it — Mercurial's define took four revisions to reach a
verdict, Borg's three on top of the apparatus — so the question does not
disappear with the first ruling and is answered on its own: **the owner
excludes it from this row.** Row 6 is the cost of getting ordinary software
into a state where it can be measured at all, and its own funnel evidence is
installation walls.

**Where that cost does belong is left open, because the record does not
support the obvious answer.** It is tempting to send it to row 2, the cost of
declaring invariants, and an earlier draft of this section did. Borg's own
record refuses that: r2 changed where the client state sits and what leg R0
does, r3 added the `sendfile` workaround, and `spike/cohort2/borg-r3/proposals.md`
says in as many words that the question bytes were unchanged. These are
measurement and define-packaging costs, not invariant-authoring costs, so
they are not evidence for row 2's comparison either. They are excluded from
row 6 by adjudication and recorded here as unallocated, which is the honest
state rather than a tidy one.

**What this row's basis actually measured, since the re-review above cites
it.** The sentence "the uniform define is three small files, and authoring
ran minutes per target" places two measurements side by side, from two
populations: the three-file shape is the #84 B-group's uniform define (its
operation file is spelled `op.txt` in some targets and `op.sh` in others),
and the minutes are the assisted cohort's 1m25s–5m02s across five targets,
which row 2 cites as its source. The cohort arrival costs belong to neither
population — they are define revisions, which the ruling above excludes from
this row and leaves unallocated.

**What this reading gives up.** From the outside, a user who must set up
libfaketime and two interpreter pins before getting a verdict has done work,
whatever it is called. This reading says that work is the instrument's and
does not score against the target's setup weight — so if the apparatus burden
ever becomes the reason a target cannot be reached at all, that is a fact
about this tool which this row will not record. #257 tracks promoting a
declared-apparatus bundle so the burden is paid once rather than per target.

### Where this leaves criterion 3

**All eight rows: none triggered.** The 2026-08-16 review stands as written,
the 2026-08-26 re-review stands as the record of what three cohorts added and
which rows it reached, and this section records the two rulings that closed
what the re-review opened. `PRD.md` carries the criterion's status line and
`DESIGN.md` §18 carries the definition row 6's ruling establishes.

The closing rule is unchanged and still applies: none of the rows closes
permanently, and a future measurement landing on a row's trigger side reopens
this page again.
