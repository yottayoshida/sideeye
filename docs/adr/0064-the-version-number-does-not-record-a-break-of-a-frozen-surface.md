# 0064 — The version number does not record a break of a frozen surface; compatibility is promised by the freeze page

Status: Accepted (2026-09-13)

## Context

`CHANGELOG.md`'s standing header said, until this change: "this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Until v1.0, any of the five frozen-at-1.0 surfaces … may change in any release." `PRD.md` said "After 1.0, breaking them is a 2.0." Three comments in `src/` said a new `unknown_reason` member was unavailable "until 2.0".

What the project did after the tag is recorded in `docs/contract-freeze.md`: two members added to the `unknown_reason` closed set (#405, #377), both shipped in `v1.1.0`, and one documented field withdrawn before any tag emitted it. On 2026-09-04 the owner ruled that the version does not record the break — "an owner ruling about what the version number is for, not a reading under which the addition stopped being a break" — and that ruling lived on the freeze page and in `BUILDLOG.md` only (#566). A consumer who read the header, pinned `>=1.0,<2.0`, and took the closed set as closed at 32 did what the header told them and was wrong twice.

The same tag's other unflipped sentence is #565: every `--json` report still said `"schema_status": "experimental"`, and `docs/report-schema.md` documented that value "until the v1.0 freeze".

## Decision

1. **The header is rewritten to say what is true.** Version numbers take the form of Semantic Versioning; compatibility is promised by `docs/contract-freeze.md`, not by the number. Within the five surfaces that page names, a change the page does not allow is a breaking change whichever release carries it. Since v1.0 such changes have shipped in 1.x releases by owner ruling, each ruled on its own, none licensing the next, and each recorded on that page. Nothing outside what that page names is promised to stay the same.
2. **`PRD.md`, `DESIGN.md`'s status line, `docs/contract-freeze.md`'s introduction and the three code comments say the same thing**, without naming a version a break would take.
3. **`schema_status` becomes `"frozen"`**, and the change is recorded on the freeze page as the fourth break of surface 2. The schema page had foretold the transition, which reads as though turning the value over merely keeps a promise; it is counted anyway, because every tag through v1.3.0 wrote the old value, so a consumer who read the field sees a field whose documented content was a literal change that literal (unlike `contract_version`, whose number the schema documents as moving), and the page's reasoning about its first break — a ruled break is still a break — does not bend because this one was announced.
4. **`spike/check-report-schema.py` holds the value to the freeze** (claim 6): it must be `"frozen"`, the schema page's anchor and table row must say so, and every generated report must carry it. Comparing the page with the reports alone would not have caught #565 — the code and the page agreed on `"experimental"` at every tag — which is why the literal itself is pinned.

## Alternatives considered

- **Keep the declaration and change the practice: the next break takes a major.** Declined by the owner: it prices a one-member addition to a closed set at a 2.0, the price the 2026-09-04 ruling looked at and declined.
- **Version the closed sets separately**, the way `contract_version` versions the trace contract, and emit that number in the report. Declined: it adds a machine field and a second number to make true a sentence prose can make true, and the freeze page already records each movement by name.
- **Keep "adheres to Semantic Versioning" and add the exception.** Declined after the plan's first review: the exception covers only the frozen surfaces, so every surface the freeze does not cover — the CLI's flags among them — would keep a stronger promise than the frozen ones (a breaking change there would still demand a major), the inverse of what the freeze is for.
- For `schema_status`: **keep `"experimental"` and explain it on the schema page** — the report would keep saying something false about itself; **remove the field** — it shipped in four tags, and withdrawing it is a heavier break than changing its value.

## Consequences

- The header no longer implies compatibility outside the five surfaces; the phrase "adheres to Semantic Versioning" implied it, and that implication is withdrawn here. One pre-tag reading of a behaviour outside them is on record and is not settled by this ADR: `docs/freeze-audit.md`'s #156 row (a page that retired at the tag) read CLI acceptance semantics as outside surface 1 and still recorded `--oracle` with `--allow-unverified` as freezing as-is, "a 2.0 question". The freeze page does not name that behaviour, so the header does not promise it; whether it stays is that row's question, for the owner.
- `schema_status: "frozen"` is the fourth break of surface 2 recorded on the freeze page. Its ledger row is a sweep's job, for the reason the page gives for the second and third.
- `docs/contract-freeze.md` line 9 still reads "changing any of them is a breaking change". It is the tag's sentence, pinned verbatim by `spike/freeze-audit/clause-checks.tsv` (`s0-breaking`), and the surface paragraphs below it name what each surface allows; the header points at the page as a whole, so the two agree.
- `PRD.md`'s list of what freezes names "the L0/L1/L2 levels", words the freeze page does not use. They are inside what it names: L1 is what the `marker` spelling means and L2 what `check` means (surface 1 freezes the meaning of an accepted spelling), L0 is the define with neither, and `earliest.invariant` carries all three as surface 2 values.
