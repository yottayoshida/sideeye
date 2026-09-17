# 0071 — The evidence a FAIL measured lives beside the case, not inside it

Status: Accepted (2026-09-17)

## Context

A saved case is what makes a counterexample durable: the define, the crash point and the
landing context a later replay re-asks (ADR 0009). What it does not carry is what the run
*saw* — which paths differed between the pre-operation state, the completed state and the
crashed one, whether a damaged path existed before, whether its old bytes survive anywhere
else, what the checker said. #607 asks for that, rendered for a maintainer who has never used
Sideeye, because the 2026-09-16 runs found the same shape in seven languages and only two of
them were reported upstream: the translation from a technically valid counterexample to
evidence somebody else can act on was the bottleneck, not the search.

Two things about the code decided the shape of the answer before any preference did.

**The crashed state exists for one iteration.** It is snapshotted inside the world loop and
freed by that iteration's own `defer crashed.deinit()`, and the state directory is restored
before the next world runs. There is no later point — not the report phase, not a separate
command, not a replay — at which it can be compared against the pre and post snapshots. A
measurement that does not happen at the branch which records the exhibit cannot happen at all.

**A case's version is tied to its shape.** `docs/contract-freeze.md` surface 4 promises that
a saved case replays across 1.x or refuses honestly, and the mechanism is a version ladder:
3 for the argv command form, 4 for `cwd`, 5 for `scratch`. Every rung is a *define* field —
part of the question the replay re-asks. A case written at a version is refused by any reader
below it, which is what makes the ladder honest.

## Decision

The measurement happens in the world loop, at the branch that latches each exhibit, and its
result is written to **`<work>/cases/NNNNNN.evidence.json`** — a separate file beside the
case, carrying its own `evidence_version`, parsed strictly the way `ReplayCase` is. The case
file is unchanged.

`sideeye evidence <case.json>` renders that file as Markdown. Its input is the two artifacts
and nothing else: it starts no process, reads no state directory, and parses none of
Sideeye's own rendered prose.

The report names the bundle in an `evidence` field beside `case` and `replay`, and in
`checker_earliest.evidence` for the claim exhibit — additive under the allowance surface 2
keeps open — rather than leaving a consumer to derive one name from the other.

A bundle is written only once its case was written, and is named from that case's id, so it
claims no id of its own.

## Alternatives considered

**Add the fields to the case file (case_version 6).** Rejected. Two costs, both structural
rather than stylistic. First, no case this release wrote would replay on any earlier 1.x —
every FAIL, including those whose defines are identical to ones a v5 reader handles today.
Second, the ladder would begin moving for reasons that have nothing to do with the question:
each later evidence field would push every case up a rung. The version ladder is a promise
about *questions*, and an observation is not one.

**Put the fields in the report JSON only.** Rejected. The report is written only when
`--json` names a path, so the bundle would exist for some FAILs and not others, and #607 asks
for something renderable from a saved FAIL. The report does name the bundle, which is the
part of this alternative worth keeping.

**Render the bundle at FAIL time instead of offering a command.** Rejected, though it is
the cheaper half: the measurement is the part that cannot be added later, and a reviewer
recommended shipping only that if the change grew too large. Acceptance 1 of #607 asks for a
command, and the objection that motivated the advice — `src/main.zig` sitting at the
declaration ceiling `spike/check-main-shape.sh` holds it to — is answered by putting the
implementation in `src/evidence.zig`, which is where the behaviour belongs anyway.

**Report a severity.** Rejected by the issue and kept rejected here. Sideeye does not know
what a file is for. The bundle carries the objective fields a maintainer needs instead —
whether the path existed before, whether its old bytes survive elsewhere, whether the define
declared it scratch, whether the checker failed — and a `--format json` was dropped for a
related reason: the machine-readable form is the bundle file itself.

## Consequences

- A FAIL writes one more small file per saved case. A write failure loses the bundle and
  nothing else: the report says `-` on its `evidence` line, and the verdict, the case and the
  replay command are unaffected.
- The declared checker's output in each explored world is now captured to
  `<work>/checker-output.txt` rather than inherited by the terminal, so the exhibit's last
  line can be quoted. This follows `--setup`'s capture (#483) and removes the unlabeled
  per-world checker output #134 records as a hazard. A capture that cannot be opened leaves
  the diagnostic unreadable and does not refuse the run — an attachment must not turn a FAIL
  into an UNKNOWN.
- `evidence_version` can move without touching `case_version`, and #606's recovery result
  has a slot held open from version 1 (`"recovery": {"result": "not_configured"}`, a string
  rather than an enum) so adding it is a value change rather than a schema change.
- The bundle's `invariant`, `subject` and `observed` are carried across from the same values
  the report prints rather than re-rendered, so the two cannot disagree; an acceptance check
  holds them to the report's `earliest` by bytes.
- What the bundle can say is bounded by what the run snapshotted. "Old bytes elsewhere"
  searches the judged state directory's regular files only, and answers `unknown` where a
  recorded `rename` brought a subtree in from outside it. `docs/evidence.md` states both.
