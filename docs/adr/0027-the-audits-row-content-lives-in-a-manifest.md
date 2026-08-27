# 0027 — The audit's row content lives in a manifest, and the page renders it

Status: Proposed

## Context

`docs/freeze-audit.md` is the v1.0 pre-tag gate: it classifies every open issue against
the five frozen surfaces and asserts that none is left as an unresolved hole. The page
says of itself that "the audit is a gate, not a ceremony performed once and aged", and
`spike/freeze-audit/check-freeze-audit.sh` holds its classification table against a
committed snapshot of issue numbers.

That check compares **only the set of issue numbers**. It does not look inside a row.
At thirteen rows that was enough, because a reader could hold the whole table. Measured
on the way into #281's re-sweep, the population the next sweep must carry is **56 open
issues** — 4.3× the current table — and the existing thirteen rows already fail the
page's own rule in four different ways:

- three touchers carry classes (`#39` A, `#123` C, `#156` C) — consistent with the rule
  "classes are for touchers";
- **six non-touchers carry class C** (`#62`, `#63`, `#64`, `#65`, `#160`, `#161`) — not;
- three non-touchers carry no class (`#118`, `#140`, `#147`) — consistent;
- `#86`, the issue that introduced the rule, carries neither cell.

A form that is applied four ways on thirteen rows is not a form that survives being
multiplied. The set-equality check cannot see any of it: every one of those rows is
present in the snapshot, so the gate is green on a table whose rows disagree about what
their own cells mean.

A second measurement decided the shape of the fix rather than merely motivating it.
`gh issue list --json ...` without `--limit` returns **30** — exactly the page size —
and with `--limit 1000` returns the real count (56 when this was measured, 55 after a
peer closed #351 the same day; the default returns 30 either way, which is the tell).
A truncated result is indistinguishable from a complete one by inspection, and if both
the snapshot and the table are derived from the same truncated query they agree
perfectly. Both queries are captured at one instant in
`spike/freeze-audit/capture-2026-08-27-limit-truncation.json`. For a gate whose subject is completeness,
the acquisition step is part of what has to be trusted, not a detail of how the
manifest is filled.

## Decision

**The manifest is the trust root for row content; the page's table is generated from
it.** The committed snapshot remains the trust root for the *population* — which
issues belong in the table at all — so there are two authorities and the gate
checks the manifest against both the snapshot and the page.

`spike/freeze-audit/audit.tsv` carries one row per open issue with a fixed column set,
and `spike/freeze-audit/render-audit.sh` renders the Markdown table from it. The check
requires the page's table to be byte-identical to a fresh render, so a hand edit to the
page is a failure rather than a silent divergence.

Three consequences are load-bearing and are the reason this is a decision rather than a
refactor:

1. **`surface` becomes an enumeration** — the five names from `docs/contract-freeze.md`
   plus `none`. The old `touches` cell mixed "does it touch one" with "which one" in
   free prose; a row can now be checked against the enum.
2. **Class applies to every row, not only to touchers.** The page's original rule said
   classes were "for touchers", and the owner first affirmed it — then the migration
   measured that under a strict reading of the five surfaces *no* row in the snapshot
   touches one, which would have stripped the only class-A row and emptied the clause
   the gate rests on. The owner's second ruling the same day separated the axes:
   `surface` is the frozen-surface question, `class` is the PASS-soundness question, and
   every row carries a class. Four rows that previously carried none (#86, #118, #140,
   #147) gain C in this migration; that is a classification change, and it is the only
   one this PR makes.
3. **`disposition` becomes an enumeration whose allowed values depend on the class**,
   taken from the page's own class definitions rather than invented: class A resolves
   only by `fix`, `demote`, `narrow` or `measured-already-fixed` (the page: "prose alone
   cannot retire one"); class B by `fix` or `document`; class C by `fix`, `defer` or
   `tracked`. The check validates the disposition *word*; whether the adjudication was
   executed is a human-reviewed assertion in the rationale column, and the page says so
   rather than implying the gate proves it.

**Acquisition is part of the mechanism.** Every tracker query carries `--limit 1000` and
asserts the returned count is strictly below the limit, because reaching the limit is
indistinguishable from being truncated. The canonical acquisition JSON is committed with
its UTC bounds so a row's provenance is reproducible rather than recalled.

**The check gains a `--live` mode.** The check is outside CI because it needs the
network; that same fact means it can compare the committed snapshot against the tracker
directly. `--live` reports the drift and exits 3 — distinct from 1, the gate's own
failure — so the audit can notice its own ageing instead of waiting to be told.

## Alternatives Considered

**Keep the hand-written table and add rows.** Rejected on the measurement above: the
form is already applied four ways on thirteen rows, and the check cannot see the
inconsistency because it only compares number sets. Forty-three more rows written by
hand would make the table the largest unchecked artifact in the repository, in the one
document whose job is to be checkable.

**Add semantic checks to the hand-written table without a manifest.** Rejected because
the predicates would have to parse prose cells, and the cells are prose precisely
because nothing constrained them. Parsing `no — apparatus weight` to decide whether a
row is a toucher is a regex standing in for a schema; the schema is cheaper and it is
what makes the enum checkable.

**Generate the manifest from the tracker on every run instead of committing it.**
Rejected: the classification is human judgement, and a manifest regenerated from the
tracker would either discard it or re-derive it, which is the thing that cannot be
automated. The tracker supplies the population and the timestamps; the manifest carries
the judgement, and `--live` is where the two are compared.

**Defer the mechanism and re-sweep first.** Rejected as the ordering it implies: the
manifest's shape would then be fitted to fifty-six rows already written, and a schema
fitted to its data checks nothing. #239 made the same ordering argument for a different
artifact — the rulebook merges before the results — and the reason transfers.

## Consequences

The page stops being editable by hand, which is a real cost: a one-word correction now
means editing the manifest and re-rendering. The check makes that a failure rather than
a nuisance, deliberately.

Sweeps become cheaper in the part that scales — the rows — and unchanged in the part
that does not: a class-A disposition is still the owner's adjudication, taken with the
recommendation visible before deciding, and no enumeration makes that decision for
anyone.

The gate can now report its own staleness, which means it will report it. The first run
of `--live` in this change reports thirteen against fifty-six, and that number is the
input to #281's second part rather than a defect introduced here.

Sunset: this page retires at the v1.0 tag. The manifest, the renderer and the check
retire with it — the freeze itself lives in `docs/contract-freeze.md`, which is not
generated and is not affected by this decision.
