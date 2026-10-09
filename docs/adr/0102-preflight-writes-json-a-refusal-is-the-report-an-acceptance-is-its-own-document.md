# 0102 — Preflight writes JSON: a refusal is the report, an acceptance is a document of its own

- **Status:** Accepted (2026-10-09)
- **Refs:** #717 (from the 2026-10-05 whole-product review); ADR 0010 (the MCP server
  self-execs, so a child answers through a file); ADR 0078 (the repeated authoring cost is
  the judged set); ADR 0079 (the judged set as data); `docs/contract-freeze.md` surfaces 2
  and 5.
- **Scope:** `src/cli.zig`, `src/main.zig` (`observeAgain`, `preflightReport`),
  `src/report.zig`, `spike/check-report-schema.py`, `spike/acceptance.sh`, `docs/cli.md`,
  `docs/report-schema.md`, `docs/contract-freeze.md`.

## Context

#717 asked for `sideeye_preflight` over MCP: an agent revising a define was running whole
explorations to learn what preflight answers from one observed run, and ADR 0078 had found
the repeated cost of authoring is revising which paths are judged. The MCP server runs the
engine as a child and reads its answer from a file (ADR 0010), and preflight had no file to
give: it refused `--json` with "preflight has no machine-readable form; sideeye explore
--config answers strictly more". That is true and was not the point — explore answers more
by running every world.

The text could not simply be handed over. The server's text block marks what the target
influenced with one counted region that never spans lines, and preflight's report is many
lines with target-chosen paths in them. And `--twice` quotes the bytes two runs disagree
on, which the page kept out of every machine form on purpose: a stretch that differs run
to run is where a per-run token or secret sits.

## Decision

**`preflight --json <path>` writes what preflight found, in one of two documents.**

- **A refusal or a stop writes the report**, `sideeye/report`, through the same
  `unknown()` and `setupError` paths explore's do, carrying the refusal preflight's text
  shows. Usually explore reaches the same one on the same define, and the docs say where it
  does not: with no crash point and neither `--oracle` nor `--allow-unverified`, explore answers its completeness gate first;
  preflight's recovery note and some of its messages are its own. (The first draft of this
  ADR said "the same verdict, reason, message and `next_step`"; review found the cases above.)
- **An accepted recording, or two runs that differ under `--twice`, writes
  `sideeye/preflight`.** Not the report: its `verdict` is a closed set of four, frozen, and
  preflight produces no verdict. The envelope already tells a reader to reject any other
  `schema`, so no existing consumer reads the new one by mistake.
- **The document carries the text block as data, and nothing the text block does not
  print**: the outcome and its exit code, the operation count, the account sentences and
  figures under the report's own names (written by the same functions, moved out of
  `buildJson` whole), and the judged set, last. Preflight runs the recording phase that
  publishes it, so the set is there — the plan for this change said otherwise and was wrong.
  The `note` and `next` lines are advice for the command line and are left out.
- **Under `--twice`, each differing path is listed with the byte line's `.shape` form** under the key `shape` —
  where, how long, what kind — made inside `observeAgain` beside the `.bytes` form the text
  quotes, because the second snapshot is freed when that function returns. No byte of
  either run reaches the document.
- **Sealed like the report.** Both documents go through one writer — temporary name,
  rename, `sideeye: json sha256=…;` on stderr — and preflight's two exits call `emitSeal`.
- **Frozen from the first release.** The document's `schema_status` is `"frozen"` under
  surface 2's rule: fields may be added, none removed or redefined. An MCP tool hands it to
  agents in the same release, so there is no window in which its names could still move.

Two sentences that were false are corrected with it: `docs/cli.md` said the quoted bytes
are in preflight's output "and in nothing else Sideeye writes" — under `--oracle` strace's
capture in the work directory holds the start of each write too — and the seal paragraph
said preflight refuses `--json`.

## Alternatives considered

| rejected | why |
|---|---|
| the report for every outcome, with a new verdict or none | `verdict` is a frozen closed set, and a report without one breaks the "one field everything else hangs off" promise |
| the MCP server parses preflight's text | a machine reading a human report, and the counted region would rest on no line beginning with a target's byte — true today, held by nothing |
| no `--twice` over MCP, so no bytes problem | `--twice` is what names the paths to declare `scratch`, the cost ADR 0078 measured |
| the document as the text with the quotes removed | the quotes are built into the `.bytes` line; deriving the shape afterwards needs the snapshots, which are gone |

## Consequences

- `spike/check-report-schema.py` reads the page in two parts, split at the
  `<!-- schema: sideeye/preflight -->` anchor, and holds the new document to its own rows in
  both directions (a field it shares with the report may stand on the report's row); claim 5
  reads the four shared writers and the new one as well as `buildJson`.
- `say`'s buffer is 32 KiB: the whole help is one `say`, and at 16 it had 27 bytes left.
- The per-command help ceiling is 72 lines; preflight's is 70 with `--json`.
