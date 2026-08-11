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

### v0.3 — The full Define contract

**Goal:** the three-commands-and-a-directory contract of DESIGN §12, complete.

Scope:

- L1 success markers and post-success invariants (the program's stdout claims, held against it).
- L2 checker scripts (fresh process, after restart, exit code = verdict).
- Checker falsification before every run (corrupted state must FAIL the check, else UNKNOWN — DESIGN §14-13).
- Shrinking: earliest/simplest failing crash point selected and reported.
- Case storage with landing context (DESIGN §14-14), and `sideeye replay <case>` on top of it.

Acceptance:

- The doctor-cross-examination scenario runs end-to-end against a toy target.
- Conditional-invariant vacuity is covered by tests: a killed run never satisfies the success marker, and the suite asserts that L1 worlds are the strict subset where the marker appeared.

### macOS native — absorbed into v0.1

**Goal:** the second platform DESIGN §9 committed to, with honest edges.

Delivered in v0.1, ahead of its slot: macOS interposition with an identical CLI and contract, and a parity assertion in CI (identical scenario, identical verdict and crash point on both OSes). What remains of the original scope is one honesty gap, tracked as #10: an Apple platform binary can never be observed, and the report says `no_shim_marker` without naming why. No longer a numbered milestone.

The original scope, for the record:

- macOS interposition; identical CLI and contract.
- Hardened-runtime / library-validation targets detected and reported as unsupported (exit 2) — never silently mis-tested. Same for statically linked Linux binaries.
- A parity suite: identical scenarios must produce identical verdicts and equivalent crash points on both OSes.

Acceptance: parity suite green on macOS and Linux; unsupported-target detection falsified once per OS.

### v0.4 — Dogfood: omamori

**Goal:** evaluate the primary success criterion (DESIGN §17) for real.

Scope:

- Run Sideeye against omamori's stateful operations (its state is file-based; it qualifies under DESIGN §9 constraints).
- Regression-case stability in practice: saved cases replayed across real code changes; context mismatch must produce "case no longer applies", not a silent pass.

Acceptance: DESIGN §17's primary criterion evaluated honestly — either a novel, author-confirmed crash-consistency bug, or a written analysis of why none was found. The analysis feeds the kill criteria (DESIGN §18); this step cannot be skipped or softened.

### v0.5 — The loop closes

**Goal:** prove the counterexample is agent food, and calibrate detection power.

Scope:

- The report JSON documented as a schema; a quickstart for CI (GitHub Actions example).
- Loop-closure test (DESIGN §17, second criterion): a coding agent receives only the report and the repository, and must produce a fix that makes the replay pass — no human translation.
- Calibration target (DESIGN §18): at least one deliberately average stateful CLI with no hand-written adversarial tests, explored with honest results.

Acceptance: loop closure demonstrated end-to-end at least once; calibration results published in the buildlog, whatever they are.

### v1.0 — Contract freeze

Entry criteria — all must hold, none may be argued around:

1. Primary success criterion met: a real, novel, author-confirmed crash-consistency bug found by Sideeye (on omamori or the calibration target), fixed, and kept as a replayed regression case.
2. Loop-closure criterion met: an agent fixed a finding from the report alone.
3. Kill criteria (DESIGN §18) reviewed against collected data; none triggered.
4. UNKNOWN rate on supported targets measured and published; a target threshold is set from that data (not invented in advance) and met.
5. Contract frozen: config format, report schema, exit codes, replay compatibility.
6. Docs: a fresh machine reaches its first exploration in under ten minutes from the README.

If criterion 1 cannot be met, v1.0 does not ship — the kill analysis ships instead.

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
