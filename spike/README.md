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
| `replay_gate.py` | the one replay-gate predicate: imported by `loop-closure-timew/judge.sh`, called by `dogfood-timew-replay.sh` leg C. `--selftest` holds `gate()` and the CLI to the same answers (acceptance check 11c) |
| `suite_summary.py` | the upstream suite verdict for `judge.sh secondary`: reads timewarrior's C++ test-framework output (summary line, under-run line, plan recorded not judged). `--selftest` in acceptance check 11d |
| `check-sealed-campaigns.sh` | CI: walks every `blind-hunt*/` and runs the consistency checker each campaign sealed |
| `lib/` | the cohort harness, sourced not copied (#259; `check-transcript.sh` is the one file run rather than sourced): `probes.sh` (entry point to the verdict functions, which stay in `cohort2/probes/lib.sh` and `cohort4/probes/lib.sh`), `drills.sh` (`drill NAME red\|green CMD…`, measures the FAILS delta itself), `snapshot.sh` (`snap` — red through the tested leg, from cohort 4's `run()` — plus `run_rc` and `declared_exec`), `check-transcript.sh` (manifest-driven verdict-set check). Every file has `--selftest`; acceptance check 11e runs them |
| `check-cohort-transcripts.sh` | CI: re-verifies the four cohort-4 probe transcripts the sealed checker declares sets for, holds the eight sealed transcript names, and walks any later cohort's `probes/verdicts.tsv` through `lib/check-transcript.sh` |
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
| `blind-hunt/` | campaign 1 (topydo) | 12/13 counterexamples, none of them filed (`topydo/topydo#318` already covers the destruction); `topydo/topydo#341` is a separate finding, the recovery misfire |
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

`cohort4/` is a closed record. `PREP.md` (the register of every mistake
cohorts 1-3 paid for, mapped to what makes it impossible), `SCOUT-BRIEF.md`,
`PROTOCOL-DRAFT.md` and `CANDIDATES-REJECTED.md` are the preconditions;
`PROTOCOL.md` is the frozen protocol, and it names the targets — himalaya
and vdirsyncer at the 2026-08-22 sign-off (vdirsyncer then failed rule 2
when measured on the 23rd), unison after the rule screen (its "freeze"
paragraph). `probes/` holds the eight transcripts, the
sealed `check-transcript.sh` that holds four of them to their verdict
sets, and `capture.sh`, which ran it once at capture time. (An earlier
version of this paragraph said no target was named and the frozen protocol
did not exist; both were true only of the preparation stage.)

**The next cohort sources `spike/lib/`.** Its probe and drill scripts
source `lib/probes.sh`, `lib/drills.sh` and `lib/snapshot.sh` rather than
copying cohort 2's or cohort 4's, and its expected verdict sets go in
`probes/verdicts.tsv` (target, mode, transcript file, names), which
`check-cohort-transcripts.sh` walks in CI — every row's transcript must
exist and every `probes/*.txt` must have a row. Cohorts 2-4 are not restaged:
their scripts stay as sealed, and the one implementation of each verdict
function stays where it was drilled red.

**The next cohort's selection asks about the copy.** Beside rule 5 of
`spike/cohort4/SCOUT-BRIEF.md` (sealed, so the question lives here rather
than in it), "Stores primary data locally that users do not want to lose",
it asks whether the user's ordinary workflow keeps an external copy of
that data, and whether damage reaches it. A copy that survives the crash
takes the target off the slate: poetry's manifest lives in its users'
version control (the note for cohort 5 in the 2026-08-23 BUILDLOG entry,
cohort 4 begins), and the report `python-poetry/poetry#11019` was closed
not-planned by its own reporter, this repository's author, because the
write path is tomlkit's; that the copy in version control is what takes
the target off the slate is this repository's reading, said nowhere
upstream (BUILDLOG, 2026-09-03). A copy that receives the damage is the
strongest form and what the slate is for: on himalaya the external
recovery path carries the damage outward, a real server keeps it, and a
second store downloads it (`spike/cohort4/himalaya-r2/RESULTS.md`,
measured 2026-08-23). The external recovery paths are measured again
before any report, which is cohort 4's Reporting rule; asking at selection
is the cheaper place to ask the same question.

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
(timewarrior, watson, todoman, omamori). They stay because BUILDLOG and
ADR prose cite them by path, and CI is not blind to them: the
`timew-regression` job runs `dogfood-timew-replay.sh` (legs a–c) on every
push to main and every pull request, and `acceptance.sh` reads three of them on every
run — `dogfood-watson/check.sh` and `loop-closure-timew/define/check.sh` as
cookbook recipes, and `dogfood-timew.sh` as a define whose bytes the
unknown-rate corpus pins. That pin freezes the recipe, so the timewarrior
define's one canonical text is `loop-closure-timew/define/` (checker, setup,
operation): `stage.sh` and `dogfood-timew-replay.sh` copy its checker and setup
and read its operation (#65).

## Dogfood runs — open, not sealed

`dogfood/` holds use of Sideeye that is not a cohort: a target somebody actually
uses, picked by the selection rules, measured and written up. Nothing there is
sealed, nothing claims blindness, and no run there is evidence for criterion 1.
`dogfood/README.md` says what a run records and carries the one rule that
directory adds to the cohort's — **screen linkage and threads before writing the
candidate table** — which the first run bought by spending four target slots on
walls it forecast correctly and confirmed expensively.

It is a record, so it is documentation by the `spike/**` default (ADR 0021) and
needs no entry in `.gitattributes` or in `check-gitattributes.sh`'s
`exempt_dirs`. It has a sunset condition, in its README.

## Local outputs

`out/`, `runs/`, `assisted/runs/` are gitignored scratch. Everything worth
keeping (reports, transcripts, saved cases) is committed on the tracked
side; the scratch dirs can be deleted at any time.
