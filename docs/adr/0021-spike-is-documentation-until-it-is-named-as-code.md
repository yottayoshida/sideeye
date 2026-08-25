# 0021. Everything under spike/ is documentation until it is named as code

Date: 2026-08-25
Status: Proposed

## Context

`.gitattributes` exists because counting the apparatus once made Shell
the repository's largest language at 52%, ahead of the engine it exists
to test. The fix was to mark closed records `linguist-documentation`,
which drops a path from the language bar without collapsing its diffs.

The rule that carried it read: *a closed cohort belongs here; add its
directory when it closes.* It was written at the top of the file it
governs, and it was missed on every closure it ever faced.

- Cohort 4 closed without it. Recorded in the file's own prose.
- `spike/macos-oracle/` closed with PR #285 (`#181`) without it.
- `spike/scout-model-comparison/` (`#221`) closed without it.

`#292` filed the second of those and diagnosed the class correctly:
*nothing opens that file at the moment a record closes, so the rule
depends on remembering it.* Measuring the tree while planning the fix
found the third, which `#292` had not noticed — three misses out of
three closures, not two.

Two things were measured before choosing a direction.

**A content predicate cannot replace the rule.** Three candidates were
run over all 20 directories under `spike/`: "has a committed transcript"
disagreed with the current registration on 6, "is not referenced by live
code" on 6, and their conjunction on 10. The reason the second fails is
specific and instructive: four registered records *are* referenced by
live code, for four different reasons — `check-sealed-campaigns.sh`
checks one, `rehearse-campaign.sh` drives another, `acceptance.sh`
consumes a third, and `spike-fsusage.yml` re-runs a fourth. No single
predicate separates "a record that something still reads" from "an
apparatus that is still maintained".

**The third state hid the misses.** Before this change, 62 tracked files
came back `unspecified`. 35 of them were the bug (the two unregistered
records) and 27 were correct (22 top-level scripts and `spike/toys/`,
which must count as code). A decision and an omission carried the same
attribute value, so nothing could be asserted about either — not that
the value was harmless, but that it was silent.

## Decision

Invert the default. Position carries the classification:

    spike/**        linguist-documentation
    spike/*        -linguist-documentation
    spike/toys/**  -linguist-documentation

A record is documentation from the day its directory is created, so
there is no closing moment to notice. A new top-level script is code
automatically, because the maintained harness lives at the top level.

`spike/check-gitattributes.sh` holds the arrangement by reading the
attribute rather than the text of `.gitattributes`, over every tracked
file rather than a sample. `unspecified` becomes a failure, which is
only assertable because the inversion leaves none.

## Alternatives Considered

**Keep the rule and add a check for "is this record closed".** Rejected
on the measurement above: no content predicate reproduces the current
classification, and the four live-reference reasons show why one is
unlikely to exist.

**Require every directory to be classified in one of two lists.** This
was the first draft, and it is wrong for a reason worth recording: a
directory created as live and later closed never changes the lists, so
the check stays green forever. It would have verified that somebody
classified a directory *when it was created* — not the predicate `#292`
is about, and the same accident would reproduce unchanged.

## Consequences

**The misclassification this direction can produce is a new live
directory left as documentation.** `spike/toys/` is the only such
directory today, and a second one has to be named in two places — this
file's pattern list and the checker's `exempt_dirs`. Naming it in only
one fails loudly from either side: a directory unset in `.gitattributes`
but missing from `exempt_dirs` fails as a record that came back `unset`,
and a stale literal in `exempt_dirs` fails as an exemption that matched
nothing.

**Naming it in neither is green, and the check cannot see it.** A live
directory omitted from both places is documentation by default and the
check expects documentation, so the two agree. That is this decision's
cost, paid knowingly: it is the accepted misclassification above, not a
gap in the checker. Saying the check "forces the decision" would be
false, and the first draft of the checker's header said exactly that.

**That misclassification is the safer one.** It understates Shell rather
than counting a frozen transcript as code, and it happens while somebody
is working in that directory rather than as they walk away from it. The
closure direction has three observed misses; this direction has none
yet, and its first will arrive with a person's attention already on it.

**35 files change meaning; 27 change only their label.**
`spike/macos-oracle/` (9) and `spike/scout-model-comparison/` (26) become
documentation. The 27 that were `unspecified` and correct become an
explicit `unset`. Nothing else in the tree moves, and the check reports
the counts on every run so the next change to this file says what it did.

Those two states are not equivalent, which an earlier draft of this
section got wrong. `unspecified` leaves linguist's own documentation
heuristics in charge of a path; `unset` overrides them to false. Of the
27, the one those heuristics do claim is `spike/README.md`, which moves
from documentation to explicitly-not-documentation. It still leaves the
bar unchanged, but for a different reason — Markdown's type is `prose`,
and the bar counts `programming` and `markup`. The same reason covers
`spike/timew-undo-ordering.patch`, whose Diff type is `data`; an earlier
draft attributed that one to the documentation heuristics too, which do
not match it. Both steps are read from linguist's documented behaviour,
not measured here; what was measured is which files move and to what.
