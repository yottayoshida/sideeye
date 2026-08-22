# spike/ — a map

This tree holds everything that is not the engine: the CI harness, the
blind-campaign apparatus, the sealed records of closed campaigns, and the
assisted-discovery cohort. Three kinds of things live here, and they have
different rules. Read this before moving or "cleaning up" anything.

## Live tooling

Used by CI or by the next campaign. Safe to change (with review; a
rehearsal green is required before a Seal A PR and after any tool change).

| Path | Role |
|------|------|
| `Dockerfile` | pinned candidate container for campaign sweeps |
| `toys/`, `build-toys.sh`, `check.sh` | the demo/acceptance toy target |
| `acceptance.sh`, `mcp-acceptance.sh` | CI acceptance harness (CLI and MCP surfaces) |
| `check-report-schema.py` | report JSON/text parity and schema claims |
| `check-sealed-campaigns.sh` | CI: walks every `blind-hunt*/` and runs the consistency checker each campaign sealed |
| `campaign-driver.sh` | non-sealed driver: status / sweep / select / verify / explore. Refuses dirty trees, uncommitted inputs, existing outdirs |
| `ledger-append.sh` | the ONLY pen for campaign ledgers — appends, then proves byte-prefix against HEAD |
| `rehearse-campaign.sh` | full-apparatus rehearsal in a scratch repo; every guard is fired with a planted defect before the real thing runs |
| `upstream-report-status.sh` | prints the standing upstream reports with their state, comment count and last activity, measured now and stamped with the measurement time - the citations in PRD/#140 carry dates that go stale silently |
| `merge-gate.sh` | one verdict line for "may this PR be merged": checks green with denominators, clean tree, local head equal to the PR's. `--selftest` falsifies it against the three merges that went out wrong |
| `cohort4/preflight.sh`, `cohort4/visibility-logger.c`, `cohort4/preflight-analyse.py` | probe conditions 8 (every state-root mutation passed through an interposable function) and 9 (how many kill points the operation has). Engine-free. `--selftest` falsifies both against `toys/toy.c` and `toys/toy_raw.c` |
| `cohort4/novelty-prescan.sh` | the recorded tracker search a novelty judgement cites, with the controls that make a zero mean something. Refuses multi-word terms: they silently return zero |

## Closed campaign records — sealed; do not move, do not add files

| Path | Campaign | Outcome |
|------|----------|---------|
| `blind-hunt/` | campaign 1 (topydo) | 12/13 counterexamples; `topydo/topydo#341` filed upstream |
| `blind-hunt2/` | campaign 2 (khard burned → abook) | null — no counterexample in the declared window |
| `blind-hunt3/` | campaign 3 (khal) | null — 41 crash worlds, all PASS |

Two rules that look like housekeeping bugs but are design:

- **The per-campaign tool copies are the forward-carry rule, not
  duplication to deduplicate.** Each campaign seals its own copy of
  `check-config-paths.sh`, `select.sh`, `sweep.sh`, `verify-seals.sh`;
  `check-sealed-campaigns.sh` fails any campaign that dropped its checker.
  Merging the copies into one shared script would un-seal three audits.
- **Sealed directories take no new files.** Campaign 1 predates the CI
  checker and is exempt by literal name; adding files to a sealed campaign
  directory marks its checkers sighted under ADR 0012. The audit
  transcripts (`*/analysis/verify-seals.txt`) name these paths.

Governing ADRs: 0012 (two-seal blind protocol), 0015 (inherited selection
seal, burn vs consumption), 0016 (campaign lessons as declaration
requirements).

**Standing taint rule**: hledger is the last blind-eligible candidate —
its sweep refusal is sealed unread. Do not read its internals, its
tracker, or scout it. That eligibility is spent the moment anyone looks.

## Cohort 4 — preparation, open

`cohort4/` holds preconditions, not a campaign: `PREP.md` (the register of
every mistake cohorts 1-3 paid for, mapped to what makes it impossible),
`SCOUT-BRIEF.md` (the instrument for proposing candidates),
`PROTOCOL-DRAFT.md` (each section marked carried, drafted or blocked),
`CANDIDATES-REJECTED.md` (the rejections the brief requires be shown beside
the survivors), and the gates with their falsification transcripts. No
target is named in any of it, and the frozen `PROTOCOL.md` does not exist
yet.

## Assisted-discovery cohort (#118) — closed record, live acceptance tests

`assisted/` holds the first cohort: `PROTOCOL.md`, `SCOUT.md`,
`RESULTS.md`, and five target directories with committed defines. It is
assisted, never blind — do not cite it as a blind result. The
`<target>/ops/explore.sh` launchers are named by issues #121–#123 as their
acceptance criteria, so these paths are load-bearing: an engine change
that closes a gap is proven by re-running them from a fresh checkout.

## Historical dogfood spikes — kept in place

`dogfood-*.sh`, `dogfood-watson/`, `loop-closure-timew/`, `probe.sh`,
`empty-oracle.sh`, `timew-undo-ordering.patch` — the pre-campaign era
(timewarrior, watson, todoman, omamori). Nothing in CI runs them; they
stay because BUILDLOG and ADR prose cite them by path.

## Local outputs

`out/`, `runs/`, `assisted/runs/` are gitignored scratch. Everything worth
keeping (reports, transcripts, saved cases) is committed on the tracked
side; the scratch dirs can be deleted at any time.
