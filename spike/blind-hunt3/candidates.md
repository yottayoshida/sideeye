# Campaign 3 candidates, in priority order — inherited from campaign 2's Seal A (ADR 0016)

This list is **frozen**, and its provenance is two removals deep: campaign 1's
sealed candidate list (frozen at `217ec4f` before any candidate had been
installed or executed) minus topydo (consumed by campaign 1), minus khard
(burned before campaign 2's Seal B — a breach, not consumption; ledger and
PR #110) and abook (consumed by campaign 2's exploration, null result).
Nothing is appended, nothing is reordered, and the selection predicate is
unchanged (ADR 0012 decision 2, inherited per ADR 0015 and ADR 0016).

These remain **high-risk blind targets**: file-backed state chosen on purpose
from web documentation. This campaign is *not* the §18 average-target
calibration — that stands on timewarrior (2026-08-12) — and the report must
not claim otherwise.

Eligibility, read from docs alone at campaign 1's Seal A: neither candidate
advertises crash-injection testing in its documentation.

| # | Target | Install (pinned since campaign 1) | State, per its own documentation |
|---|--------|-----------------------------------|----------------------------------|
| 1 | **khal** | pip `khal==0.14.0` | vdir directories of iCalendar files |
| 2 | **hledger** | apt 1.25-2 (bookworm) | a plain-text journal, appended to |

What the repository records as consulted or observed for these two beyond web
docs (everything ledger-recorded under the prior campaigns' rules): their
`--help` output, minimal-config formats from their readthedocs pages, one
normal (non-crash) run each, and two sweeps' verdicts — **exit codes only**
(khal accepted in both; hledger refused in both, its refusal reason sealed
and unread to this day). No *recorded* contact involves traces, crash
behavior, source, or bug trackers; the record is self-reported, and ADR
0012's honesty bounds carry unchanged.

**Pre-registered risk, not a predicate change** (ADR 0015 §1, carried): the
campaign-1 normal run observed khal's `new` creating **a randomly named
`.ics`**. If that shape defeats the byte-reproducible baseline at exploration
time, the exploration refuses and the refusal is the campaign's recorded
result — it is not a reason to reorder this list.

**Pre-registered disclosure duty** (carried verbatim from campaign 2's seal):
khal shares the vdir/iCalendar storage class with todoman, which this project
has explored. If khal is selected, **the report must say so**.

## Taint ledger — targets excluded because this project already read their internals

timewarrior · taskwarrior · git · todoman · watson · jrnl · omamori ·
**topydo** (campaign 1: crash worlds explored, state bytes read, bug tracker
searched) · **khard** (campaign 2: burned — its failure output on a
mis-shaped store was observed pre-seal; post-burn its declaration history is
public) · **abook** (campaign 2: crash worlds explored, reports read).

**Carried-over class knowledge is declared, not denied.** From those targets
this project knows the general shapes — the window between renames of related
files, the temp-write-then-rename idiom, journals that must stay a prefix of
themselves, the in-place rewrite whose interruption empties the file, the
backup store whose state-matching can misfire after a crash, and (campaign 2)
the refusal path explored as an `expected_status` operation. That knowledge
informs *what kinds of invariant are worth declaring*; the bar stays
target-specific internals, and that is what this ledger keeps out.
