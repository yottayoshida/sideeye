# 0078 — The repeated authoring cost is the judged set, and Sideeye reports it rather than inferring it

Status: Accepted (2026-09-19)

## Context

#618 asked how much of a target's own semantics a person must supply before a Sideeye question
is trustworthy, and required the answer to be measured before any feature was chosen. Four
targets were authored under a sealed protocol (ADR 0077) and graded by two fresh graders each:
`dos2unix`, `genisoimage`, `lmdb-utils`, `fossil`. The figures are in
`spike/authoring-cost/RESULTS.md`; the evidence is each run's committed transcript and
snapshots.

The issue named four possible outcomes — better diagnostics, a define scaffold, checker
templates, a `sideeye init` surface, suggestions emitted from preflight/explore — and explicitly
allowed a fifth: that no removable repeated cost was measured.

What the runs show is a sequence of **judged sets**: which paths under the state root the
built-in byte pre-or-post rule was applied to. Counted from the records: the judged set **moved**
in three of the four runs (`genisoimage` once, `fossil` twice, `lmdb-utils` three times;
`dos2unix-measured` never), and the judged **count** fell in two of them — `genisoimage`'s stayed
at 14 while a path moved out to `scratch`. `lmdb-utils` went
`2 → 1 (scratch lock.mdb) → 2 → 1 (scratch data.mdb)` — a round trip that ends on a define
judging the one file its own subject had already identified, in writing, as non-durable.

That subject did not lack the semantics. It had them in four minutes. What it lacked was any
handle on the set it was currently judging: the engine reports `N path(s) judged pre-or-post`
and a FAIL names only the path that broke. `lock.mdb` never broke, so nothing ever named it.

## Decision

**The repeated authoring cost is updating the judged set, and the part Sideeye can remove is
reporting it — not deciding it.**

Deciding what belongs in the judged set is the target's semantics and stays with the author.
Reporting what the engine has already decided is bookkeeping, and bookkeeping is what a tool can
carry. The judged set is therefore to be reported as data — a new optional field in the JSON
report — filed as its own issue with `lmdb-utils`'s `07:49:50` state as the acceptance case.

**It is filed, not built here.** #618's sixth condition asks for a follow-up feature to be
*filed from* the evidence with an acceptance case drawn from the measured failure mode. A merge
that both concludes "this is the repeated cost" and ships the feature answering it leaves no way
to tell a finding from a justification written alongside the thing it justifies.

**The summary sentence does not change.** `buildL0Note` names files deliberately sparingly —
"Names are bounded — the point is 'which files got the weaker claim', not an inventory"
(`src/report.zig`, ADR 0004) — and it caps names at three. Reversing that would not even solve
the motivating case: `genisoimage` judged 14 paths. The report's JSON is a different surface,
and the freeze's additive allowance for surface 2 has carried new optional fields four times
(`scratch`, `setup_error_reason`, `earliest.recovery`, `paths_attributed_to_rename`).

**But this is an extension of that policy, not a precedent already set.** `scratch` echoes a
declaration the user wrote, so its length is bounded by the define. A judged set is bounded by
the state tree, which can be thousands of paths. The issue carries that as an open question
rather than assuming the answer; it also carries that `spike/check-report-schema.py` holds the
schema in both directions, so the field lands there or not at all.

## Alternatives considered

| rejected | why |
|---|---|
| **`sideeye init` / a define scaffold** | A scaffold has to guess what is durable. Every run's deciding card line was exactly that question, and `dos2unix`'s split shows the two graders disagreeing about one target's answer. A scaffold would encode one reading as the default and make a wrong question the path of least resistance — the failure #618 says is worse than setup friction. |
| **Checker generation / templates** | The rubric's `vacuous checker` verdict could not be reached this round, so this study measured nothing about checker quality. Building for it would be building on an unmeasured problem, which is the thing #618 exists to prevent. |
| **Scratch inference** | Inferring scratch is inferring the contract. `lmdb-utils`'s `lock.mdb` and `fossil`'s `.fslckout` are both rebuildable-but-load-bearing in ways only the target's own documentation settles, and `dos2unix`'s leftover temporary is a case the card marks `unspecified` — the answer key itself declines to answer it. |
| **Naming the judged paths in the summary line** | Reverses ADR 0004 and is capped at three names; `genisoimage` judged 14. |
| **Concluding that no repeated cost was measured** | Defensible on n=4 with one run unchanged, and it was put to the owner as the alternative reading. Rejected because the mechanism is visible in three independent runs and is not target-specific: the three move their judged set for different reasons, and the one that never moved it is the one the graders could not agree about. |

## Consequences

- The study's primary count changes from revisions to judged states. `PROTOCOL.md`,
  `audit.py`'s docstring and `runs/README.md` each carried the old claim and each is corrected;
  the protocol change is a dated amendment with its own ledger row and pre-image.
- `audit.py` refuses a run whose record does not carry its judged-set sequence, or carries one
  its transcript does not support. This implements a refusal `watch-defines.py`'s docstring had
  promised since the apparatus was written and which nothing had ever performed — five published
  runs passed in silence before it existed.
- Two issues are filed (#638, #639). A third was planned — the watcher's blindness to a
  define handed to the engine on the command line — and dropped: its docstring declares it,
  this merge implements the refusal that docstring promised and publishes the states, and
  what remains is the grading half, which #639 carries. The engine is untouched by this merge.
- **What this does not settle**: whether reporting the judged set actually removes the cost. The
  measurement here is of a subject that could not see the set; whether a subject that can see it
  writes the define correctly is a second experiment, and the issue says so rather than assuming
  its own acceptance case is sufficient.
