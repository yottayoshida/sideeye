# Sideeye PRD — v0.1 to v1.0

**Status:** active roadmap
**Last updated:** 2026-08-10

[DESIGN.md](DESIGN.md) says what Sideeye is. This document says in what order it becomes real, what each milestone must prove, and what v1.0 promises. Milestones are ordered by risk: the assumption most likely to kill the project is always the next one tested.

## Versioning philosophy

**v1.0 is a contract freeze, not a feature count.** What freezes at 1.0:

- the Define contract (`sideeye.toml` format and the L0/L1/L2 levels),
- the report schema (JSON),
- the exit codes (0 PASS / 1 FAIL / 2 UNKNOWN / 3 SETUP ERROR),
- replay compatibility for saved cases.

Until 1.0, any release may break any of these without apology. After 1.0, breaking them is a 2.0.

## Milestones

### v0.1 — First counterexample (Linux)

**Goal:** prove the engine on the easiest ground. This milestone *is* the feasibility spike.

Scope:

- Linux only, single operation, dynamically linked targets.
- Crash-point exploration at file-operation boundaries; deterministic, logically addressed crash points.
- L0 built-in atomicity invariant (state-dir snapshot comparison). No checker support yet.
- State snapshot/restore per world (DESIGN §14-11).
- JSON + text reports with exploration counts; the full exit-code contract.
- Reproduction by re-running the operation with the crash point named in the report, printed as a `reproduce` line the caller can paste. `sideeye replay <case>` moves to v0.2, with the case storage it needs: this milestone listed the command while listing storage under v0.2, and a case that was never stored cannot be replayed.

Acceptance:

- A toy target with a planted delete-before-rename bug yields FAIL with a logical crash point, reproduced 10/10.
- The corrected toy target yields PASS with exploration counts.
- UNKNOWN and SETUP ERROR are demonstrably reachable — each verdict path falsified once. A gate whose failure paths were never seen firing is not a gate.
- The printed `reproduce` line is executed by the suite, not read. It was wrong twice while looking right.

Risk retired: interposition works at all; crash points are deterministic and reproducible.

Delivered beyond this scope, because it cost less than deferring it: macOS interposition and OS parity (originally a milestone of its own, below), and L2 checkers with falsification (originally part of the Define-contract milestone). Those milestones keep their remaining scope.

### v0.2 — Process boundaries (delivered 2026-08-11)

**Goal (as shipped):** stop refusing every target that creates a process, without ever guessing about one.

This milestone was not on the original roadmap — the slot was promised to the Define contract, which moves to v0.3 with its scope unchanged. What forced the queue-jump: pointing v0.1.0 at its first real target (the v0.4 dogfood subject) ended at `child_process_detected` for the shape every shim, wrapper and launcher shares, and the attempt surfaced a v0.1.0 defect in which observing a `vfork` killed the target. Roadmaps yield to measurements; that is what they are for.

Shipped:

- Containment: every target runs in its own process group, killed and reaped as one, so nothing a target starts outlives the engine's look at the state.
- Interposing `vfork` no longer corrupts the target (a recorded boundary, then a guaranteed tail call).
- Boundary tolerance (trace contract v3, ADR 0002): a fork/spawn boundary is explorable when an oracle is present and no process other than the subject touched the state directory. Everything else refuses with a named detector, and any boundary without an oracle is UNKNOWN.

Acceptance, measured: six acceptance cases over one binary with one environment variable of difference decide tolerance by the child's behaviour alone, and the dogfood target now travels past the boundary gate to fail for its true reason (a rustix-issued raw syscall — #19) instead of the categorical one.

### v0.3 — The full Define contract (delivered 2026-08-12)

**Goal:** the three-commands-and-a-directory contract of DESIGN §12, complete.

Shipped, one PR per piece (#43, #44/ADR 0007, #47/ADR 0008, #49/ADR 0009, plus the acceptance):

- Refusals name the operation they refused on (#41): the divergence index, the raw strace line, the shim's account — in text and JSON alike.
- `sideeye.toml` (ADR 0007): a hand-parsed strict subset owning the define surface only; unknown keys refuse with their line, and a key joins the schema only in the change that enforces it.
- L1 success markers and post-success invariants (ADR 0008): judged against the whole post snapshot in worlds where the marker reached stdout before the kill; a marker the clean run cannot produce refuses (`marker_never_observed`) instead of going silently vacuous.
- L2 checker scripts and checker falsification before every run — both shipped early, in v0.1, and exercised by every dogfood since.
- Case storage with landing context and `sideeye replay` (ADR 0009): replay is the explore pipeline restricted to the case's crash point plus the baseline, every trust gate intact; a changed recording answers `case_no_longer_applies`, never a verdict about a shifted address.
- **Scope narrowed, deliberately:** shrinking in v0.3 means the *earliest* failing crash point, reported with its logical address. "Simplest" and measured reproducibility counts remain future work, and the report claims neither.

Acceptance (measured, in `spike/acceptance.sh`):

- The doctor-cross-examination scenario runs end-to-end against a toy target, driven by the toml alone (check 2aa).
- Conditional-invariant vacuity both ways (check 2y): the marker-observed worlds are a strict subset of the crash worlds (`0 < 4 < 8` measured on the marker toy), an unflushed marker yields an honestly vacuous zero, and a marker the clean run cannot produce is UNKNOWN.
- The define budget, measured on a fresh target (`spike/dogfood-watson/`): watson is driven to a correct, named refusal — `baseline_violates_invariant`, its frames carry a fresh uuid per run — by a `sideeye.toml`, one checker script, and one environment variable. The budget held; the refusal did its job.

### macOS native — absorbed into v0.1

**Goal:** the second platform DESIGN §9 committed to, with honest edges.

Delivered in v0.1, ahead of its slot: macOS interposition with an identical CLI and contract, and a parity assertion in CI (identical scenario, identical verdict and crash point on both OSes). What remains of the original scope is one honesty gap, tracked as #10: an Apple platform binary can never be observed, and the report says `no_shim_marker` without naming why. No longer a numbered milestone.

The original scope, for the record:

- macOS interposition; identical CLI and contract.
- Hardened-runtime / library-validation targets detected and reported as unsupported (exit 2) — never silently mis-tested. Same for statically linked Linux binaries.
- A parity suite: identical scenarios must produce identical verdicts and equivalent crash points on both OSes.

Acceptance: parity suite green on macOS and Linux; unsupported-target detection falsified once per OS.

### v0.4 — Dogfood: omamori (delivered 2026-08-12)

**Goal:** evaluate the primary success criterion (DESIGN §17) for real.

Scope:

- Run Sideeye against omamori's stateful operations (its state is file-based; it qualifies under DESIGN §9 constraints).
- Regression-case stability in practice: saved cases replayed across real code changes; context mismatch must produce "case no longer applies", not a silent pass.

Acceptance: DESIGN §17's primary criterion evaluated honestly — either a novel, author-confirmed crash-consistency bug, or a written analysis of why none was found. The analysis feeds the kill criteria (DESIGN §18); this step cannot be skipped or softened.

**Status (2026-08-12, updated same day): calibration kill condition cleared; regression-case stability measured in practice; the full §17 primary criterion is not yet met.** The second scope item is now measured rather than argued (`spike/dogfood-timew-replay.sh`, BUILDLOG same date): the saved timewarrior case replays FAIL on the unpatched pinned build, replays **PASS** across the applied fix rebuilt under the same command name (explored 2, landing context intact), and answers `case_no_longer_applies` — a refusal, not a verdict — against a build whose recording differs (distro 1.4.3, 19 ops vs 24). The state-mutating omamori subcommand this evaluation drove — `exec` — was reconnoitred (BUILDLOG, same date): the write pattern confirms the high-water mark *after* the body, so verify stays conservative in every crash window and no §17-class bug exists on that path — a clean instance of "too hardened" (§18), the survivable side. The guarded self-modification commands (config-modify, `init --force`, audit key rotate) refuse for a human at a terminal exactly as for an agent (#12); measuring one as a Sideeye `operation` would require break-glass, which removes the defence under test, so it is out of scope on discipline (the full surface was enumerated the same day — BUILDLOG: every subcommand including nested arms, the argv0 shim mode and the hook entrypoints, cross-checked from the write-primitive side; of the four unguarded writers beyond exec, install/setup/init refused at named trace-contract walls under v8 — `symlinkat`, `fchmodat` — until #141 re-measured them under v10 (2026-08-16): all four explore fully and PASS, audit verify's high-water-mark bootstrap write included (4 crash points in that run; counts move with image and contract); the one non-atomic write found, retention's in-place prune rewrite on the append path, is recorded there as an open finding that needs clock control to drive). The find is on the calibration target §18 required: timewarrior, no hand-written adversarial tests, whose crash-window bug (`timew undo` destroying committed data, timewarrior#778) is the mechanical inverse of omamori's safe ordering. That clears §18's calibration kill condition. It does **not** yet satisfy v1.0's entry criterion 1: of §17's six conditions, four are clean and two have gaps — "discovered automatically" holds only for the crash-world search (manual trace triage seeded the target and window; DESIGN §17 status note), and the finding is kept as a reproducible recipe, not a `sideeye replay` regression case (it needs a built timewarrior). *(Updated 2026-08-16: the regression gap is closed as hygiene — the `timew-regression` CI job runs the recipe's record/FAIL/PASS legs on every push to main and every pull request (#82) — and the discovery gap is superseded rather than closed: ADR 0017 redesigned criterion 1 around provenance, and the timewarrior finding stays outside it by the ordering requirement.)*

### v0.5 — The loop closes (delivered 2026-08-13)

**Goal:** prove the counterexample is agent food, and calibrate detection power.

Scope:

- The report JSON documented as a schema; a quickstart for CI (GitHub Actions example).
- Loop-closure test (DESIGN §17, second criterion): a coding agent receives only the report and the repository, and must produce a fix that makes the replay pass — no human translation.
- Calibration target (DESIGN §18): at least one deliberately average stateful CLI with no hand-written adversarial tests, explored with honest results.

Acceptance: loop closure demonstrated end-to-end at least once; calibration results published in the buildlog, whatever they are.

**Status (2026-08-12, superseded the next day — see below): the agent-facing surface is built — and shipped early, in v0.4.0** (the adapter landed on main before v0.4 was cut, so the 0.4.0 tag carries it; this milestone stays open and cuts 0.5.0 when its own acceptance is met). `sideeye mcp` (ADR 0010) gives an agent the standard MCP tool surface — explore a `sideeye.toml` and replay a saved case, both measured end-to-end over the wire (explore → case → replay reproduces). The calibration target is already met (timewarrior, §18/§17 status). What remains for the milestone is the loop-closure *test* itself: hand an agent only the report and the repository through this surface and see whether it fixes the finding without human translation — the surface is ready to run it.

**Status (2026-08-13): loop closure demonstrated end-to-end — the milestone's
acceptance sentence is met.** A context-free coding agent, handed only the
counterexample (the report JSON, the case it names, the declared invariant it
points at, bug-blind replay plumbing) and the pinned timewarrior checkout,
re-derived the fix and the judge's own replay passed, with the feature intact
and the audit clean (`spike/loop-closure-timew/`, BUILDLOG 2026-08-13,
`spike/runs/sideeye-loop-1/manifest.json`). v1.0 entry criterion 2 is met by
this measurement. Two honesty notes: the first run drove the CLI replay
surface through the plumbing script, not the MCP adapter — **resolved the same
day**: attempting the MCP-mediated variant first surfaced and fixed two real
surface gaps (ADR 0011 — the child env dropped `TIMEWARRIORDB`-class
variables, and a persistent server had no per-call state freshness), and the
confirmation run then closed the loop **through this surface** with a second
model (claude-fable-5, `spike/runs/sideeye-loop-2/manifest.json` —
loop_closed true, all three controls held, audit clean); and the input set is
the report *and what it transitively names*, not "the report alone" (the
exact set is declared in the BUILDLOG protocol). The milestone's remaining
scope closed the same day: the report is documented as a schema
(`docs/report-schema.md`, held to the generated reports by acceptance
check 4), and the CI quickstart is a real workflow this repo runs
(`docs/ci-quickstart.md`). Nothing of v0.5's scope remains; 0.5.0 released
2026-08-13.

### v1.0 — Contract freeze

Entry criteria — all must hold, none may be argued around:

1. Primary success criterion met: a real, novel, author-confirmed crash-consistency bug **discovered by Sideeye's deterministic judge from an invariant declared and committed before this project observed any failure of the target in execution (reading a report of a failure while scouting is not observing one) — with the question's provenance recorded and labeled: blind (posed under ADR 0012's two-seal protocol) or assisted (a scout read the target; the scout and its sources named)** — fixed, and kept as a replayed regression case. "Novel" requires a recorded tracker search with a positive control, as campaign 1 scored it; "author-confirmed" reads as §17 scored it for timewarrior: this project's author judges the bug real, upstream confirmation is sought, not required. An assisted finding is never presented as blind; blind remains the stronger provenance and nothing assisted may borrow it, and the ordering requirement holds timewarrior's "discovered automatically — partial" scoring exactly where §17 put it (its checker was written after the failure was observed). Redesigned 2026-08-15 (ADR 0017, which carries the full argument, the re-scoring of past findings, and the costs): the redesign path was pre-committed in #118 after the campaign nulls were known and before any assisted evidence existed, and the #118 experiment then measured that the binding constraint on reaching a verdict was the judge's reach, not the question's provenance (`spike/assisted/REMEASURE.md`).
2. Loop-closure criterion met: an agent fixed a finding from the report alone.
3. Kill criteria (DESIGN §18) reviewed against collected data; none triggered.
4. UNKNOWN rate on supported targets measured and published; a target threshold is set from that data (not invented in advance) and met.
5. Contract frozen: config format, report schema, exit codes, replay compatibility.
6. Docs: a fresh machine reaches its first exploration in under ten minutes from the README.

If criterion 1 cannot be met, v1.0 does not ship — the kill analysis ships instead.

**Criterion 4 status (2026-08-16): met.** The measurement is `docs/unknown-rate.md` — a two-group corpus frozen and merged before the sweep ran (apparatus PR #142, then the results PR; the first-parent order is the audit trail). The A-group (28 trials over every runnable committed define) measured 1/28 UNKNOWN (3.6%, watson's known nondeterministic-writer refusal) and is published as the engine's development-input set, deliberately not the threshold basis. The B-group — 20 never-run targets machine-selected from Debian's own package metadata, 7 reaching the uniform define stage — measured 3/7 UNKNOWN (42.9%), every one a define-budget refusal with a named reason: four of the five targets whose invocations could be spelled as operation strings reached verdicts (including a fresh FAIL on bogofilter-sqlite, disposition pending triage), and the fifth (cookietool) was refused on the exit convention the uniform protocol declared, not on spelling. The threshold, set from that data by the owner and recorded with it — with the page disclosing that the origin classification postdates the sweep and that cookietool is its arguable case: target-origin UNKNOWNs ≤ 1/7 (measured 0; 1/7 even if cookietool is re-filed) and overall ≤ 50% (measured 42.9%) — both hold. The generated tables are held to the committed reports by acceptance check 12 (the surrounding prose is held by review, not by the gate); the funnel (20 selected → 13 documented walls → 7 explored) and the per-axis slices are on the page.

**Criterion 5 status (2026-08-17): audited; the freeze declaration is written and three fixes gate the tag.** The audit is `docs/freeze-audit.md` — all twenty-six open issues classified against the five frozen surfaces (the four from this criterion plus the MCP surface decided 2026-08-13), the classification held to a committed snapshot by a self-falsifying gate, and every class-A member — plus #10, their adjacent honesty fix — resolved by the owner's adjudication (fix: #27, #46; demote: #5; narrow: #39, #10 — none left as a documented hole under an intact PASS claim). The exit-code split from #94 is rejected permanently, with reasons on the page. The criterion is met when the three fix-adjudicated changes land and the pre-tag re-sweep runs; #86 stays open until then.

**Criterion 6 status (2026-08-17): met, first measurement.** The protocol was committed before the clock ran (`spike/onboarding-clock/PROTOCOL.md`: a network-off fresh container, the README as the only sideeye documentation, a context-free headless driver not told it was timed, the external target jrnl chosen by the owner under the standing selection bar). Wall-clock: **4 minutes 22 seconds** from the session's first event to `explore` returning a real PASS on jrnl — 4 of 4 crash worlds, oracle agreeing, checker falsified first — derived from the committed event timeline, not hand-written (`spike/onboarding-clock/RESULTS.md`, which also records the audit's three flagged transfer commands and their adjudication). The rehearsal that preceded the clock found the aarch64-linux release artifacts of v0.9.0 and v0.10.0 broken on lesser CPUs than their builders' — measured on Apple-Silicon Docker; the x86_64 artifact shares the construction, presumed affected and unverified (fixed and repaired the same day — the release matrix now pins `-Dtarget`); the run measured the repaired artifact. One run is one measurement: re-runs after doc changes append under the same protocol, and the last run before the freeze is the criterion's evidence.

**Criterion 3 status (2026-08-16): met.** The review is `docs/kill-criteria-review.md` — every §18 condition quoted, scored against named committed evidence, with the counter-evidence and margins on the page. Six rows are scored on measurements (the assisted cohort, the #84 sweep, the loop-closure test, the #144 follow-up; the calibration paragraph stands on #141); row 2 is scored on the recorded absence of the very comparison it asserts — no measurement supports the condition, and the page names what would; row 7 — the UX-difference condition, the one row whose wording makes absence of data a trigger rather than a neutral — is recorded as an owner adjudication (2026-08-16: not triggered), with the missing head-to-head disclosed on the page rather than argued around. The page also discloses that most rows draw on a single measurement family, so the review is one instrument read eight ways, not eight independent confirmations. None triggered. Acceptance check 11 holds the page's repository paths against rot; the numbers are quotations whose recomputation lives at their source pages. Per the page's closing rule, any future measurement landing on a row's trigger side reopens the review — the rows do not close permanently.

**Criterion 1 status (2026-08-14, after the blind campaign on topydo 0.14).** Three of its legs are now closed and three remain, and the split is deliberate rather than rhetorical:

- **found by Sideeye — closed, blind.** Twelve of thirteen declared operation forms produced a counterexample from an invariant committed before any crash world of that target existed. `verify-seals` returns ALL SEAL CHECKS PASSED (R1 audited) against Seal B `5a034aff`, so the ordering is machine-checked, not asserted (DESIGN §17, and the three honesty bounds it carries).
- **kept as a replayed regression case — closed.** Each saved case replays inside the pinned image with no target build (`exit 1`, `the case reproduced`). This is the shape `#82` asks for; the timewarrior recipe could not provide it.
- **novel — measured 2026-08-14 (tracker search recorded in the campaign ledger), and the answer is split.** The blind-found crash-window destruction is not novel as a phenomenon: `topydo/topydo#318` reports the same failure surface (disk-full write destroying the list) — the campaign adds mechanism and a replayable counterexample, not the discovery. The recovery misfire (post-crash `revert` undoing an older command; contradictory documentation on the matching rule) was not found in the tracker and is novel as far as that search sees — but it came from post-seal analysis, not the blind search. **Consequence: no single finding currently satisfies "found by Sideeye" and "novel" at once**, and criterion 1 stays open on that conjunction. **Ruled 2026-08-14 (author): the misfire does not count.** The scale that scored the timewarrior find *partial* — a human formed the specific hypothesis — reads the same here with the arrows reversed, and the sealed declaration itself pre-committed to calling recovery measurements analysis, not findings. Criterion 1 therefore waits for another blind target *(superseded 2026-08-15 by ADR 0017 — the criterion no longer gates on blind provenance; the rulings in this paragraph stand)*: the designated path was a second campaign under fresh seals whose declaration includes **recovery-path invariants** ("after a crash plus the documented recovery command, intact data survives" — declarable from documentation alone), which is the lesson this campaign paid for. Timing is a resourcing decision, deliberately not fixed here. The misfire keeps the value it already delivered upstream (`topydo/topydo#341`); it simply does not wear the "discovered automatically" badge.
- **real / author-confirmed — open.** Not asserted by the run. The sharpest observed behavior lives in the documented recovery path and is *post-seal analysis*, not automated discovery; `spike/blind-hunt/analysis/findings.md` keeps the halves apart.
- **fixed — open.** Not attempted.

**The second campaign ran (2026-08-14, campaign 2 under ADR 0015): null result on abook 0.6.1, and criterion 1 stays open.** khard — first in the inherited order — was burned before Seal B: its red suite let the checker's leading query run over deliberately mis-shaped stores, committing the target's failure response pre-seal (the burn, the machine reselection, and the full disclosure are in the campaign ledger and PR #110). The sealed predicate then selected abook. Its declaration — three `--convert` forms including the observed refusal as an `expected_status = "1"` operation, the recovery-path rule discharged vacuously because the documentation names no recovery command at all — was machine-verified to precede exploration: **ALL SEAL CHECKS PASSED (R1 audited)** (the committed transcript `spike/blind-hunt2/analysis/verify-seals.txt`), exploration head == Seal B in a clean tree, engine and shim byte-equal to the sweep's (R3). Every crash world satisfied the declared invariants (import 2+1 worlds, export 2+1, refused 1+1; violations 0), with the engine's falsification gate proving the checker red on corrupted state after the seal (`spike/blind-hunt2/analysis/findings.md`). A null campaign is the protocol working, not failing — the same honesty that scored timewarrior *partial* and the misfire *not counted* also records "nothing found" without inflating it. Remaining unconsumed candidates in the sealed order: khal; hledger refused at sweep (reason sealed, unread). Whether to run a third campaign is a resourcing decision, deliberately not fixed here.

**The third campaign ran (2026-08-14, campaign 3 under ADR 0016): null result on khal 0.14.0, and criterion 1 stays open.** The inherited order (khard burned, abook consumed) selected khal by the sealed predicate over a fresh sweep (khal 0 / hledger 2, reason still sealed unread). Its declaration — import of a fixed-UID .ics as the live search, import-update and new with pre-registered refusal expectations, the recovery-path rule vacuous over the full help set plus the version-pinned usage page — was machine-verified to precede exploration: **ALL SEAL CHECKS PASSED (R1 audited)** (`spike/blind-hunt3/analysis/verify-seals.txt`). Every crash world satisfied the declared invariants — import 10+1 worlds, update 21+1, new 10+1, violations 0 — and both pre-registered refusals did not fire: the recordings were accepted and explored in full, which is wider coverage than the declaration promised itself. The vdir/iCalendar storage-class disclosure (todoman, explored by this project) is discharged in the declaration and the findings. Remaining unconsumed candidate: hledger, unselectable while its sweep refusal stands; understanding that refusal means unsealing it — deliberately not done. **Two designated-path campaigns have now returned null.** Whether criterion 1's remaining path is more campaigns, a different target class, or §18's kill analysis is a resourcing and judgement decision, deliberately not made in a status paragraph.

**Criterion 1 redesigned (2026-08-15, ADR 0017): provenance is labeled, not gated.** The sealed candidate pool was run to exhaustion first — one non-novel find (topydo), two nulls (abook, khal), the last sealed candidate unselectable behind an unread refusal; a fourth campaign under fresh seals remains possible per ADR 0012 and declining it is a resourcing judgement. The assisted experiment (#118, its scoring rules pre-committed in the issue after the nulls were known and before any assisted run) recorded an inversion: question quality 5/5, the binding constraint the judge's reach. The three measured syscall gaps closed the next day (#121, #122; the fourth gap, exec, is #123 and deliberately deferred), and the same committed defines reached verified, replay-confirmed counterexamples on stow, devtodo and buku — calcurse was verified before the gaps closed and is the control (`spike/assisted/REMEASURE.md`). The criterion now requires the judge's discovery from an invariant committed before any observed failure, with provenance labeled; novel/author-confirmed/fixed/replayed are unchanged and all still open — novelty is deliberately unchecked for all four assisted findings, and the tracker searches are the designated next step *(they ran the same day; next paragraph)*.

**The assisted findings' next legs ran (2026-08-15): novelty four-for-four, two upstream reports standing, buku withdrawn.** The recorded tracker searches (`spike/assisted/NOVELTY.md`, positive controls throughout) found none of the four previously reported. The report step then applied two harder gates in sequence: reproducibility with tooling a maintainer already has (strace fault injection), and fairness at target selection (now a PROTOCOL.md selection-time rule). Outcome: calcurse and stow reported and standing (`lfos/calcurse#529`, `aspiers/stow#139`); devtodo's report filed and withdrawn on the fairness rule, its finding staying in-repo; and buku's finding **withdrawn entirely** — its one remaining leg was a misread of the falsification gate's output, and buku's own recovery-open succeeds in every crash world (`spike/assisted/buku/RUNLOG.md`, Correction section). The count of assisted findings carrying a live contract-level claim is therefore three (stow, devtodo, calcurse); buku remains a verified engine-level L0 observation sitting inside sqlite's documented recovery contract. Author-confirmed / fixed / replayed remain open on all three.

A null result was budgeted for and, in the first campaign, did not happen; campaigns 2 and 3 then spent that budget twice (the abook and khal nulls above). What remains after the redesign is the novelty/confirmation/fix/replay work on the assisted findings — the legs the redesign deliberately did not touch.

## Sequencing rationale

- **Linux before macOS:** retire engine risk before platform risk.
- **Built-in invariant before checkers:** zero-config value first; L0 is also what agent callers use.
- **Dogfood after the Define contract is complete:** omamori's interesting invariants need L2.
- **Loop closure last:** it tests the report format, which should be stable by then.

## Risks, ranked

1. **Interposition spike fails** or crash points are not deterministic → v0.1 exists to learn this in week one; kill or redesign early.
2. **UNKNOWN dominates in practice** → measured from v0.1 onward; explicit kill criterion.
3. **Define burden creeps** past three commands and a directory → the contract is a budget (DESIGN §12); a breach is a warning sign, not a growth opportunity.
4. **omamori is too hardened to yield a novel bug** → the calibration target in v0.5 separates "the tool is weak" from "the target is strong".
5. **Name is a common word; PyPI/npm taken** → accepted on 2026-08-10; distribution is a single binary.

## Out of scope through 1.0

Everything in DESIGN §15, unchanged: network faults, clock manipulation, thread scheduling, distributed systems, remote consistency, security scanning, static analysis, AI code review, formal verification, GUI, cloud, LLM verdicts, badges.

Power failure / torn writes is first in line for *consideration* after 1.0 (DESIGN §21) — not before.
