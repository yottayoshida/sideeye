# The contract-freeze audit — v1.0 criterion 5

PRD criterion 5 freezes four surfaces at v1.0 — config format, report schema,
exit codes, replay compatibility — and issue #86 added a fifth by decision
(the MCP surface) and defined this audit: every open issue that touches a
frozen surface gets resolved *before* the freeze, because after it, a fix as
filed is a broken promise. "Defer and freeze anyway" is the one outcome this
page exists to prevent.

**Snapshot.** The classification below covers the open-issue set captured at
the **fourth sweep, 2026-08-29** — fifty-six issues, committed verbatim as
`spike/freeze-audit/snapshot-2026-08-29.tsv`, replacing the 2026-08-27
snapshot of fifty-five (which replaced the 2026-08-18 snapshot of thirteen,
which replaced the original sweep's twenty-six of 2026-08-17). The gate's
`SNAPSHOT` name moved with the file, in the same commit — the two are one
trust root. Every query carries `--limit 1000` and
asserts the returned count is strictly below it, because `gh issue list`
defaults to thirty, exactly its page size, so a truncated result is
indistinguishable from a complete one.

**The accounting is recomputable, which it was not before.** The window from
the previous snapshot to this one is `2026-08-27T05:54:56Z` (the commit that
installed it, 33049a9) to the capture, and the whole acquisition — number,
state, `createdAt`, `closedAt`, `updatedAt` and title for every issue the
tracker holds — is committed as
`spike/freeze-audit/capture-2026-08-29-raw.json` with its query, its limit
and its instant. Every count on this page is recomputable from that
file — the gate recomputes the population, the window's closed set and the
measured closed-set additions on every run, and a reader can derive the rest (the
class tallies, the forecast count, the volume figure below) from the same file.
None is quoted from a transcript: fifty-six open (forty-seven surviving
from the previous snapshot, nine filed since), eight previous-snapshot issues
since closed — six of them landing or scheduling the window's pre-tag work
(#323, #363, the sweep's own #281 and #353, and the after-1.0 pair's third,
#217, beside #201 and #202) plus the measured #272 — and **zero issues opened
and closed inside the window**, the set a final-state capture cannot see at
all, and which is why this page carries a resolved section enumerated by a
closed-issue query (the previous two sweeps' equivalents were thirty-eight
and four).

The tables are **generated** from `spike/freeze-audit/audit.tsv` by
`spike/freeze-audit/render-audit.sh` (ADR 0027) — the manifest is the trust
root for row content and a hand edit to either table is a check failure. What
moved on a frozen surface is *not* in that manifest: it is one row per change
in `spike/freeze-audit/surface-changes.tsv`, measured by
`spike/freeze-audit/surface-drift.sh` (ADR 0028), because a change is
(surface, item, kind, before, after, commit, issues, legality) and issues and
changes are many-to-many. Completeness, row shape, both renders, both ledger
directions and the measured closed set are checked by
`spike/freeze-audit/check-freeze-audit.sh`, **run at each sweep, not wired
into CI** — this page retires at the v1.0 tag, and a permanent gate for a
retiring page is a layer this repo declines. The gate proves on every run
that it can go red: it deletes one active row from a run-time copy of this
page and requires that copy to fail (the copy is generated, never committed —
a committed fixture rots silently after a re-sweep, and an absent one must
not read as a passed falsification; both failure shapes were measured).

Two sentences that stood here for two sweeps have been corrected. The claim
that the sweep "excludes #87, closed seventeen seconds before it" belongs to
the **original** sweep of 2026-08-17 — `#87` closed at
`2026-08-17T00:32:58Z` — and was carried into the re-sweep's paragraph, where
it read as a statement about a capture taken a day later. And nothing
machine-checked the snapshot's own completeness; the gate now recomputes it
from the committed capture, which bounds the claim to what that capture can
support.

Gate output, 2026-08-29 (fourth sweep): `ok: 122 rows (56 active, 66
resolved) cover the 56 snapshot issues; both tables are byte-identical
renders of the manifest; every enum, the class-dependent disposition rule and
both ledger directions hold; the 8 measured closed-set additions match
surface-changes.tsv; the declaration is at the revision this sweep read; and
the gate goes red on a one-row-deleted copy.` `--live` the same day: no
drift — every snapshot issue still open has an active row, every one now
closed has a resolved row, and nothing has been filed since.

Gate output, 2026-08-27 (re-sweep): `ok: 113 rows (53 active, 60 resolved)
cover the 55 snapshot issues; both tables are byte-identical renders of the
manifest; every enum, the class-dependent disposition rule and both ledger
directions hold; the 5 measured closed-set additions match
surface-changes.tsv; the declaration is at the revision this sweep read; and
the gate goes red on a one-row-deleted copy.` The two earlier sweeps measured
the same shape on smaller sets, with the reverse measured once (a forged
snapshot row makes it fail, naming the row) and the strike separation seen red
once.

**`--live`'s predicate changed, and the reason is measured.** It used to be
"the snapshot IS the tracker's open set". A sweep closes its own obligation
issue, so that equality breaks the moment a sweep lands — `#86` closed at
`2026-08-18T04:06:58Z`, **one second after** the snapshot commit at
`04:06:57Z`, and it has been false ever since. "Run it green before the tag"
was therefore unachievable rather than strict. The predicate is now: every
snapshot issue the tracker still shows open has an active row, and every one
it shows closed has a resolved row. That is what "the page has caught up with
the tracker" means, and it survives a sweep closing its own issues. It also
fixes the older inconsistency the old predicate hid: `#86` sat in the
*active* table while closed, and this sweep's own issues (`#281`, `#353`) are
resolved rows rather than active ones.

**The rule this declaration carries.** It takes effect at the v1.0 tag, not
today. Before tagging, the sweep is re-run and this page updated for any
issue opened or closed since the snapshot — **the audit is a gate, not a
ceremony performed once and aged.** The 2026-08-18 re-sweep satisfied that
rule for the tag it was aimed at; it did not retire the rule, and the
sentence saying so was briefly deleted in the re-sweep's own PR and restored
when the next two filings proved why it exists (below). The declaration's
permanent home is `docs/contract-freeze.md` — this page retires at the tag,
the promise does not.

**The previous sweep's informal reading has been formalised.** That sweep
noted `#180` and `#181` as filed hours after its snapshot, read them against
the five surfaces itself, and deferred the formal classification to "the next
sweep". This is that sweep: both closed inside the window and both carry
resolved rows below, and the earlier reading held — `#180` was release
engineering and `#181` added capability through channels already frozen and
already accommodating it.

## The declaration: what freezes at v1.0

**Moved to [`docs/contract-freeze.md`](contract-freeze.md)** (2026-08-18,
the re-sweep): this page retires at the tag, the promise does not, and a
freeze whose only home is a retired page is a freeze nobody can read. The
five surfaces — config format, report schema, exit codes, replay
compatibility, the MCP surface — live there verbatim, with their owner
decisions (#94's exit-code split declined permanently among them). PRD
criterion 5 names all five and points the same way.

## What this gate guarantees

Stated here because it was never stated precisely in one place. It has been
written three ways: #86's own title says "every open issue touching a frozen
surface gets fixed or documented before the freeze"; #353 says "no open
frozen-surface issue at the freeze"; `PRD.md` says "none left as a documented
hole under an intact PASS claim". The first two make touching-and-open the
condition, and that is measurably not it.
Three issues in the 2026-08-18 snapshot are open, carry classes, and criterion 5
is met. `PRD.md`'s wording is the operative one — "none left as a documented hole
under an intact PASS claim" — and the owner's ruling of 2026-08-27 makes it two
clauses:

1. **No issue whose adjudication is unexecuted.** Whether the issue is open is
   not the question; whether its ruling has been carried out is. #39 was this
   clause's live example — open as the mkstemp family's lookout post with its
   narrowing executed, and the gate passing over it for exactly that reason —
   until 2026-08-31, when the class stopped being a wall and the row resolved
   (ADR 0036). The clause is unchanged by that; it lost its illustration, not
   its meaning.
2. **No class-A gap left documented under an intact PASS claim.** Note that this
   is tighter than #86's "fixed **or documented**": the class definitions below
   settled later that class A is the one class prose cannot retire, and where the
   two disagree the class definition is the operative one. Class A's resolutions
   are therefore: the resolutions are fix, demote to a refusal,
   or narrow the stated promise. Narrowing counts because it *changes the
   promise*, not because writing counts — explaining a gap without narrowing
   anything is exactly the "prose alone" this refuses.

**What the gate checks, and what it does not.** The check holds the *form* of
every row — the surface, class and state enumerations, the class-dependent
disposition rule, one row per snapshot issue, byte-equality between both tables
and a fresh render, referential integrity in both directions between the two
ledgers, and the window's accounting recomputed from the committed capture. It
also holds the one thing this sweep could measure outright: the `unknown_reason`
closed set's additions must be exactly what `surface-changes.tsv` records.

Three things it does **not** hold, each stated because a reader could reasonably
assume otherwise:

- **It does not verify that an adjudication was executed.** An A row saying
  `narrow` with nothing behind it passes. Both clauses above are human-reviewed
  assertions carried by the rationale column, held by review the way the numbers
  on this page always have been.
- **It holds the enumerated half of each frozen surface, not the behavioural
  half.** See the measurement section below for which clauses are which. This is
  a measured limit, not a cautious one: `#273` moved the exit-code surface inside
  this window while the `ExitCode` enum stayed byte-identical.
- **It cannot check a forecast.** An active row's surface entry says what
  resolving the issue as filed *would* move. Only the next sweep's measurement
  can confirm or correct it, which is the same standing the previous sweep's
  informal reading of `#180` and `#181` had — and that one held.

**Two axes, not one** (owner ruling, 2026-08-27; ADR 0027 carries the mechanism).
The surface a row bears on and the failure direction of its gap are different
questions. They were one column until the previous sweep, and conflating them is
why thirteen rows carried four different shapes for one rule — three touchers
with classes, six non-touchers with class C, three non-touchers with none, and
the amendment issue itself with neither. `class` applies to **every** row,
toucher or not.

**And the surface axis has two tenses, which this sweep separates** (ADR 0028).
For an open issue the question is a forecast: would resolving it as filed move a
frozen surface? For a closed one it is a measurement: did its resolution move
one? Holding both in a single column is what hid the sharpest finding of this
sweep — `#324`'s body names neither `unknown_reason` nor the closed set (measured
zero occurrences of each, raw and whitespace-normalised, in
`spike/freeze-audit/capture-2026-08-27-issue-324-body.json`, which commits the
body because the sweep's raw capture excludes bodies), and its resolution added
`trace_too_large` to that set. The surface moved in the
resolution, not in the issue text, so a page that decides surfaces by reading
issues returns `none` for it however carefully it reads. Four of this window's
five closed-set additions were lost that way in this schema's first draft.

Read against the strict enumeration, eleven of the forty-eight active rows
carry a forecast other than `none` (sixteen of fifty-three at the third
sweep; twelve rows left the active set and five of them were the ones carrying
a forecast, while the seven that arrived all forecast `none` — so the count
drops by exactly those five and the population by four). No active
row names a still-owed pre-tag
decision — the list under the table is empty again, and the section below
records how it emptied.

## What moved on the frozen surfaces

Measured, not read (ADR 0028). `sh spike/freeze-audit/surface-drift.sh` compares
the five surfaces between the commit that installed the previous snapshot and
this one, and its committed output is
`spike/freeze-audit/surface-drift-2026-08-29.txt` (the third sweep's window is
`surface-drift-2026-08-27.txt`). **This window's result**: the closed set grew
29 → 32 (`state_tree_too_large`, `state_rewrite_failed`, `child_timed_out` —
sc-14, sc-15, sc-17), one semantic exit-code movement rode #363's resolution
(three post-define rewrite-failure sites, 3 → 2, sc-16), and every other
enumerated set is unmoved: config keys 6, report fields 21, exit-code values 4,
`contract_version` 12, MCP tool names 2. `docs/contract-freeze.md` is
byte-identical across this window — the fourth sweep read the same yardstick
the third did — and all four changes were already in the ledger before this
sweep ran, recorded through the gate's own drift path (extend the ledger, move
the pin, same commit) when each landed. The narrative below is the third
sweep's window, kept as its record; the rung ladder it explains is how both
windows were measured. It reports in three rungs, separately, because they
support different claims:

1. **Blob identity.** If *every* file a surface is defined by is byte-identical
   across the window, the surface did not move — enumerated names *and*
   behavioural clauses, because the behaviour lives in those files too. This is
   the only rung that can settle a surface outright, and **on this window it
   settles none of the five.** `src/config.zig` is byte-identical, so surface 1's
   six accepted keys, its parse and its named line-numbered refusals did not
   move — but `src/main.zig` changed, and that is where the rest of surface 1
   lives: `splitArgs` (the string form's split-on-spaces rule), the argv form's
   verbatim passing, and `resolvePathAgainst` (relative paths against the toml's
   directory, ADR 0007). Those clauses are rung-3 residue for this window. An
   earlier draft of this page claimed surface 1 settled outright on
   `src/config.zig` alone; review measured that the clauses it named are in
   another file, which is the same overclaim this ladder exists to prevent, one
   level down.
2. **The enumerated diff**, for files that did change, with each extraction
   defined in the script rather than described in prose. It answers "which names
   appeared or disappeared" and nothing else.
3. **The residue, per clause.** `spike/freeze-audit/clause-checks.tsv` names, for
   each clause of the declaration, the check that pins it — or records that
   nothing does. **Every clause of `docs/contract-freeze.md` either names the
   check that pins it or says that it is unpinned**, and rung 3 prints only the
   second kind, plus the leftover half of the clauses a check covers in part.
   A clause held in full is not printed at all, so the list shrinks as checks are
   written; when it empties, this rung has nothing to report and the ladder
   collapses to two (#369). Today: 29 clauses, 10 pinned, 8 partial, 11 unpinned.
   The `by` column names a suite and a heading rather than a check id, and rung 3
   fails if that heading is gone — a row cannot go on claiming a check that was
   renamed away. **That failure is only seen by whoever runs the sweep**: no
   workflow invokes `surface-drift.sh` or `check-freeze-audit.sh`, so a renamed
   heading merges green and the row goes stale until the next sweep reads it. What is **not** machine-checked is that the enumeration is
   complete: a clause is one independently checkable assertion, which matches no
   boundary in the text, so nothing can compare the file against the declaration
   and find a missing row. The `clause` column is verbatim, which stops a row
   from describing text that is not there; the other direction is held by review.
   **That gap has been measured, not just conceded.** The file shipped at 26 rows
   and was three short — the declaration's claim that the listed keys and the
   code's accepted set stay the same list, `sc-18`'s legality reading
   `freeze-broken`, and `contract_version_mismatch` being a different refusal
   from a saved case's — with a fourth row, `s1-string-form`, naming a check that
   drives half of its clause. All four were found by a second reader walking the
   declaration sentence by sentence against the rows, none of them reddened a
   gate, and that walk remains the only instrument for this direction.

**What rung 2 found, all of it legal, and all of it previously unrecorded:**

| surface | movement | legality |
|---|---|---|
| 1 config format | keys and parse unmoved (rung 1 on `src/config.zig`); `src/main.zig` changed, so the spelling and path-resolution clauses fall to rung 3 — where `s1-argv-form` turns out to be pinned by `check 2ab`, `s1-string-form` half-pinned by the same check (nothing drives its no-quoting rule), and `s1-relative-paths` by nothing | — |
| 2 report schema | **five `unknown_reason` members added**, none removed | pre-tag only: the closed set is excluded from the additive allowance by name |
| 2 report schema | one field, `checker_earliest` | additive, permitted in any 1.x |
| 3 exit codes | four codes, values unchanged | — (rung 3: `s3-exit-zero-not-pass` and `s3-no-evidence-split` unpinned) |
| 4 replay compatibility | `contract_version` 10 → 11 → 12 | declared not a broken promise |
| 5 MCP surface | two tool names, unchanged | — (rung 3: `isError` pinned in mcp-acceptance.sh, `s5-input-schemas` unpinned) |

Seventeen changes are recorded one per row in
`spike/freeze-audit/surface-changes.tsv` with the commit, the causing issue and
the evidence — thirteen by the 2026-08-27 sweep, and four appended on 2026-08-29
when the pre-tag closed-set members landed after it (sc-14..sc-17, the pin moved
in the same commit: the path the gate itself names for post-sweep drift). Attribution is a human judgement recorded per change, not a parse:
`git log -G` answers "which commits contain a matching diff", never "which issue
required this line", and the commit-subject convention is not uniform enough to
be a rule. Of the nine commits this sweep attributes changes to, three carry no
trailing parenthetical at all, and among those that do it is sometimes the pull
request (`8b75ad7` ends `(#231) (#241)`, where #231 is the issue and #241 the PR)
and sometimes the issue itself (`7ed5c97` ends `(#269)`, an issue). A parser cannot
tell which without looking each number up, which is the definition of not a rule.
One change names no causing issue at all, because attributing it to the issue
that rode the same commit would be association rather than cause.

**The yardstick moved too, three times, and no sweep had ever recorded that.**
`docs/contract-freeze.md` is the declaration every reading here is taken strictly
against, and inside this window it was amended by `0e035eb` (surface 2 gained the
additive allowance *and* the closed-set exemption), `9f04932` (surface 3 rewritten
from a flat code list into a one-way verdict-to-code promise, legalising `#273`'s
`--help` change) and `975e2fd` (surface 4's previous text measured against the
code and found **wrong** — it had split one refusal across two reason names).

Two consequences worth stating plainly. First, **the additive allowance most of
this sweep's readings lean on did not exist when the snapshot being replaced was
taken**; it was written on 2026-08-26, eight days into the window. Second, twice
in this window a surface's declaration was amended by the same commit that
changed the surface. Before reading circularity into that: in both cases the
amendment constrained the change rather than excusing it — `0e035eb` wrote the
sentence that binds its own closed-set addition to pre-tag, and `9f04932`
narrowed what a verdict may return. The audit records the pattern; it does not
allege a fault. What it does now insist on is that a sweep pin the revisions
it read, and the gate reports two ages against those pins: **staleness** if
`docs/contract-freeze.md` has moved since the readings were taken, naming both
shas, and **drift** if an enumerated frozen surface has moved since. Both exit 3
and neither stops the legs behind it. The second is the one no earlier mechanism
could reach — a frozen surface can move without any issue changing state, so
every population check is blind to it by construction, and the one leg that is
not blind has to be reached before it can say so.

**Both ages are a sweep's to resolve, and only a sweep's.** A pin asserts that
somebody read the five surfaces against that revision; moving one is a claim
about a reading, not a data update. An author whose change moved the declaration
or an enumerated surface has not taken that reading, so **those two reports** say
plainly that there is nothing here for them to do. That reassurance is scoped to
them: a leg that cannot extract a surface at all is saying the gate's own
extraction no longer matches the code, which does want someone to look. It did not always. The declaration check used to
`exit 1` — the code for a malformed audit — and told whoever saw the red to
"re-read the surfaces, then update DECLARATION_PIN in the same commit": advice
only a sweeper can honestly follow, put in front of an author who could not.
A parallel session landing a new closed-set member read it, correctly doubted
it, and asked whether to break the standing agreement that authors do not touch
`spike/freeze-audit/` (#371). Exiting 1 also hid every leg behind it. `config_keys`
gained `cwd` with no ledger row — which under (A) below is the correct state until
the next sweep, not a defect — and **nothing reported it** for a day, because the
leg that would have was never reached.

The ledger row and the pin stay **coupled**, which was a choice with a named
alternative. **(A)** keep them coupled and let a sweep move both: the ledger
stays "what a sweep measured", which is what its header claims. **(B)** decouple
them, so the gate requires the causing PR to add its row while the pin moves only
at a sweep. (B) is the stronger invariant and the worse arrangement: it turns a
file one sweep owns into a file every surface-touching PR must edit, and what it
buys — the row landing earlier — the next sweep buys again anyway. **(A) is
taken.** (B) is recorded because it is the shape to move to if
`spike/freeze-audit/` ever stops being sweep-owned.

## Every open issue, classified

Classes, per #86's amendment and no longer restricted to touchers (see the
invariant above): **A** — the gap can make PASS overclaim (prose alone cannot
retire one; resolution is fix, demote to a refusal, or narrow the stated
promise); **B** — FAIL-side noise or precision; **C** — ergonomics and
diagnostics; **D** — an adversarial surface: the gap hands an attacker a
capability against a consumer of the output or against the operator's
filesystem, and its own resolution `contain` means the exposure is bounded by
a stated operational precondition rather than removed.

**D is new in this sweep (owner ruling, 2026-08-27), and the enumeration had
already been strained twice before it.** Five open issues here come from
threat-model runs — `#325`, `#328`, `#337`, `#338`, `#339` — and fit none of
A, B or C: a channel that carries attacker-chosen text into a reading agent's
context is not PASS overclaim, not FAIL-side noise, and calling it
"ergonomics and diagnostics" would be this page misdescribing its own
content. The historical rows had already reached for `A-adjacent` (`#10`) and
`C-shaped` (`#167`) rather than pick one of three, and three more carried no
class at all; migrating them is what made the gap impossible to keep
deferring. Those hedged values are mapped to A and C in the manifest with the
original word kept in the row's rationale.

**The disposition sets were also written from too small a sample.** They came
from the thirteen active rows of the previous sweep, and the seventeen
historical resolved rows do not fit them: `#12` closed as documented on a
class-C row, `#6` and `#13` were measured already-fixed outside class A, and
`#165` was a duplicate. Class A keeps the restricted set, because it is the
class prose cannot retire; B, C and D share a wider one.

**`after-1.0` is a disposition, added 2026-08-27 by owner ruling, and class A
cannot take it.** It means the owner scheduled the work outside v1.0's scope, so
the tag does not leave a frozen surface broken by it. It replaced `defer` on the
four open `after-1.0` rows (`#123`, `#262`, `#279`, `#286`) because `defer` is
defined here as deferral *to 1.x*, and these are deferred *past* the frozen
contract's life — seven issues carrying one adjudication under two words. The
asymmetry is the point: **scheduling a PASS-overclaim gap out of the release is
exactly the outcome class A forbids**, so an enum that accepted `after-1.0` there
would let the one clause with teeth be satisfied by a calendar rather than by a
fix, a demotion or a narrowing. The gate withholds it from A for that reason. Class-A resolutions
below are the owner's adjudication (2026-08-17), taken with the recommendation
visible before deciding.

<!-- BEGIN generated: freeze-audit classification (render-audit.sh) -->
_Generated by `sh spike/freeze-audit/render-audit.sh` — do not edit between the markers._

| # | what it is | surface | class | resolution |
|---|---|---|---|---|
| #62 | loop-closure stage clones the full upstream | forecast: none — apparatus weight | C | **defer** |
| #63 | the agent-side seal has never been seen red | forecast: none — experiment apparatus | C | **defer** |
| #123 | the judge cannot follow a target across execve | forecast: none — implementing it is a trace-contract event, and surface 4 says in as many words that a future trace-contract bump is not a broken promise | C | **after-1.0**: with the recorded reading: the single-pid exec chain is already judged under the contract of its day, and a bump refuses old cases with the mismatch named |
| #147 | outcome-map.tsv overcounts reported-upstream rows | forecast: none — evidence-page correction | C | **tracked**: stays open; the fix is independent of any frozen surface |
| #161 | release glibc floor inherited, not chosen | forecast: none — release engineering, outside the five surfaces | C | **defer**: worth deciding before 1.0, not contract-bound |
| #257 | determinism apparatus is rebuilt by hand per target; no declared-apparatus surface exists | forecast: config-format report-schema — a define naming its apparatus is an additive config key and the report carrying the declaration is an additive field; both sit inside the allowances surfaces 1 and 2 state | C | **defer**: Nothing here is tag-blocking, but the issue is right that the shape is cheaper to decide before the tag than after. |
| #258 | wall roadmap ordering: encounter frequency and contract cost disagree | forecast: none — a scheduling question about other issues, not a gap in a surface | C | **defer**: Asks for an explicit owner decision on post-tag order with the encounter table in front of it. |
| #259 | every cohort rewrites its probe, drill and transcript harness | forecast: none — spike apparatus, outside the five surfaces | C | **defer**: The re-derivations re-import bug classes review then has to re-find; three have recurred across cohorts. |
| #260 | selection rule 5 misses user-side recoverability: the poetry lesson | forecast: none — a selection rule for future cohorts, not a surface | C | **defer**: To settle before cohort 5 selects, per the issue. |
| #261 | the define cannot declare non-durable paths, and the L0 precision limit keeps consuming targets | forecast: config-format report-schema — either candidate shape — an ignore list in the define, or an L1 durability marker — adds a config key and a report field, both additive | B | **defer**: Four recorded shapes have already spent a target, a claim or an engine PR on this limit. |
| #262 | exploration is strictly sequential and every world pays the full state size | forecast: none — the cheap steps (binary search in find, a hash-first compare) touch no frozen surface; parallelism would, and the issue defers that | C | **after-1.0**: Labelled after-1.0. The tracked home for the throughput bound. |
| #263 | no timeout exists anywhere: one hung world stalls an explore forever, silently | forecast: report-schema — a named refusal for a wall-clock breach needs a new closed-set member, and the closed set is excluded from surface 2's additive allowance — so the naming, if that is the shape, can only land before the tag | C | **defer**: PRE-TAG DECISION OWED: the issue says the naming belongs before the tag even if the default stays off. Undecided as of this sweep. |
| #274 | refusals help unevenly: the commonest detectors ship one word | forecast: none — enriching a refusal's message text, or a new diagnose subcommand, is CLI and message prose rather than a frozen field's meaning | C | **defer**: The refusal a new user hits first carries the least help; the discrimination it declines is cheap outside the engine. |
| #275 | sideeye.toml cannot carry oracle or work: a committed define stops one flag short | forecast: config-format — an oracle key is an additive config key, and surface 1 says in as many words that additive keys remain possible | C | **defer**: Not tag-blocking. The issue's own precedent (#95, the argv form) landed pre-freeze for convenience, not necessity. |
| #276 | the checker cookbook contains no checkers: four recipes, all pointers into spike/ | forecast: none — documentation, outside the five surfaces | C | **defer**: The page's own premise is that the checker is the layer that fails quietest. |
| #279 | a contract bump orphans every saved case: three re-records paid by hand | forecast: replay-compatibility — surface 4 says a future trace-contract bump is not a broken promise, so what this issue asks for is a migration story about cost, not a change to the promise | C | **after-1.0**: Labelled after-1.0, but the issue is right that CI's regression-case story should name the helper before the first post-tag bump improvises it. |
| #280 | hand-synced pairs and untested cores inside src/ | forecast: none — internal duplication with nothing pinning the copies together; no frozen surface | C | **defer**: Test weight sits away from the sharpest code, measured per file in the issue. |
| #286 | macOS verification without per-run root: three routes, none measured | forecast: report-schema — each route buys a verification claim weaker than oracle_verified, and the issue names the report vocabulary as the real contract surface | C | **after-1.0**: The owner priority recorded in the issue argues against defaulting it to after-1.0; the vocabulary decision is still open. |
| #293 | can FSEvents veto a mutation the shim never reported? | forecast: report-schema — any veto is a claim weaker than oracle_verified and needs its own name in the report, which the issue names as the contract-reopening half | C | **defer**: H1 measured and dead; H2 not judged. The apparatus is committed and reusable; what is missing is the corpus. |
| #297 | upstream-report-status.sh cannot see a report that was never added to its list | forecast: none — spike tooling, outside the five surfaces | C | **defer**: The failure mode is an absent row, not a wrong one, and the script's output cannot distinguish six-of-six from six-of-seven. |
| #299 | the other family: a recorder whose coverage is complete by construction | forecast: report-schema — a generated interposer would need its own claim vocabulary if it ever became a verification route | C | **defer**: Filed so it is not lost, explicitly not as a commitment. |
| #318 | an empty-diff claim drops its normalisation, and the record miscounts its own | forecast: none — committed prose, outside the five surfaces | C | **defer**: The class is at three instances, which is this repository's own full-sweep threshold. |
| #325 | a relative define.state in a case file resolves against the invoker's cwd, unlike a config's | forecast: replay-compatibility — refusing a relative state in a case file changes which case shapes the engine accepts, which is the travel-together half of surface 4 | D | **defer**: Found during #266's security review. Fail-closed today under --state-under, and cases the engine writes always carry absolute state, so the hole needs a hand-written case to reach. |
| #337 | relay the oracle's decomposition, not the raw strace line | forecast: report-schema — the issue states the blocker itself: message is a report field, so its MEANING is frozen surface 2, and changing what it carries is a breaking change rather than an additive one | D | **defer**: The sharpest self-declared toucher in this sweep. Blocked by the freeze rather than handled by #326's marking, and the issue exists because only the second of those had been written down. |
| #338 | compare device and inode across the check and the open | forecast: none — an internal hardening of the destructive path; no frozen surface | D | **defer**: #335 changed the cost: one side of the comparison is already an open descriptor. Closes the check-to-open race outright; the pre-existing bind mount stays open and cannot be closed this way. |
| #339 | acceptance plants a forged closing banner; the opening banner is the untested half | forecast: none — an acceptance leg and one clause of a tool description; the isError rule and the tool names are untouched | D | **defer**: A counting reader is structurally unaffected because everything before the real banner comes from closed sets; a scanning reader is not. |
| #341 | four of #239's new predicates have no fixture | forecast: none — spike gate internals, outside the five surfaces | C | **defer**: The predicates are live today; what is missing is the proof that they stay live. |
| #342 | the ledger sizes are prose outside the generated block, and nothing recomputes them | forecast: none — a generated-docs bookkeeping question, outside the five surfaces | C | **defer**: The files cannot drift from each other; what can drift is the page's description of them, and a reader checking completeness reads the prose. |
| #344 | the fsevents sensitivity leg needs an msync-class mutation | forecast: none — spike apparatus for a route that is itself undecided | C | **defer**: Belongs to #293's owner: whether the apparatus is rebuilt at all is part of the route-B decision. |
| #349 | reports carry no generation or run identity: a swapped report passes every check | forecast: none — the cheapest fix is a sha in the sweep manifest, which is spike tooling; the alternative (a run identifier the engine is told) would be a config surface question, and the issue says so rather than assuming it | C | **defer**: Measured, not supposed: twenty-eight shared reports copied byte-for-byte between generations produced a green check. |
| #350 | committed oracle logs carry the sweep machine's absolute paths | forecast: none — committed evidence and a spike capture step; no frozen surface | C | **defer**: No keys or tokens are present, checked. What the paths do is put a machine layout into a public record permanently, and every re-sweep adds more. |
| #352 | a refusal before the oracle block says no oracle was given, on runs that gave one | forecast: report-schema — the oracle string is an account field, and surface 2 says the account fields' prose may improve between releases — so correcting it is inside the promise, not against it | B | **defer**: The machine-readable surface stays honest (oracle_verified: false is correct for every one of these); what is wrong is the prose a human reads in the same document. |
| #356 | the three documents that carry criterion 3's reopen rule can drift apart unchecked | forecast: none — release-gate bookkeeping across three documents, outside the five surfaces | C | **defer**: The predicate is written out in the issue. #240 ran it as a throwaway script deliberately; that reasoning expired with the PR. |
| #357 | a quoted figure is checked for existence in a source, not for being the right figure | forecast: none — an acceptance check over committed prose, outside the five surfaces | C | **defer**: The issue records the honest weighing itself: this failure mode has one measured instance (a mutant) and the one review caught has three. |
| #359 | where the root denylists live: engine.zig hosts a rule two consumers share | forecast: none — an internal placement question; both entry points keep their names and signatures | D | **defer**: The issue also records that #329's plan gave a false reason for not doing it, so that reason is not inherited. |
| #370 | the v7-case acceptance leg claims 'never a verdict' and does not assert it | forecast: none — an acceptance leg's assertion strength over surface 4's promised refusal; strengthening the check moves no surface | C | **defer**: Filed 2026-08-28. The engine refuses correctly today; the gap is that the leg would stay green on a regression that answers a verdict with the mismatch message in the output. Same family as #341's fixture gap. |
| #371 | the drift message tells the wrong actor to move the pin, and a pin asserts a reading nobody did | forecast: none — the audit gate's own diagnostics and pin semantics, outside the five surfaces | C | **defer**: Filed 2026-08-28, measured by a coordination failure it caused. This sweep re-pins with the reading actually taken (surface-drift-2026-08-29.txt committed beside it); the message's audience question stays open. |
| #373 | docs/adr/ numbering has no exclusion, and a collision merges green | forecast: none — repository hygiene over docs/adr/ filenames, outside the five surfaces | C | **defer**: Filed 2026-08-28 after two sessions each created an 0028 on the same day and only conversation caught it. The proposed check is three lines beside an existing spike check. |
| #374 | entries in the [Unreleased] block invalidate each other, and the stale ones stay | forecast: none — release-notes prose hygiene, outside the five surfaces | C | **defer**: Filed 2026-08-28 with a measured claim family (the memory-bound wording) where a later entry falsifies an earlier one and both stand. The release checklist rewrites the heading, not the entries. |
| #376 | SnapshotError types a reader that cannot raise half of it | forecast: none — internal error-set precision; every consumer already catches the whole set, so no behaviour or surface moves | C | **defer**: Filed 2026-08-28. The cost is that snapshotDetail's exhaustiveness covers a wider set than each producer can raise, which weakens the new-member-is-a-compile-error mechanism's precision, not its soundness. |
| #377 | max_trace_bytes is per-read, the way the per-file cap was before #323 | forecast: none — a bounded-by-counting property of the engine's own memory, outside the five surfaces; the issue names no new member and the existing refusal covers each read | C | **tracked**: Filed 2026-08-28 so the property lives somewhere other than an argument: the total is bounded by there being two read sites in one function, and a third would move the bound with nothing noticing. Lower urgency than #323 was — neither read is target-controlled in size. **Both halves of that forecast were wrong, measured 2026-08-30.** There were already THREE read sites, in two functions — the third arrived with preflight --twice (#199) and says so in its own comment — and six documents still said two. And the fix did need a new closed-set member: trace_budget_exhausted, because a shared-ceiling refusal is a different fact from one trace being too large, the same reason state_tree_too_large is not folded into state_file_too_large. Fix shipped with ADR 0033; this row moves to resolved and its sc- row lands in the follow-up audit commit, which is where a row naming its own merge sha can be written (sc-18, for #405s break, is still waiting for the same follow-up). |
| #383 | the onboarding clock's launcher can silently reuse a stale box | forecast: none — criterion 6's spike apparatus (run-clock.sh preflight), outside the five surfaces | C | **defer**: Filed 2026-08-28 from run 2, which was taken against a box started 2h51m earlier after a name-conflict docker run failure. The run stands — zero files changed inside the box between its start and the run, measured with a 47-file control — and the preflight's missing age check is the filed gap. |
<!-- END generated: freeze-audit classification -->

Forty-eight active rows at this re-sweep, against thirteen at the previous one
and twenty-six at the original; seventy-four resolved rows below, of which
seventeen are migrated from the two earlier sweeps and fifty-seven closed since.

**Eleven active rows now carry a surface forecast other than `none`, where
the previous sweep's page said no row touched a frozen surface at all.** That
is not a change of standard; it is a larger population read against the same
declaration. The sharpest is `#337`, which states the blocker itself — the
report's `message` field is frozen surface 2, so shrinking what it carries is
a breaking change rather than an additive one — and is deliberately after-1.0
for that reason. The three rows that named a **still-owed pre-tag decision** at the third
sweep — `#263`, `#323`, `#363`, foreclosed because the `unknown_reason`
closed set is excluded from surface 2's additive allowance — have all
resolved inside this window, each with its member landed before the tag:
`state_tree_too_large` (#323, sc-14), `state_rewrite_failed` plus the three
exit-path movements (#363, sc-15 and sc-16), and `child_timed_out` (#263's
first half, sc-17; the issue stays open on its stdin question, which reuses
nothing frozen and carries no deadline). Every remaining forecast falls inside an allowance the declaration
states: additive config keys (`#275`, `#257`), additive report fields
(`#257`, `#261`), a trace-contract bump, which surface 4 says in as many
words is not a broken promise (`#279`), or account-field prose, which surface
2 permits to improve (`#352`).

Class A holds eleven rows, all resolved — fix (`#46`, `#164`, `#169`, `#244`,
`#256`, `#264`, `#333`), demote (`#5`), measured already-fixed (`#27`) and
narrow (`#10`, `#39`). `#39` was the one active row until 2026-08-31: its
narrowing was executed on 2026-08-17 and the issue stayed open as the mkstemp
family's lookout post by owner decision, until the class stopped being a wall
(ADR 0036) and the lookout became a standing check. That is still the whole
point of the invariant's first clause: what the gate asks is whether a ruling
has been carried out, not whether the issue is shut. Not one of the eleven was resolved by leaving a PASS claim intact over a
documented hole, which is the outcome class A forbids.

## Resolved before the tag

Every row below was an open issue in some sweep's snapshot, or was filed and
resolved between sweeps — zero such issues in this window, against
thirty-eight in the third sweep's and four in the second's, enumerated by a
closed-issue query over the window, since a final-state capture cannot see an
issue that opened and closed inside it. The
struck rows keep their adjudication history, and the table is now **generated
from the manifest** like the active one: until this sweep it was hand-written
and the gate counted active rows only, so seventeen rows of adjudication
history were held by nothing.

**Read the surface column carefully — it says which question it answers.**
A row measured by this sweep's surface diff says so, and names the change ids
in `surface-changes.tsv` when its resolution moved something. A row that
closed *before* this window says **not measured by this sweep** and carries
the reading the earlier sweeps took, because a diff over this window supports
no claim about it. The first draft of this migration wrote `none` for those
rows too, and the render then read "measured: no frozen surface moved — yes —
verdict soundness" on a row the earlier sweep had recorded as touching one.

<!-- BEGIN generated: freeze-audit resolved rows (render-audit.sh) -->
_Generated by `sh spike/freeze-audit/render-audit.sh` — do not edit between the markers._

| issue | what it says | surface | class | resolution |
|---|---|---|---|---|
| ~~#39~~ | libc conveniences that mutate state behind the PLT (mkstemp family) | not measured by this sweep (closed before its window) — observation reach is not one of the five; what it bears on is PASS soundness, which is why this row carries a class without touching a surface | A | **narrow**: on Linux the class fails closed through the oracle (sound today); the narrowing itself is written in docs/target-classes.md under "Internal libc calls that mutate state" (measured 2026-08-22 on spike/toys/toy_mkstemp.c), and the issue stayed open as the mkstemp family's lookout post until this row resolved **Executed 2026-08-31**: the five name-generating creators (mkstemp, mkostemp, mkstemps, mkostemps, mkdtemp) are reimplemented in the shim through the recorded wrappers (contract v13) and measured judged rather than refused, member by member, in spike/libc-internal/RESULTS.md; dprintf stays a wall by decision (glibc splits a large write at 8192, so a replacement would either delete a crash point or hard-code a libc internal) and tmpfile is not a member (O_TMPFILE creates no directory entry). ADR 0036 replaces the first-contact trigger with a proof obligation, so the lookout post this row named is now a standing check rather than an open issue. |
| ~~#64~~ | secondary observations lack a committed generator | no attributed enumerated change — apparatus: the change is confined to spike/loop-closure-timew/ shell, DESIGN §17's status paragraph and this ledger; none of the enumeration sources (src/contract.zig, src/config.zig, src/mcp.zig, docs/report-schema.md) or docs/contract-freeze.md is in the diff | C | **fix**: Closed 2026-09-03: judge.sh secondary --mode neg\|pos\|run produces the full exploration and the four upstream C++ suites from the committed apparatus, verifies the seal without restoring, and refuses to read a run until both controls have held. Run 1 and run 2 keep their cited figures (their stages are gone); the generator's own controls are recorded on the #62 witness stage. Evidence beside the three gates, not a fourth gate. |
| ~~#65~~ | invariant and leg-C predicate hand-synced across spike/ | no attributed enumerated change — apparatus: the change is confined to spike/ shell, one python file and docs; none of the enumeration sources (src/contract.zig, src/config.zig, src/mcp.zig, docs/report-schema.md) or docs/contract-freeze.md is in the diff | C | **fix**: Closed 2026-09-03: the checker, setup and operation string have one canonical text in spike/loop-closure-timew/define/; stage.sh and dogfood-timew-replay.sh copy the checker and setup and read the operation; the leg-C predicate is spike/replay_gate.py, read by judge.sh and leg C. spike/dogfood-timew.sh keeps its copy on purpose: the unknown-rate corpus pins its bytes, so it is a record rather than a consumer. The one-field JSON reads and the STAGE/SEAL/RESULTS derivations stay duplicated; their drift fails loudly across scripts, which is the property the change buys elsewhere. |
| ~~#118~~ | assisted-discovery product thesis | no attributed enumerated change — product tracking; the thesis landed in docs/scouting.md, ADR 0017 and criterion 1's status, and the issue closed on owner ruling | C | **document**: Closed 2026-09-03 by owner ruling: the product decision (advance) shipped as docs/scouting.md (2026-08-16; the capability floor from #221 followed on 2026-08-22); criterion 1 was redesigned around provenance (ADR 0017) and met 2026-08-25 (himalaya-r2, assisted); v1.0.0 shipped 2026-08-29. Later measurements live in spike/cohort2..4/ and spike/scout-model-comparison/, not on the issue; the re-scoring is 3 of 5 (CHANGELOG and spike/assisted/RESULTS.md carry the correction). |
| ~~#156~~ | `--oracle` + `--allow-unverified` accepted and inert | no attributed enumerated change — reading taken by the fourth sweep, 2026-08-29: no — CLI acceptance semantics are not surface 1, which freezes the toml keys and the two command spellings | C | **document**: ~~defer~~ **Closed 2026-08-29, the issue's own closing condition fired**: its text said that if the freeze audit closed without the change, the accepted-but-inert behaviour freezes as-is. #86 closed and v1.0.0 was tagged 2026-08-29, so it did. Nothing new was written to close it — the permanence note was already published in this row, the owner reconfirmed the deferral on 2026-08-18, and the behaviour itself is stated on `docs/report-schema.md` (`oracle_verified` is false for `--allow-unverified` with no oracle) and in README. Closed as documented, not as fixed; making the combo refuse is a 2.0 question, and the reason it cannot be a 1.x one is this row's own note |
| ~~#199~~ | preflight cannot see nondeterminism: a property of two runs, from one observed run | no attributed enumerated change — a new preflight mode or subcommand is CLI surface, which surface 1 does not freeze (it freezes the toml keys and the define's two command spellings); the issue says so itself and states that no change to the recording contract, the report schema or the closed set is required | C | **fix**: The cheapest fact about a target is currently learned the most expensive way. **Resolved 2026-09-03 as fixed**: the ask itself (`preflight --twice`) shipped in #392 (2026-08-30); what kept the issue open was the 08-29 comment — `git add` passes a bare preflight and explore refuses it at the baseline with a message that blames the checker, so the byte layer's refusal now names the path and what the re-run left it holding (gone / neither content / history no longer a prefix), points at the class wall, and the README and DESIGN list byte-repeatable writes among the limits. The 08-22 comment (libc bypass) was already answered by the recording detectors preflight runs and by `docs/target-classes.md`. No surface moved: refusal-message detail and `next_step` inside an existing member. |
| ~~#201~~ | statically-linked targets: the oracle sees them, the kill injector cannot reach them | no attributed enumerated change — an after-1.0 scheduling ruling; the wall record lives in docs/target-classes.md, outside the five surfaces | C | **after-1.0**: Closed 2026-08-27 as scheduled out of v1.0, not as resolved (state reason not-planned). The owner's 2026-08-21 ruling is in the issue's own text and the after-1.0 label; the statically-linked wall row (Jujutsu, no_shim_marker) stays in docs/target-classes.md and does not close with the issue. |
| ~~#202~~ | threaded targets: kill points lose their address under interleaving | no attributed enumerated change — an after-1.0 scheduling ruling; the wall record lives in docs/target-classes.md, outside the five surfaces | C | **after-1.0**: Closed 2026-08-27 as scheduled out of v1.0, not as resolved (state reason not-planned). The owner's 2026-08-21 ruling called it the deepest of the three reach walls, touching the determinism contract's core; the multi-threaded wall row (Bun, multiple_threads_detected) stays in docs/target-classes.md. |
| ~~#217~~ | targets whose file I/O bypasses libc: the shim loads and hears nothing | no attributed enumerated change — an after-1.0 scheduling ruling; the wall record lives in docs/target-classes.md, outside the five surfaces | C | **after-1.0**: Closed 2026-08-27 as scheduled out of v1.0, not as resolved (state reason not-planned). The after-1.0 label and the title both carry the ruling; the raw-syscall wall row (cargo, the rename diagnosis in spike/cohort3/) stays in docs/target-classes.md. |
| ~~#272~~ | the himalaya report's severity ceiling rests on three points the record marks unmeasured | no attributed enumerated change — three severity-ceiling measurements committed as cohort records (outward-reach.txt), outside the five surfaces | C | **fix**: Closed 2026-08-28 as completed: the three measurements the record marked unmeasured exist, committed in 37278fe as spike/cohort4/himalaya-r2/outward-reach.txt with a positive control beside each; RESULTS.md:115 and the CHANGELOG entry (#272, #288) are its index. |
| ~~#323~~ | the state tree's TOTAL is unbounded: the per-file cap is not a memory ceiling | measured: sc-14 — the surface diff attributes a measured change to this issue's resolution; see surface-changes.tsv for the item, the legality and the evidence | C | **fix**: Closed 2026-08-27. The owner ruled for a new member rather than riding on state_unsnapshotable — a failure with a limit reports its limit — and the ceiling landed as state_tree_too_large, naming the total read and the largest contributors. Its active row forecast this exact shape: the member was implemented and unmerged when the sweep shipped, so the gate reported it as post-sweep drift when it landed, by design. |
| ~~#328~~ | what #266's close did not close: the hostile-case residue, tracked | no attributed enumerated change — the residue is about what a case's commands DO on replay, which ADR 0010 places outside the engine's containment; no frozen surface | D | **fix**: Closed 2026-09-02 by the second of the two movements this row named — a declared non-goal with the deployment guidance strengthened. ADR 0010 now records that the engine neither provides containment nor checks for it, with the measurement behind it: the observations that move with confinement (`Seccomp`, Docker's masked `/proc`) can be raised by the confined process itself, and a container reading maximally confined by all of them still destroyed a host file through its bind-mounted root. README carries a deployment whose flags were run before being written. Sandboxed execution stays a posture change with its own cost line. |
| ~~#345~~ | what no in-file check can see: a watched name deleted from every list at once | no attributed enumerated change — a limit of a spike ratchet, outside the five surfaces | C | **document**: ~~tracked~~ **Closed 2026-08-30 as documented**: the limit is held where a reader meets it. spike/check-macos-coverage.py's own docstring records it with the measurement that found it — dropping `clonefile` from the interposed set stayed green, because the watched set is its own universe — and names what covers the rest: the darwin_libc.zig cross-check as a partial anchor, and review for a name deleted from every list at once. The issue asked for that record to exist rather than for a check to be built; its own text says the current state may be the honest optimum, and the alternative it sketches moves the delete-everything problem one file over. Closed as documented, not as fixed; an out-of-repo reference for write-capable reopens it. |
| ~~#347~~ | a generation can be marked complete with a SETUP_ERROR in it | no attributed enumerated change — spike measurement tooling, outside the five surfaces | C | **fix**: shipped 2026-08-30 (PR #413): the judgement that an apparatus failure could not be fixed is recorded in spike/unknown-rate/exclusions.tsv, and count.py check refuses a complete generation carrying a SETUP_ERROR the ledger does not name. |
| ~~#348~~ | apparatus.txt is written and never read, and a flagged trial is checked in one place | no attributed enumerated change — spike measurement tooling, outside the five surfaces | C | **fix**: shipped 2026-08-30 (PR #422): count.py check reads each completed generation's apparatus.txt and refuses a record that is absent, short a digest line, missing a resolved head:, or silent about an image its manifest uses. The second half — a flagged trial checked in one place — was already answered: that guard was deleted as true by construction, its reachable input is covered by the duplicate-id check over all corpus rows, and what a flagged row reaches is held by the attribution checks against every published aggregate. |
| ~~#360~~ | four ADRs still say Proposed after their implementing PRs merged | no attributed enumerated change — a documentation-status convention; the resolution inverts the default and adds a CI check, touching no frozen surface | C | **fix**: Resolved by writing ADRs `Accepted` with provenance instead of flipping them after the fact, and by checking the Status line in CI (spike/check-adr-status.sh). The old rule asked for a flip no single PR can perform — the ADR arrives with the work it decides — and twenty of twenty-five born-Proposed ADRs were flipped while five were not, all inside 2026-08-25..27. Pre-registration (Seal A) stays legal as `Proposed (design-first: …)`. The issue said four ADRs; measured five, since 0029 landed after it was filed. |
| ~~#363~~ | eight non-snapshot refusals still exit 3 after the define has run | measured: sc-15 sc-16 — the surface diff attributes a measured change to this issue's resolution; see surface-changes.tsv for the item, the legality and the evidence | C | **fix**: Closed 2026-08-28. Group B: the engine failing to rewrite the state tree it recorded, after the define has run, answers UNKNOWN state_rewrite_failed instead of exit 3 at the two restore sites and the corruption site — one closed-set member, three exit paths moved from 3 to 2. Group A's five apparatus reads stay exit 3 under the spawnFailure adjudication recorded on the issue; the remaining :1413 wording fix carries no tag deadline and left the tracker with the close. |
| ~~#365~~ | the trace-cap CI step's sha comparison cannot see an edit to the shipped value | no attributed enumerated change — a CI differential check; the resolution asserts the shipped option values in unit tests and the wiring at configure time, adding no public surface, so no frozen surface moves | C | **fix**: Resolved by asserting the shipped build values in unit tests (engine and shim), a declaration-count ratchet per options module (three in the engine's, one in the shim's) so a further option cannot arrive unchecked, and a configure-time assertion that each shipped artifact is built with the module those tests read — without that last one, repointing the artifact's import was a single edit the suite could not see. The issue's own measurement read wider than it was: a 64-byte ceiling does NOT go out green, because every acceptance leg that drives the shipped binary refuses on a trace that size. What goes out green is a quiet edit — measured at 128 MiB, where the sha step stayed green while `zig build test` went red. The loud half is read off spike/acceptance.sh, not run. |
| ~~#5~~ | restore drops FIFOs/sockets/devices; worlds differ from the recorded tree (symlinks fixed in #122) | not measured by this sweep (closed before its window) — reading taken by the 2026-08-17/18 sweeps: yes — verdict soundness | A | **demote**: detect a non-regular, non-symlink entry at snapshot time and refuse (UNKNOWN) rather than explore a tree that cannot be reproduced. Fix lands before the tag. **Landed 2026-08-17**: `unsupported_state_entry` fires at all three snapshots (initial, final, crashed — the last catching entries no syscall witness saw born), and the demotion's own review first forced the entrance repair: the `DT_UNKNOWN` fallback used to probe by opening, which hangs on a FIFO and misclassifies sockets and devices — classification is by `statx`/`fstatat` now, no open, no follow |
| ~~#6~~ | the oracle reads any quoted string on a strace line as a path; a target that *prints* a state path draws a false refusal | not measured by this sweep (closed before its window) — reading taken by the 2026-08-17/18 sweeps: no — internal parsing precision, fails closed, fix is non-breaking | B | **measured-already-fixed**: ~~stays open; fixable in any 1.x~~ **Closed 2026-08-18, measured already-fixed**: the issue predates ADR 0006 (2026-08-11), whose typed resolver names this false-positive verbatim in its Context and closed it — a classified `write` is an fd syscall, scoped from its descriptor annotation only, and the named unit pin exists ("a state-directory string inside a write buffer is not scope"; mutation-checked once with attribution fixed by `--test-filter`). The close is scoped to the named case: the conservative whole-line net remains for *unclassified* syscalls and only ever refuses — deliberate fail-closed residue The page left this row's class blank, from the era before class applied to every row. Assigned B: internal parsing precision, fails closed, and the fix was non-breaking. |
| ~~#10~~ | macOS Apple platform binaries can never be observed; the docs imply a narrower limit | not measured by this sweep (closed before its window) — reading taken by the 2026-08-17/18 sweeps: yes — the stated promise | A | **narrow**: `docs/target-classes.md` states plainly that a macOS target must be self-built or self-installed, never an Apple-shipped binary. The README stays under its cut-only order. **Landed 2026-08-18, wider than adjudicated here by owner decision**: the report's macOS build also named an Apple-shipped platform binary as *one possible cause* on the `no_shim_marker` detail line — never the cause; the review killed the attributing form, since the marker proves only that `shim_ready` never appeared — with the refusal shape pinned in the macOS CI job, each check predicate seen red once, and the Linux wording left byte-identical. **Superseded 2026-08-29 by #391**, which is this row's own reasoning carried one step further: naming a cause the engine had not looked at is what the clause did, and a user who checked all of the offered causes against an Apple-signed binary found every one false. The detail line now reports the fields read off the operation's executable and offers no candidates, on either platform, so the clause, the Linux wording and the clause half of the CI pin are all gone; the pin itself remains and now also asserts the old guesses are absent. This row is left as the record of what was decided in August, not as a description of what the report says Recorded on the page as class 'A-adjacent', which was not one of the three values the page defined; mapped to A here and the original word kept. |
| ~~#12~~ | the omamori dogfood cannot be agent-driven | not measured by this sweep (closed before its window) — reading taken by the 2026-08-17/18 sweeps: no — internal tooling | C | **document**: ~~defer to 1.x~~ **Closed 2026-08-18, owner decision**: the by-design account was already on the record — PRD's v0.4 status carries the full account (the guards fire for a human at a terminal exactly as for an agent; measuring one would need break-glass, which removes the defence under test), and DESIGN says "not measured either way". Closed as documented, not as fixed; the audience-assumption generalisation went to `docs/scouting.md` as one sentence |
| ~~#13~~ | stdio (fopen/fwrite) invisible to the shim | not measured by this sweep (closed before its window) — reading taken by the 2026-08-17/18 sweeps: **stale** — fixed by ADR 0005 (flush-granularity observation), pinned by acceptance check 2u | B | **measured-already-fixed**: **close as fixed**; the unmeasured reach note (Go, raw syscalls) already lives on the target-classes page The page left this row's class blank. Assigned B: an observation-reach precision limit, stale and already fixed by ADR 0005. |
| ~~#26~~ | target-chosen paths reach the text report unescaped | not measured by this sweep (closed before its window) — reading taken by the 2026-08-17/18 sweeps: yes — report surface (text) | B | **fix**: ~~document~~ **Corrected 2026-08-17, owner decision**: fixed ahead of the adjudicated minimum — the forged line was demonstrated on the pre-fix binary, the three target-chosen operands now reach the text defanged while the JSON keeps the exact bytes, and the acceptance suite pins both sides. Closes with the fix's merge |
| ~~#27~~ | standard-form L0 misses a file replaced by a directory when pre or post content is empty — a real false-PASS window | not measured by this sweep (closed before its window) — reading taken by the 2026-08-17/18 sweeps: yes — the meaning of PASS | A | **measured-already-fixed**: ~~fix before the tag~~ **Corrected 2026-08-17, measured**: the issue predates #122, whose (kind, content) pair rule already closed the named window **for pairs that enter the plan** — the issue's own scenario, both empty sides, now lands as one unit pin per case through the real classify+judge path, and a kind-blind mutation reds each pin test individually while sparing the non-empty control. Closes as measured when the pin change merges. The measurement also found the adjacent gap *outside* the plan — the dir-to-dir pair exclusion — filed as #164 and fixed in the same change; #164 joins this table at the pre-tag re-sweep per the snapshot rule |
| ~~#35~~ | L0 flags git's COMMIT_EDITMSG scratch file | not measured by this sweep (closed before its window) — reading taken by the 2026-08-17/18 sweeps: yes — FAIL-side precision | B | **document**: document as a named precision limit on non-durable files — **executed 2026-08-17**: the scratch-file pattern joined the checker cookbook's failure-patterns list with the measured run cited. Closes as documented with that change's merge |
| ~~#46~~ | no quiescence observation on the stdout capture under a tolerated boundary — a marker could silently vanish and skip L1 | not measured by this sweep (closed before its window) — reading taken by the 2026-08-17/18 sweeps: yes — PASS-side miss window | A | **fix**: before the tag: include the capture file in the same two-sample quiescence observation the state directory already gets (the issue's own fix shape). **Landed 2026-08-17** (PR #170): the capture joins the two-sample observation on both the recording and every world, arming extends to world-local boundary evidence, and the one open follow-on — whether a world-only boundary should refuse outright — is #169, deliberately out of this audit's scope because deciding it changes verdicts |
| ~~#58~~ | acceptance asserts vs PYTHONOPTIMIZE | not measured by this sweep (closed before its window) — reading taken by the 2026-08-17/18 sweeps: no — test infra | C | **fix**: ~~defer~~ **Corrected 2026-08-17, owner decision**: fixed ahead of the adjudicated deferral — every judgment `assert` across both acceptance suites and the quickstart workflow replaced by explicit exits, the assert-version hole demonstrated once on falsified input, and both suites run entirely green under `PYTHONOPTIMIZE=1`. Closes with the fix's merge |
| ~~#86~~ | this audit, and the amendment that added the MCP surface | no attributed enumerated change — criterion 5's own obligation issue, not a gap in a surface: the MCP-surface decision was recorded in it, which is not the same as touching that surface | C | **fix**: Closed 2026-08-18 by the re-sweep merge (PR #178) that installed the snapshot this sweep replaces. It sat in the ACTIVE table while closed, which is the inconsistency the gate's new predicate fixes. |
| ~~#140~~ | criterion 1's search half | no attributed enumerated change — a process criterion, not a surface: it asks for a qualifying find under the provenance gate | C | **fix**: Closed 2026-08-25 (PR #319). Its close is what made #305 filable: the himalaya finding's fix changes the operation sequence, so leg C of the replay bar is structurally unreachable for it. |
| ~~#150~~ | the FAIL headline counts the baseline under "crash worlds" | not measured by this sweep (closed before its window) — reading taken by the 2026-08-17/18 sweeps: yes — reader-facing verdict label | B | **fix**: before the tag (relabel to explored worlds; sweep acceptance greps first). Machine fields are already correct. **Landed 2026-08-18**, wider than filed: the PASS headline carried the same mislabel (the issue never named it; the plan review did) and both verdicts now say explored worlds, with the printed numbers pinned against the same run's JSON `violations`/`explored` — a wording-only pin would have passed a wrongly-changed denominator |
| ~~#157~~ | value pins cannot see a bool-vs-string type regression | not measured by this sweep (closed before its window) — reading taken by the 2026-08-17/18 sweeps: no — test infra | C | **fix**: ~~defer~~ **Corrected 2026-08-18, owner decision**: fixed ahead of the adjudicated deferral — the seven oracle_verified pins go through one typed predicate (`type is bool` with the value), self-falsified on every call against an in-memory string-"True" document through the same predicate. Closes with the fix's merge |
| ~~#159~~ | README never introduces `--shim`/`--work` outside the Example | not measured by this sweep (closed before its window) — reading taken by the 2026-08-17/18 sweeps: no — docs under the cut-only order | C | **fix**: ~~awaiting the owner's call~~ **Resolved 2026-08-18, owner decision**: a minimal Usage addition — `--shim` and `--work` introduced in the README's flag list (PR #177); criterion 6's evidence stays the pre-change README's run, deliberately not re-measured |
| ~~#160~~ | onboarding-clock hardening before run 2 | no attributed enumerated change — experiment apparatus, outside the five surfaces | C | **fix**: Closed 2026-08-25 (PR #321), hardening the onboarding clock's instrument before any run 2. |
| ~~#164~~ | a dir-to-dir pair is excluded from judgment entirely | not measured by this sweep (closed before its window) — reading taken by the 2026-08-17/18 sweeps: yes — adjacent to #27's false-PASS window | A | **fix**: **Fixed 2026-08-17, by the same measurement that closed #27** (filed between the sweeps; #27's row promised this row would join at the re-sweep): the pair-rule exclusion #27's measurement surfaced *outside* the plan, closed in the same change with per-case unit pins |
| ~~#165~~ | (accidental duplicate of #164) | not measured by this sweep (closed before its window) — the 2026-08-17/18 sweeps recorded no reading for this row | C | **duplicate**: **Closed 2026-08-17 as a duplicate**: a shell precedence slip in the filing command created the same issue twice; #164 is canonical The page left this row's class blank. Assigned C: an accidental duplicate carries no failure direction of its own. |
| ~~#167~~ | the text defang stops at 0x7f; raw C1 bytes pass through | not measured by this sweep (closed before its window) — reading taken by the 2026-08-17/18 sweeps: no — display hardening, outside the five surfaces | C | **fix**: **Fixed 2026-08-18 ahead of any deferral, owner decision** (filed after the 08-17 snapshot; classified at the re-sweep): one UTF-8-aware classifier behind both text-side predicates — plan review found the second, `sanitizeForReport` — C1 defanged in both encodings, invalid bytes one at a time, real multi-byte sequences spared, both routes pinned with a byte-wise mutation seen red (PR #177) Recorded on the page as class 'C-shaped', which was not one of the three values the page defined; mapped to C here and the original word kept. |
| ~~#169~~ | a world-only process boundary is tolerated with no account of that world | not measured by this sweep (closed before its window) — reading taken by the 2026-08-17/18 sweeps: yes — what a verdict means over a boundary nobody accounted for | A | **fix**: **Fixed 2026-08-18, owner decision** (filed after the 08-17 snapshot; classified at the re-sweep): refuses under `boundary_without_oracle` — the issue's own per-world analog, so the schema's closed set does not move; the world-story `processes` account precedes the refusal; the existing tolerate check inverted as the red/green pair; ADR 0002 superseded in part, its knowingly-open recording-crossed window now stated to cover the whole remaining exposure (PR #176) |
| ~~#180~~ | installing is four steps where the ecosystem's answer is one | no attributed enumerated change — release engineering, the same class as #161 | C | **fix**: Closed 2026-08-23 through an external repository (yottayoshida/homebrew-tap#58); no commit or PR in THIS repository names it. The measurement in the issue held: the shim search needed no code change. |
| ~~#181~~ | the macOS-has-no-oracle claim rested on one tool | no attributed enumerated change — a measurement of platform observers; it would add capability through channels already frozen and already accommodating it (the --oracle flag and oracle_verified) | C | **fix**: Closed 2026-08-23 (PR #285). The survey measured every candidate: no unprivileged oracle exists, SIP leaves DTrace without probes even as root, fs_usage works root-gated. |
| ~~#183~~ | criterion 1, second cohort: five targets frozen at selection | no attributed enumerated change — a cohort selection freeze, outside the five surfaces | C | **fix**: Closed 2026-08-21. Two null-with-verdicts and three walls, all under pre-frozen rules. |
| ~~#190~~ | widen the metadata exclusion to the timestamp family | no attributed enumerated change — the report prose widened from ownership/permission to name timestamps and docs/report-schema.md followed; the schema SHAPE was unchanged (metadata_writes already existed) and the closed set was untouched, so the surface diff attributes nothing here | B | **fix**: Owner-approved 2026-08-21. The issue calls its own change pre-tag-legal under the freeze's rules: a verdict-reaching behaviour change, recorded in the CHANGELOG. |
| ~~#200~~ | freeze the monotonic clock and re-ask the Borg question | no attributed enumerated change — declared apparatus around a target, outside the five surfaces | C | **fix**: Closed 2026-08-21 (PR #208). Owner scheduling ruling: before v1.0, because Borg was the only wall whose mechanism was incidental to the product. |
| ~~#209~~ | criterion 1, third cohort: sweet-spot selection frozen with bench refill | no attributed enumerated change — a cohort selection freeze, outside the five surfaces | C | **fix**: Closed 2026-08-22. The bench refill rule means the cohort cannot end in 'we could not measure'. |
| ~~#221~~ | scout model sensitivity: does the method hold with a smaller scout? | no attributed enumerated change — measures question quality, and by construction the judge never consults the scout | C | **fix**: Closed 2026-08-22. Explicitly not a verdict-soundness question. |
| ~~#231~~ | select the earliest checker-red world, not the earliest violation | measured: sc-06 — the surface diff attributes a measured change to this issue's resolution; see surface-changes.tsv for the item, the legality and the evidence | B | **fix**: Closed 2026-08-22. Added checker_earliest to the report, the one additive field this window gained, and checked it against docs/contract-freeze.md before landing it. The poetry record is the demonstration: a precision-limit L0 world structurally precedes the world where the declared checker actually breaks. |
| ~~#239~~ | the A-group UNKNOWN rate predates two cohorts | no attributed enumerated change — a published number about the engine's own development inputs; criterion 4's threshold rests on B-group data, which this does not touch | C | **fix**: Closed 2026-08-26 (PR #346). Settled 'runnable' in writing before the sweep ran, which is the order that keeps the answer from being chosen after seeing its effect. |
| ~~#240~~ | criterion 3's kill-criteria review predates two cohorts | no attributed enumerated change — a scoring judgement about kill criteria, outside the five surfaces | C | **fix**: Closed 2026-08-27 (PR #362). Re-scored row by row with the previous verdict quoted beside the new one; two rows reopened and were adjudicated. |
| ~~#244~~ | the shim cannot see Rust std's fs::copy, and the libc-bypass class has three mechanisms | measured: sc-07 — the surface diff attributes a measured change to this issue's resolution; see surface-changes.tsv for the item, the legality and the evidence | A | **fix**: Closed 2026-08-26 (PR #332). Exporting the weak-lookup symbols was sufficient for a whole class of Rust tools; the bump to v11 is the declared-not-a-break kind. Class A because a write the shim cannot see is a PASS-side hole wherever no oracle refuses it. |
| ~~#256~~ | the shim omits three wrappers the oracle already classifies | measured: sc-07 — the surface diff attributes a measured change to this issue's resolution; see surface-changes.tsv for the item, the legality and the evidence | A | **fix**: Closed 2026-08-26 (PR #332). renameat2, pwritev, pwritev2 — real glibc symbols that were simply never written. Same bump as #244. |
| ~~#264~~ | a failed waitpid decodes as exit 0: the wrong-reason path was shipped | measured: sc-01 — the surface diff attributes a measured change to this issue's resolution; see surface-changes.tsv for the item, the legality and the evidence | A | **fix**: Closed 2026-08-24 (PR #294). Eight consecutive failures produced a confident wrong reason; the fix refuses with child_wait_failed instead, which is why the closed set gained a member. |
| ~~#265~~ | snapshot reads whole files with no size cap | no attributed enumerated change — the cap landed as a SETUP_ERROR at the initial snapshot, which needed no new vocabulary; the post-recording sites are #330's row | B | **fix**: Closed 2026-08-25 (PR #322). The one unbounded read in the engine, over target-controlled data, hundreds of times per explore. |
| ~~#266~~ | MCP replay trusts define.state inside the case file | no attributed enumerated change — the confinement changed which states a replay may name, which is MCP behaviour rather than the frozen tool names, input schemas or isError rule | D | **fix**: Closed 2026-08-25 (PR #322). Scoped close: what closed is the accident and received-case class. The residue is tracked in #328 rather than re-litigated inside a closed issue. |
| ~~#267~~ | assertSafeRoot accepts any absolute path two slashes deep | no attributed enumerated change — a guard in front of deleteTree; no frozen surface | D | **fix**: Closed 2026-08-25 (PR #315). /var/lib, /usr/local and /home/user all passed the only guard in front of a delete that runs once per explored world. |
| ~~#268~~ | the default work dir is one fixed world-writable path | no attributed enumerated change — a default path and open flags; no frozen surface | D | **fix**: Closed 2026-08-25 (PR #316). The MCP side had already met this shape and fixed it for itself; the general case had not. |
| ~~#269~~ | the MCP server has no parent-death cleanup | measured: sc-02 — the surface diff attributes a measured change to this issue's resolution; see surface-changes.tsv for the item, the legality and the evidence | C | **fix**: Closed 2026-08-25 (PR #317). An agent host restarts servers routinely, so orphaned explores happen at some background rate. The stop needed a reason of its own, which is why the closed set gained parent_exited. |
| ~~#270~~ | the numbering-assert wiring has no live acceptance coverage | no attributed enumerated change — acceptance coverage of an internal assert; no frozen surface | C | **fix**: Closed 2026-08-25 (PR #322). The recorded both-asserts-off mutant survived the suite; a second net no test can reach is indistinguishable from dead code. |
| ~~#271~~ | upstream-report-status.sh cannot fail: the BROKEN counter dies in a subshell | no attributed enumerated change — spike tooling, outside the five surfaces | B | **fix**: Closed 2026-08-24 (PR #294). A table whose every row was BROKEN exited 0 under a header promising 'Exit 0 measured'. The list half stayed open as #297. |
| ~~#273~~ | --help is not a word the CLI knows, and the usage text drifted from the parser | measured: sc-09 sc-12 — the surface diff attributes a measured change to this issue's resolution; see surface-changes.tsv for the item, the legality and the evidence | C | **fix**: Closed 2026-08-24 (PR #294). This is the row that proves an enumerated diff is not a measurement of surface 3: the ExitCode enum never moved, and the declaration was rewritten in the same commit to state the promise as a one-way verdict-to-code mapping. |
| ~~#277~~ | top-level docs lag the record | no attributed enumerated change — documentation currency, outside the five surfaces | C | **fix**: Closed 2026-08-23 (PR #283). The same page had been backfilled the day before and drifted again within a day, which is why the issue asks for a checklist hook rather than a bigger backfill. |
| ~~#278~~ | the README never routes a skeptic to the denominators | no attributed enumerated change — documentation navigation, outside the five surfaces | C | **fix**: Closed 2026-08-23 (PR #283, squash-merged as c16501b). Four rows added, including one to this audit page, plus the standing-value section the issue held open. |
| ~~#281~~ | this re-sweep, and the standing obligation that the audit is a gate rather than a ceremony | no attributed enumerated change — the audit's own obligation issue, the same shape #86 had: recording a sweep is not touching a surface | C | **fix**: Closed by this merge. What it asked for is the sweep this manifest is: the snapshot replaced, every issue opened or closed since the last one classified, and the resolved accounting enumerated by a closed-issue query rather than recalled. |
| ~~#292~~ | spike/macos-oracle/ is not registered in .gitattributes, and the rule has been missed twice | no attributed enumerated change — repository metadata, outside the five surfaces | C | **fix**: Closed 2026-08-25. Two misses out of two closures is the shape of a rule that needs a check rather than more emphasis; the issue records deciding not to add one as a legitimate answer with a sunset note. |
| ~~#295~~ | the synopsis check covers two directions of three | no attributed enumerated change — acceptance coverage of the parser-versus-usage pair; no frozen surface | C | **fix**: Closed 2026-08-25. The unchecked direction is the one that actually drifted before #273. |
| ~~#296~~ | sideeye explore --help is a SETUP ERROR: help is answered before the mode word | measured: sc-10 — the surface diff attributes a measured change to this issue's resolution; see surface-changes.tsv for the item, the legality and the evidence | C | **fix**: Closed 2026-08-25. The second movement of the exit-code surface's behavioural half in this window, and equally invisible to an enumerated diff. |
| ~~#305~~ | a fix that changes the operation sequence orphans its own case | no attributed enumerated change — surface 4 promises exactly this refusal (case_no_longer_applies when the code changed underneath), so the promise is kept, not moved; what the issue questions is a criterion's bar | C | **fix**: Closed 2026-08-25 (PR #319). Structural, and stated without overreaching: a case pins a crash point inside a recorded sequence, so any fix that changes that sequence orphans it. How common such fixes are is explicitly not claimed — n is two. |
| ~~#306~~ | the himalaya guard states a premise the upstream fix falsified, and it is committed twice | no attributed enumerated change — a committed checker's message text, outside the five surfaces | B | **fix**: Closed 2026-08-25. Found by scanning the class across all 18 committed cohort checkers: 18 hits in 6 files, two falsified, eight measured still true, one unmeasured and named as such. |
| ~~#320~~ | the report-schema surface has no additive rule: whether a new field is breaking is a reading | measured: sc-11 — the surface diff attributes a measured change to this issue's resolution; see surface-changes.tsv for the item, the legality and the evidence | C | **fix**: Closed 2026-08-26 (PR #334). This is the row that makes the yardstick's motion visible: the rule most of this sweep's readings lean on was written INSIDE the window being audited, and did not exist when the snapshot being replaced was taken. |
| ~~#324~~ | readTrace is the other uncapped read, and capping it naively would relabel the failure | measured: sc-03 — the surface diff attributes a measured change to this issue's resolution; see surface-changes.tsv for the item, the legality and the evidence | B | **fix**: Closed 2026-08-26 (PR #334). The issue whose body names neither unknown_reason nor the closed set while its resolution added trace_too_large to that set. It is the measured reason this audit stopped deciding surfaces by reading issues. |
| ~~#326~~ | the MCP tool result relays target-controlled report text into the agent's context | no attributed enumerated change — marking the target-derived region changed the text block's content, not the frozen tool names, input schemas or isError rule | D | **fix**: Closed 2026-08-26. Escaping already prevented breaking the transport; what passed through untouched was the MEANING. The salience half became #336 and the shrink-the-channel half #337. |
| ~~#327~~ | hold the destructive root by descriptor | no attributed enumerated change — an internal change to how the destructive walk addresses the root; no frozen surface | D | **fix**: Closed 2026-08-26. Under #266's threat model the swap window was not a one-shot race: restore runs once per world, so the attacker owns the retry count. |
| ~~#329~~ | should the naming root be subject to the depth rule? | no attributed enumerated change — the startup vet's predicate; no frozen surface | D | **fix**: Closed 2026-08-27. The depth rule refused every single-component root, which is the ordinary shape of a container mount the README recommends. Resolved by vetting distance from danger rather than depth. |
| ~~#330~~ | a post-recording cap breach reports exit 3 though exploration began | measured: sc-04 — the surface diff attributes a measured change to this issue's resolution; see surface-changes.tsv for the item, the legality and the evidence | B | **fix**: Closed 2026-08-26. Exit 3 means the define did not run; here exploration had begun. The same shape #264 refused for wait failures, and it cost a closed-set member for the same reason. |
| ~~#333~~ | macOS copies through fcopyfile, which v11 does not interpose | measured: sc-08 — the surface diff attributes a measured change to this issue's resolution; see surface-changes.tsv for the item, the legality and the evidence | A | **fix**: Closed 2026-08-26. Class A on the platform where it costs most: SIP leaves no usable oracle, so a write the shim cannot see is refused by nothing. The bump to v12 is the declared-not-a-break kind. |
| ~~#336~~ | the provenance advisory is read once at tools/list, not when a region is present | no attributed enumerated change — the advisory is emitted in the result text; the frozen tool names, input schemas and isError rule are untouched | D | **fix**: Closed 2026-08-26. #326's precision argument was correct about a different goal; salience at the moment of consumption is satisfied by one conditional. |
| ~~#351~~ | a post-recording snapshot failure that is not the cap still says the define did not run | measured: sc-05 — the surface diff attributes a measured change to this issue's resolution; see surface-changes.tsv for the item, the legality and the evidence | B | **fix**: Closed 2026-08-27. Owner ruling recorded in the issue: add state_unsnapshotable to the closed set before the tag. Six error values behind one member, with the message separating them. |
| ~~#353~~ | the audit's post-snapshot section has aged past four frozen-surface issues | no attributed enumerated change — the audit's own obligation issue, the same shape as #86 and #281 | C | **fix**: Closed by this merge. Its own text says the fix is a re-sweep rather than an edit, and it was right about more than it knew: the window held five closed-set additions rather than the four issues it named, and two of those five were counted by nobody until this sweep measured the enum. |
| ~~#358~~ | the predicate that deletes and the one that names read outward differently | no attributed enumerated change — an internal predicate alignment; no frozen surface | D | **fix**: Closed 2026-08-27 (main 4655363). Landed while this sweep was being measured, which is why this manifest sits on top of it. |
| ~~#369~~ | rung 3's residue has no clause-to-check map: 'held by a check' and 'held by nobody' read the same | no attributed enumerated change — an audit-instrumentation gap; the resolution adds a manifest and changes what rung 3 prints, touching no frozen surface | C | **fix**: Resolved by clause-checks.tsv: every clause of the declaration now names the check that pins it or records that nothing does, and rung 3 prints only the unpinned rows and the leftover half of partial ones. 29 clauses — 10 pinned, 8 partial, 11 unpinned. The `by` column names a suite and a heading, not a check id (two ids are duplicated in acceptance.sh), and rung 3 fails when a named heading is gone. No new acceptance check is added: #369 rules that out, since a change that polices checks cannot also supply them without making a mutation unattributable. Completeness of the enumeration stays unmeasured and says so — measured, not theoretical: the file shipped at 26 rows and a second reader walking the declaration against it found three normative clauses with no row at all (the keys and the accepted set staying the same list, sc-18's legality reading freeze-broken, contract_version_mismatch being a different refusal from a saved case's) plus one row naming a check that drives half its clause. No gate went red on any of the four. |
| ~~#375~~ | state_tree_too_large reports what it read, not what the tree holds | no attributed enumerated change — reading taken by the fourth sweep, 2026-08-29: no — refusal-message detail inside an existing member; the member, the verdict and the exit are unchanged by any resolution the issue entertained | C | **document**: ~~defer~~ **Closed 2026-08-29 as documented**: the adjudication already lives in `docs/adr/0029-the-snapshot-caps-what-holding-the-tree-costs.md` (the section rejecting an accounting-only continuation on four measurements), which ends by filing contributor-naming separately, to be built if operators ask. The issue and that section carried the same ruling and the ADR is the durable half. The refusal already names the two commands that answer the question exactly. Closed as documented, not as fixed; an operator asking reopens it |
<!-- END generated: freeze-audit resolved rows -->

## What remains before the tag

1. ~~The adjudicated fixes~~ — done: #46's observation and #5's demotion both
   landed 2026-08-17 (#27 left this list the same day, measured already-fixed;
   each row above carries its record).
2. ~~The target-classes narrowing for #10~~ — done: landed 2026-08-18, wider
   than the docs-only adjudication (the report's macOS clause and a CI pin
   came with it; #39's narrowing executed 2026-08-17, #150's relabel landed
   2026-08-18 on both verdict headlines — each row above carries its record).
3. ~~Re-run the sweep~~ — done 2026-08-18: snapshot replaced (13 issues,
   gate path moved in the same commit), the four issues filed and resolved
   between the sweeps accounted (#169 class A, fixed — the world-only
   boundary refusal; #167, fixed — the UTF-8 defang; #164, fixed 2026-08-17
   with #27's measurement; #165, its duplicate) with #159's held call
   resolved alongside, resolved rows struck, gate re-run green
   with the strike separation seen red once.
4. ~~Re-run the sweep again~~ — done 2026-08-27, third sweep: snapshot
   replaced (55 issues, gate path and declaration pin moved in the same
   commit), thirty-eight issues filed and resolved inside the window
   accounted by a closed-issue query, seventeen historical rows migrated into
   the manifest, and the five surfaces measured rather than read for the first
   time.
5. ~~Re-run before the tag~~ — done 2026-08-29, fourth sweep: snapshot
   replaced (56 issues), zero issues opened-and-closed inside the window, the
   three foreclosed pre-tag decisions all landed and measured into the ledger
   before the sweep ran (sc-14..sc-17), and the declaration byte-identical
   across the window.

**The list is empty again.** The third sweep put three items on it — the
first sweeps to end with it non-empty — and all three resolved inside this
window, each decision taken and landed *before* the tag, which is the only
order the closed set's exemption from the additive allowance permits:

1. **`#263`** — resolved as a new member: `child_timed_out`, behind
   `--world-timeout` (off by default, worlds only). Landed 2026-08-28
   (sc-17); the issue stays open on its stdin question, which reuses nothing
   frozen and carries no deadline.
2. **`#323`** — resolved as a new member: `state_tree_too_large`, the owner
   ruling for a name over riding on `state_unsnapshotable` because a failure
   with a limit reports its limit. Landed 2026-08-27 (sc-14).
3. **`#363`** — resolved on both of its own branches: one new member,
   `state_rewrite_failed`, for the engine's own rewrite failures after the
   define has run (sc-15), and three exit paths moved 3 → 2 under the
   declaration's existing clause (sc-16). The five apparatus reads stay
   exit 3 by the adjudication recorded on the issue. Landed 2026-08-28.

Every landing was measured into `surface-changes.tsv` through the gate's own
drift path when it happened, not recorded by this sweep after the fact.
**Criterion 5's status is the owner's call given this record**, recorded in
`PRD.md` with its date, not adjusted here.

The standing obligation is unchanged and never leaves the list: whatever is
filed between now and the tag gets swept and classified before the tag, however
many times that takes. "Criterion 5 is met" is a statement about the audit that
ran, not a promise that the tracker stopped moving — the third sweep measured
eighty-three issues moved in nine days; this window, seventeen in two.

**The last-moment check is mechanical, and since this sweep it is achievable**:
`sh spike/freeze-audit/check-freeze-audit.sh --live` asks the tracker whether
every snapshot issue still open has an active row and every one now closed has
a resolved row, refuses a query that could have been truncated, and exits 3 on
any drift. Run it immediately before the tag and require it green.

The predicate had to change for that instruction to mean anything. The previous
one — "the snapshot IS the tracker's open set" — went false one second after the
snapshot it was written for was committed, because that sweep's own obligation
issue closed with the same merge. Green was reachable for an instant and never
again, so requiring it before the tag was requiring the impossible. Under the
new predicate a sweep that closes its own issues and records them as resolved
stays green, which is the state this page ships in.

There is still no committed tag procedure to hook this into — the ceremony lives
in `.github/workflows/release.yml`'s header comment and runs *after* the tag is
published — so the obligation is recorded here, on the page whose gate it is.
A surface can also move after a sweep without any issue changing state, which
`--live` structurally cannot see — it asks about issues. **The offline gate now
asks about surfaces**: it pins the `src/contract.zig` revision this sweep measured
and reports any later movement of the closed set as drift, exit 3, after every
other leg has passed so a stale audit never masks a malformed one. Both directions
were seen red before shipping — the addition side against a synthetic blob
carrying the very member a peer session's unmerged work will add, which is
therefore the first firing this leg is expected to have. The declaration's permanent
home is [`docs/contract-freeze.md`](contract-freeze.md) — the freeze survives
this page's retirement at the tag.

#26 and #35 resolve as "document", and their rows above *are* the record —
no further page is owed.

Also retired by the 2026-08-18 sweep: `src/main.zig`'s preflight refusal
promised a machine-readable form "arriving with issue #84" — a future that had
already happened without it. The text states the standing constraint instead.
