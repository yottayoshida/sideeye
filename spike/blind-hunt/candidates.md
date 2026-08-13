# Candidate targets, in priority order — sealed at Seal A (ADR 0012)

This list is **frozen**. Nothing may be appended after Seal A merges, and the order
below is the order the selection predicate walks. Every entry was chosen from
web-hosted documentation only; no candidate had been installed or executed when this
file was written.

These are **high-risk blind targets**: file-backed state chosen on purpose, several
spanning more than one file (abook and hledger are single-file counterweights so the
sweep is not one storage shape five times). This campaign is *not* the §18
average-target calibration — that was satisfied by timewarrior on 2026-08-12 — and
the report must not claim otherwise.

Eligibility, read from docs alone: none of the five advertises crash-injection
testing in its documentation. That is as far as this claim can honestly reach —
reading a target's test suite to verify it would itself breach the source rule.

| # | Target | Install | State, per its own documentation |
|---|--------|---------|----------------------------------|
| 1 | **topydo** | pip | todo.txt format; the documentation describes an archive of completed items alongside the active list |
| 2 | **khard** | pip (needs Python ≥ 3.10) | vCard files, one per contact |
| 3 | **abook** | apt (Debian bookworm 0.6.1-2) | a single text address book |
| 4 | **khal** | pip | vdir directories of iCalendar files |
| 5 | **hledger** | apt (Debian bookworm 1.25-2) | a plain-text journal, appended to |

## Taint ledger — targets excluded because this project already read their internals

timewarrior · taskwarrior · git · todoman · watson · jrnl · omamori.

For each of these, this project has read traces, write orderings, or source while
hunting; "declared before the bug was known" is not recoverable for them.

**Carried-over class knowledge is declared, not denied.** From those targets this
project knows the general shapes — a window between renames of related files, the
temp-write-then-rename idiom, journals that must stay a prefix of themselves. That
knowledge informs *what kinds of invariant are worth declaring at all*, and it comes
along to every future campaign. The bar §17 sets is target-specific internals, and
that is what the ledger and the reference rules keep out. Candidate 4 (khal) shares
the vdir/iCalendar storage class with todoman, which this project has explored; if it
is ever selected, the report must say so.

## Consultations during Seal A (documentation only)

| Source | Consulted for | Note |
|--------|---------------|------|
| `github.com/topydo/topydo` README | what it is, install, todo.txt format | PyPI page failed to render; README used instead |
| `pypi.org/project/khard` | version, Python floor, vCard-per-contact storage | |
| `pypi.org/project/khal` | version, vdir/iCalendar storage | |
| `packages.debian.org/bookworm/abook` | version, description | |
| `packages.debian.org/bookworm/hledger` | version, description | |

No `--help` output, no normal-run transcripts, no traces, no source, no issue
trackers: nothing was installed at Seal A time.
