# 0145 — The README's promise names its exceptions by a list, and every later ADR lists its windows

- **Status:** Accepted (2026-11-01)
- **Refs:** #936; ADR 0032 (whose placement of the exception this replaces); `docs/silent-windows.md`,
  `spike/silent-windows.tsv`, `spike/check-silent-windows.py`, `spike/check-readme-shape.sh` (check 9).
- **Scope:** `README.md`'s promise sentence, `DESIGN.md`'s section on a directory renamed in from outside, the ADR
  convention.

## Context

`README.md` promised "never a silent PASS", with one exception — unrecorded writes under a directory a recorded
`rename` moved in from outside — named in the sentence that makes the promise, as ADR 0032 decided, and
`spike/check-readme-shape.sh` held the sentence to `paths_attributed_to_rename`. The ADRs record more than one way a run
under an oracle can reach PASS with something missed: explored worlds read no oracle (ADR 0002, 0053, 0065), a write
that reaches neither witness is caught only per path (ADR 0121), a store through a mapping that was not refused
(ADR 0098), and others. The sentence said less than the record did, each newly found gap arrived as an urgent fix
rather than as an entry in a list, and nothing tied the gaps an ADR records to the promise they qualify.

## Decision

1. **The promise links a list.** `README.md` says "never a silent PASS — except the known windows, each with the report
   field or test that shows it, or a note that nothing does", linking `docs/silent-windows.md`. The page defines a window (a run under an oracle
   reaching PASS with an operation or a state change missed; not a refusal, not `--allow-unverified`, not a FAIL) and
   lists each with what shows it and where it was decided. The rename exception is its first row, and `DESIGN.md`'s
   section on it now points there.
2. **The ADRs and the page are held together.** `spike/silent-windows.tsv` files every line an ADR states a gap on —
   found by a fixed vocabulary — either under a window the page lists or with the reason it is not one, and
   `spike/check-silent-windows.py` fails on a gap nobody filed, on a filed anchor that no longer occurs once, on a window
   the page lists that no row sources, and on a vocabulary that no longer reaches the gaps #936 named.
3. **Every ADR numbered after this one ends with a windows section** (the heading the check names), which may say none.
   Its items are filed the same way. This is the half the vocabulary cannot carry: an ADR that records a gap in words
   the vocabulary does not know would otherwise go by, as a marker an author can forget to write would.

## Alternatives considered

- **Keep the rename exception named in `README.md` and link the others.** ADR 0032's reason — a reader meets the
  exception where the promise is made — is kept by the link sitting in that same sentence. Naming one window and
  linking the rest makes the named one look like the main one, and the clause would spend words the README's
  bound (`spike/check-readme-shape.sh`) has few of.
- **Leave `README.md` as it was and link the page from `DESIGN.md` only.** The promise sentence would go on saying
  less than the record does, which is the problem #936 names.
- **A marker in each ADR (`<!-- window: id -->`) matched against the page, with no vocabulary.** An ADR that forgets
  the marker passes. The required section is a marker whose absence fails.
- **List every gap on the page.** Most are refusals, rejected alternatives or past states; the reader of a promise
  wants the windows. The rest are filed with their reasons in the table, where a reviewer reads them.

## Consequences

- The onboarding clock's box holds `README.md` alone (`spike/onboarding-clock/PROTOCOL.md`), so a driver there reads
  "the known windows" without the list. That is the cost this decision accepts: the README says there are exceptions
  and where they are, and the list is one link away everywhere but in that box.
- `spike/check-readme-shape.sh` check 9 now requires the promise sentence to link `docs/silent-windows.md` rather than
  to name `paths_attributed_to_rename`.
- An ADR that predates this one is read through the vocabulary alone; a gap written there in other words is not
  caught. The page was drawn from a reading of those ADRs, not from the grep alone.
- A gap recorded only in `DESIGN.md` or `docs/report-schema.md` is not scanned; a row may cite either as a source, and
  its anchor is held there.

## Residual windows

None: this decision changes how windows are listed, not what a run sees.
