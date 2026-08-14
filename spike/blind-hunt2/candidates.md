# Campaign 2 candidates, in priority order — inherited from campaign 1's Seal A (ADR 0015)

This list is **frozen**, and it was frozen on 2026-08-13: it is campaign 1's sealed
candidate list (`spike/blind-hunt/candidates.md`, sealed at `217ec4f` before any
candidate had been installed or executed) with exactly one removal — topydo, consumed
by campaign 1 and now fully sighted. Nothing is appended, nothing is reordered, and
the selection predicate is unchanged (ADR 0012 decision 2, inherited per ADR 0015).

These remain **high-risk blind targets**: file-backed state chosen on purpose from
web documentation, several spanning more than one file, abook and hledger as
single-file counterweights. This campaign is *not* the §18 average-target
calibration — that stands on timewarrior (2026-08-12) — and the report must not
claim otherwise.

Eligibility, read from docs alone at campaign 1's Seal A: none of the four
advertises crash-injection testing in its documentation.

| # | Target | Install (pinned since campaign 1) | State, per its own documentation |
|---|--------|-----------------------------------|----------------------------------|
| 1 | **khard** | pip `khard==0.21.0` | vCard files, one per contact |
| 2 | **abook** | apt 0.6.1-2 (bookworm) | a single text address book |
| 3 | **khal** | pip `khal==0.14.0` | vdir directories of iCalendar files |
| 4 | **hledger** | apt 1.25-2 (bookworm) | a plain-text journal, appended to |

What the repository records as consulted or observed for these four beyond web
docs (everything ledger-recorded under campaign 1's rules): their `--help`
output, minimal-config formats from their readthedocs pages, one normal
(non-crash) run each, and the campaign-1 sweep verdicts — **exit codes only**
(khard/abook/khal accepted; hledger refused, its refusal reason sealed and
unread to this day). No *recorded* contact involves traces, crash behavior,
source, or bug trackers; the record is self-reported, and ADR 0012's honesty
bounds carry unchanged.

**Pre-registered risk, not a predicate change** (ADR 0015 §1): campaign 1's normal
runs showed khard minting randomly named files per contact. If that shape defeats
the byte-reproducible baseline at exploration time, the exploration refuses and the
refusal is the campaign's recorded result — it is not a reason to reorder this list.

## Taint ledger — targets excluded because this project already read their internals

timewarrior · taskwarrior · git · todoman · watson · jrnl · omamori · **topydo**
(campaign 1: crash worlds explored, state bytes read, bug tracker searched).

**Carried-over class knowledge is declared, not denied.** From those targets this
project knows the general shapes — the window between renames of related files, the
temp-write-then-rename idiom, journals that must stay a prefix of themselves, the
in-place rewrite whose interruption empties the file, and the backup store whose
state-matching can misfire after a crash. That knowledge informs *what kinds of
invariant are worth declaring* — campaign 2's recovery-path rule (ADR 0015 §2) is
exactly that knowledge converted into declared coverage. The bar stays
target-specific internals, and that is what this ledger keeps out. Candidate 3
(khal) shares the vdir/iCalendar storage class with todoman, which this project has
explored; if it is ever selected, the report must say so.
