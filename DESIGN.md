# Sideeye — Design Document

**Status:** implemented and released through v0.13.0; the v1.0 contract freeze is tracked in [PRD.md](PRD.md)
**Name:** Sideeye (confirmed 2026-08-10)
**Tagline:** *Sideeye doesn't believe it.*
**Initial focus:** process crash × persistent state consistency

---

## 1. Overview

Sideeye deliberately removes software from the well-behaved world it was written for, and searches for a replayable counterexample that breaks a property its developer declared must hold. It is a mean-spirited reviewer.

Ordinary tests define inputs and expected outputs. Property-based testing defines properties instead of examples and generates many inputs. Sideeye is closer to the latter, but what it varies is not primarily the input — it is the world the program runs in.

Developers do not write piles of failure scenarios ("kill here", "fail that write"). They declare invariants: *if the operation said it succeeded, this must still be true after a restart.* Sideeye searches for a world that breaks the invariant and, when it finds one, returns a minimal, reproducible counterexample.

The long-term surface includes process crash, persistent state, network, clock, concurrency, and partial external effects. v0 deliberately learns exactly one kind of malice: **process crash against persistent state.** The philosophy stays broad; the first cruelty is narrow.

## 2. Problem

AI coding agents write code faster than humans can understand its failure semantics. Happy paths, common error handling, and unit tests are generated in minutes; questions like *what is left on disk if we die halfway?* or *is the state actually consistent after a restart that follows a reported success?* still depend on human attention.

Outside databases and distributed systems, adversarial testing is not a normal part of development. Ordinary CLIs, developer tools, daemons, and desktop applications work fine for months, then fail at the first coincidence of a crash, a partial state update, and a restart.

The problem Sideeye attacks is not "not enough tests." It is that **failure worlds the developer never imagined cannot be verified by enumerating them as test cases in advance.**

## 3. Product Thesis

**Sideeye is a deterministic adversarial gate for the coding loop.**

The bet has two halves:

1. Asking developers for **invariants** — and letting Sideeye invent the failures and shrink the counterexamples — is what makes adversarial testing viable for ordinary software development.
2. In a loop where more and more code is written by LLMs, **the skeptic must not be one.** A gate only works if its verdicts are deterministic, reproducible, and machine-consumable.

Sideeye does not aim to invent new fault-injection primitives. Property-based testing, shrinking, fault injection, crash-consistency testing, Jepsen-style adversarial verification, and deterministic simulation all have long lineages. Sideeye's bet is on bringing those ideas to ordinary stateful software as an invariant-first developer experience — cheap enough to sit inside the loop:

```
write → test → sideeye → review → ship
```

## 4. Core Principles

### 4.1 Ask for invariants, invent the failures

The central thing a user writes is not *how to break the software* but *what must not break.*

Invariants come in two shapes, and the distinction matters:

- **Always-invariants (crash atomicity).** For every crash point: after restart, the persistent state is either the complete old state or the complete new state, and diagnostic commands must agree with reality. These hold unconditionally across every explored world. They are the workhorse of v0.
- **Post-success invariants (durability).** In worlds where the operation reported success before dying, the new state must survive restart. Sideeye records what the program claimed on stdout up to the moment of the kill, and holds the program to its own words.

A conditional invariant of the form "if it succeeded, then…" is vacuously true in most crash worlds — the killed operation never reports success. Sideeye's defaults are therefore built on always-invariants; post-success invariants are the sharper, optional layer.

### 4.2 Break worlds, not just inputs

Sideeye does not primarily generate strange inputs. It takes a normal input and breaks the environment's promises partway through — the process dies. The question is not *what if the input was bad* but *what if the world was not convenient.*

### 4.3 Counterexamples, not warnings

The central artifact is not a warning or a risk score. It is a reproducible counterexample.

Bad output:

> Possible inconsistency during state replacement.

Desired output:

> For an execution where `rotate-key` reported success, killing the process at a specific point leaves no valid key after restart while `doctor` still reports healthy. Reproduce in 3 steps.

"This might be dangerous" loses to "this actually broke, here is how."

### 4.4 Shrink aggressively

The first failure scenario Sideeye finds may be complicated. It is never handed to the developer as-is: unnecessary conditions are removed until only what is required to break the invariant remains. Failure *reduction* matters as much as failure *discovery*.

In v0 the search space is (one operation × crash points), so shrinking degenerates into choosing the earliest, simplest failing crash point. That is a benefit of the scope, not a limitation of the idea; shrinking earns its name once operation sequences arrive.

### 4.5 Never overclaim

Sideeye is suspicious of itself too. "Found no counterexample" and "proved it safe" are different sentences.

Results distinguish, at minimum:

- **PASS** — no invariant violation found within the declared exploration.
- **FAIL** — a reproducible invariant violation was found.
- **UNKNOWN** — the result could not be judged correctly.
- **NOT TESTED** — this area was not part of the verification.

PASS never means "crash-safe" as an unbounded claim. This vocabulary is enforced by the exit-code contract (§13), not by prose.

### 4.6 Failure is part of product behavior

Behavior under failure is product behavior, exactly like behavior under success. "Anything goes, it was an error path" is not accepted. In particular, three things are treated as explicit contracts: the state after a reported success, the state observed after a restart, and the state a diagnostic command reports.

### 4.7 The skeptic is not an LLM

Everything that affects a verdict — exploration, violation detection, shrinking, replay — is deterministic and does not involve a language model. LLMs are welcome at the edges: proposing invariants on the way in, explaining reports on the way out. **They never decide PASS or FAIL.**

In a development loop where the code author is increasingly an LLM, the reviewer's value is precisely that it is not one.

## 5. Product Personality

Sideeye is not a clever AI reviewer. It does not read your code and generate ten concerns.

Its personality is the suspicious senior reviewer with unreasonably good instincts. "The tests pass" gets *"and if it dies halfway?"* "We retry" gets *"and if the previous attempt half-succeeded?"* "Doctor says healthy" gets *"and if doctor is wrong?"*

The personality lives in the product's stance, not in the output. Findings are calm, unambiguous, and machine-usable. *Sideeye doesn't believe it* is an attitude, not a tone of voice.

## 6. Why Sideeye, Why Now

As implementation gets cheaper, sustained human suspicion becomes relatively more expensive. With more code, faster change, and multiple agents editing in parallel, no human reviews every failure path in their head.

What the loop needs is not only a faster generator. It needs something that **doubts at the speed the generator writes.**

Sideeye is not an AI-only tool. But it is designed, from v0, to be *callable by agents*: non-interactive, machine-readable, exit-code honest. This section is not background color — it is where the output-contract requirements in §13 come from.

## 7. What Makes Sideeye Different

Three differences are the point; none of them is a new primitive.

1. **Ordinary software.** Adversarial testing for CLIs, local developer tools, and small daemons — not only for databases and distributed systems.
2. **Invariants first.** Users write "if the operation succeeded, this property holds after restart" — never "SIGKILL here, then fail this write."
3. **Replayable counterexamples as the deliverable.** Evidence a developer (or an agent) can paste into an issue, a regression test, and a fix verification, unchanged.

Whether Sideeye deserves to exist is decided by whether these three can be made *easy* for ordinary developers.

## 8. Design Lineage

Sideeye comes from a lineage of projects (omamori, llm-key-ring) whose recurring theme is refusing to trust reported success: measure before believing, falsify a new guard once before trusting it, never treat an unverified state as success. Sideeye turns that habit of suspicion itself into a standalone tool.

Someone else building on the same ideas would likely make a fault-injection framework or a chaos-testing tool. Sideeye's identity is not the number of things it can break. It is the stubbornness: refuse vague success, produce an actual counterexample, shrink it, bring it home.

## 9. v0 Scope

v0 answers one question:

> **If the process dies partway through a stateful operation, do the developer's declared invariants still hold after restart?**

Typical targets: config updates, key rotation, state migration, index updates, cache metadata, audit state, anything around a local database.

### The crash model, precisely

v0's crash is a **process crash** (SIGKILL-equivalent): the OS survives. Every write the process completed is durable; nothing is lost or reordered. Power loss and kernel panics — where unsynced data vanishes and write order gets rearranged — are **outside this model, and a PASS says nothing about them.**

This limitation is a focus, not a weakness. The bugs that surface under the process-crash model are pure logical-ordering bugs — delete-then-create, missing temp+rename, print-success-then-write — exactly the class ordinary software is dense with. It also keeps the engine simple: no filesystem simulation is required.

### Known constraints (declared, not hidden)

- Targets must keep persistent state in **files or directories Sideeye can snapshot and restore.** State in system keychains or remote services is out of scope.
- v0 targets **dynamically linked executables.** macOS binaries with hardened runtime + library validation, and statically linked Linux binaries, cannot be observed by the intended mechanism; Sideeye reports them as *unsupported* instead of pretending.
- A target that **creates other processes** is explorable when an oracle can account for all of them — the rule is that no process other than the subject touched the state directory, and it requires an oracle — `--oracle` on Linux, and on macOS `--oracle-fs-usage`, which buys the same account for the price of root on the run (ADR 0031). A target that `exec`s over itself is judged when the carried operation count survives the image change (since contract v10, ADR 0018) and refused when the chain breaks; one that creates threads or leaves the containment group is refused, and so is any process boundary on a platform without an oracle.
- v0 runs **natively on macOS and Linux.** (On macOS, every language is forced through libSystem, which makes userspace interposition a single mechanism covering Rust, Go, Python, and friends; the same approach covers dynamically linked Linux binaries.)

### Not in v0

Network failure, clock manipulation, multi-process races, distributed systems, and partial remote effects are not goals for v0. They remain future possibilities — not before the first product value is proven.

## 10. Primary Users

Sideeye has two users per run, and they are usually different parties:

- **The caller** is often not a human: a CI job or a coding agent invoking `sideeye` non-interactively and branching on its exit code.
- **The reader** is a human — or an agent acting for one — who receives the counterexample and decides what to do.

The first human audience is OSS and developer-tool authors who:

- build stateful CLIs or local applications,
- have decent normal-path tests,
- care about crash consistency but will never write tests for every failure point,
- keep state in copyable files and can check it after a restart,
- want reproductions, not warnings.

The first dogfood target is **omamori**. Not a product requirement — but its author understands its internal state and failure semantics, and it already carries many hand-written adversarial tests, so it sets a deliberately high bar for whether Sideeye can beat existing human tests. (See §17 and §18 for the calibration risk this creates.)

## 11. Core User Story

As a developer, I declare the property a stateful operation must keep, and let Sideeye explore the worlds where that operation crashed halfway.

When Sideeye finds a violation, I receive the shortest possible reproduction and observation — not an essay about risk.

After I fix it, I replay the same counterexample and watch it stop reproducing.

When the developer in this story is a coding agent, nothing changes except that nobody is watching: **the report has to be actionable without a human translating it.**

## 12. Conceptual UX

Three verbs, nothing else: **Define. Explore. Explain.**

- **Define** — the target operation and the property that must hold after it (or after a restart).
- **Explore** — Sideeye searches crash worlds of that operation. Where to crash and what state survives are Sideeye's responsibility, not the user's.
- **Explain** — on a violation, Sideeye shrinks the counterexample and returns the minimal conditions, the expected state, the observed state, and the measured reproducibility.

### The v0 contract (a budget, not an implementation spec)

What a user writes in v0 is **three commands and one directory:**

```toml
# sideeye.toml
[world]
state = "./state"                 # the directory Sideeye snapshots and restores

[define]
setup     = "mytool init"         # produce the initial state
operation = "mytool rotate-key"   # what Sideeye kills partway through
check     = "./check.sh"          # runs after crash + restart, in a fresh process
                                  # exit 0 = invariant holds
```

If Define ever needs more than this, that is movement toward the kill criteria in §18, and we should notice.

Noticed three times, deliberately, and recorded each time: `marker` joined with the L1 layer (ADR 0008), `expected_status` joined for targets whose success convention is a non-zero exit — git-style tools were unjudgeable without it (ADR 0014) — and the argv form joined for the argument a space-split string cannot spell, after the #84 sweep measured the script-file escape hatch being refused structurally for exactly the targets that needed it (ADR 0019). The third is not a key at all but a second value shape for the existing commands; the sentence above covers shapes as much as keys, and a sixth key — or a third shape — should face it again.

Faced a fourth time, for `cwd`. §18 has no row about Define growing — the sentence above says growth is *movement toward* those criteria, and the two it moves toward are row 6, setup too heavy for ordinary software, and row 2, defining invariants costing about what ordinary failure tests cost. Against those two the answer is that this key removes setup rather than adding it: what it replaces is a launcher script the author had to write and commit beside the define, which is strictly more setup than a line in the file. It also says nothing about the target's behaviour, which is the shape that would make a define grow toward row 2 — a declaration that has to spell out what the tool does is a judge that has stopped being able to watch. It says where the engine starts it — a choice every caller already had except one. The MCP server is handed a config path and starts the engine itself, so the directory was settable by everyone but the caller this tool exists to serve, and the flag added alongside the key only restates at the CLI what `cd` already did. The gap's measured shape is in this repository: `spike/cohort3/*/ops/explore.sh` are committed launchers whose content is a `cd` and some environment, written because the define could not carry them. What would count as Define growing, and stays refused, is a key describing the target's behaviour rather than its invocation. The environment is the nearest sibling and was deliberately left out: `SIDEEYE_MCP_CHILD_ENV` and the CLI's inheritance already give every caller a way to set it, so it fails the "no other way to say it" test `cwd` passes.

Define has three levels; the lower ones are zero-effort:

- **L0 — built-in invariants, zero config.** Sideeye ships general invariants it can judge without any checker. The first is **atomicity**, stated per file rather than per directory: for every file present in *both* the pre-operation snapshot and the post-operation result, the state after restart must still contain it, holding either the old content or the new one — never a mixture of the two. An agent can point `sideeye` at an operation and get value with no configuration at all.

  The obvious wording — "the state directory must equal the pre-operation snapshot or the post-operation result" — is stricter than it looks, and wrong. A program that writes atomically leaves `key.json.tmp` behind in every world killed between the `open` and the `rename`, so the directory equals neither snapshot and the *correct* program is reported as violating the built-in invariant. Files that appear in only one of the two snapshots are therefore left unconstrained.

  This is deliberately narrower than the directory-equality reading, and the difference is worth naming: L0 does not catch a crash that leaves temporary files behind forever, or one that creates a file the operation never produces on a clean run. Those are real defects, and L0 stays quiet about them. They belong to a checker (L2), or to a future built-in invariant stated in terms the correct program can actually satisfy.

  L0 carries a second per-file form, chosen from the snapshots alone (ADR 0004). A file whose post-operation content strictly extends its non-empty pre-operation content — the shape of logs, journals and audit chains, whose appended bytes may legitimately differ between runs (timestamps, HMAC chains) — is judged by **history preservation** instead: after the crash the file must still be a file whose content begins with everything it held before the operation. The appended tail is not judged; whether a torn tail is acceptable is the target's recovery semantics, and belongs to a checker. Every report names which files were judged by which form, and `not tested` grows "appended tails" whenever this form is in play. A file that is empty before the operation stays on the pre-or-post rule — the preserved history of an empty file would constrain nothing.
- **L1 — the program's own words.** Declare a success marker (a pattern on stdout). In worlds where the marker appeared before the kill, Sideeye additionally enforces the post-success invariant (§4.1).
- **L2 — domain checkers.** A checker script for what only the author knows — for example, cross-examining a diagnostic command:

```sh
#!/bin/sh
healthy=$(mytool doctor --json | jq .healthy)
loadable=$(mytool load-key >/dev/null 2>&1 && echo true || echo false)
[ "$healthy" = "$loadable" ]   # FAIL when doctor's claim contradicts reality
```

The check always runs **after a restart, in a fresh process.** In-memory state hides corruption; v0 never evaluates invariants inside the crashed process's lifetime.

## 13. Output Requirements

The most important UI is the counterexample report. It ships in two forms: **JSON for the caller, text for the reader.** The JSON is the complete record — every field a machine might gate on, including the ones no human wants in a verdict (`schema`, `contract_version`, `exit_code`). The text is the reader's view of the same run, and the worked examples below are what it actually looks like: a short summary, not a second copy of the JSON. **What binds them is that a value both forms carry has one definition** — the JSON reads the same note the text prints, never a second formatting of it. Two things hold that: `spike/check-report-schema.py`'s fifth claim, for every value the JSON writer passes through `jsonString`, and — for `not_tested`, which is appended directly and so falls outside that claim — a comptime table plus acceptance check 2nt, which reads one real report in both forms and requires them to agree. This sentence used to read "two forms with identical content". Its own examples below contradicted it: eleven lines for the FAIL and three for the PASS, against a document of twenty top-level fields (`docs/report-schema.md` carries that one; this section shows no JSON). Ruled 2026-09-01 (owner, #280) in favour of the examples.

A FAIL, as the reader sees it:

```
FAIL  case sideeye-000042
invariant  : check.sh exited 1  (always-invariant)
operation  : mytool rotate-key
crash point: after unlink("state/key.json"),
             before rename("state/key.json.tmp" -> "state/key.json")
             (file-op 3 of 5 — landing evidence recorded)
observed   : doctor: healthy=true / loadable key: none
expected   : doctor's claim matches reality
reproduce  : sideeye replay 000042        (reproduced 10/10)
explored   : 5 crash points, 5 restarts, 5 checks
not tested : power loss, torn writes, concurrent processes
```

And a PASS:

```
PASS  rotate-key: 5/5 explored worlds satisfied the invariant
      checker falsified before run: corrupted state -> check exited 1  [ok]
      not tested : power loss, torn writes, concurrent processes
```

Every report includes:

- which invariant was violated,
- what was expected and what was observed,
- the **logical crash point**, with recorded evidence that the crash landed there,
- the minimal reproduction steps,
- measured reproducibility (not assumed),
- what Sideeye did **not** verify,
- a stable case ID for replay after the fix.

Crash points are addressed logically ("after unlink, before rename"), never by raw counters alone. When a saved case is replayed against changed code and its context no longer exists, Sideeye says *"case no longer applies"* — it never silently verifies a different point.

### The exit-code contract

This is where §4.5 stops being prose:

| exit | meaning |
|------|---------|
| 0 | **PASS** — no violation found within the declared exploration |
| 1 | **FAIL** — reproducible violation found |
| 2 | **UNKNOWN** — could not judge (environment artifact, checker failed to run, unsupported target) |
| 3 | **SETUP ERROR** — configuration or environment problem before exploration began |

UNKNOWN is never 0. A caller that treats UNKNOWN as success has to do so deliberately, in its own code, against the contract.

The table maps **verdicts** to codes. Commands that reach no verdict are outside it: `version`, `help` and an accepting `preflight` all exit 0 for doing what was asked. `preflight --twice` (#199) adds the one negative that shape needs — exit 1 when the two observed runs left different state — which is the answer to an identity question, not a crash-consistency FAIL. The verdict-to-code mapping the freeze pins is untouched by it.

## 14. Functional Requirements for v0

1. Define one stateful operation as the verification target.
2. Define invariants evaluated after the operation or after restart.
3. Explore execution worlds where the process crashes at multiple points of the operation — process crash only.
4. Restart or re-evaluate the target from the crashed state.
5. Detect invariant violations.
6. Save violations as reproducible cases.
7. Shrink discovered cases by removing unnecessary conditions.
8. Replay past counterexamples as regression cases after a fix.
9. Never treat an unverified or unjudgeable state as success.
10. State explicitly, in every result, what Sideeye did and did not verify.
11. Start every crash world from an identical initial state; snapshot and restore the state directory; no leakage between worlds.
12. Include exploration counts (crash points, restarts, check executions) in every report.
13. Falsify the checker once before exploring: a deliberately corrupted state must make the check FAIL; otherwise the run is UNKNOWN, not PASS.
14. Record crash landing context in every counterexample; on replay, report "case no longer applies" when the context no longer matches.
15. Emit machine-readable output (JSON) alongside human-readable text, honoring the exit-code contract of §13.
16. Operate fully non-interactively, suitable for CI and agent callers.

This document still does not choose OS primitives or interception techniques. It acknowledges one thing: the combination of *reproducible logical crash points* and *native macOS + Linux support* pushes the mechanism toward userspace interposition. The feasibility spike for that is the first task on the roadmap (see PRD.md).

## 15. Non-Goals for v0

- Arbitrary syscall fault injection in general.
- Network fault injection.
- Clock manipulation.
- Thread scheduling control.
- Full deterministic execution.
- Distributed system verification.
- Remote service consistency.
- Security vulnerability scanning.
- Static analysis.
- AI code review.
- Formal verification.
- A universal failure-modeling language.
- GUI.
- Cloud service.
- Organization-wide chaos engineering platform.
- **LLM-based verdicts.** Sideeye never uses a language model to decide PASS or FAIL. Not in v0, not later.
- **A badge.** "Passed Sideeye" is not a certification, and we will not make it one. The product's output is counterexamples, not reassurance.

Being able to implement any of these is not a reason to build them before v0's value is proven.

## 16. What Sideeye Did Not Invent

Property-based testing, shrinking, fault injection, crash-consistency testing, deterministic simulation, and Jepsen-style adversarial verification are not Sideeye's inventions, and this document does not pretend otherwise.

The closest neighbor in spirit is **ALICE** (OSDI '14): ordinary applications, user-defined checkers, systematic exploration of crash states. CrashMonkey/ACE explored the filesystem side; LazyFS and dm-log-writes serve the power-failure model; QuickCheck and Hypothesis proved invariant-plus-shrinking as a developer experience.

What that lineage proved: systematically exploring worlds the developer did not imagine finds bugs ordinary tests cannot. What remains unproven — and what Sideeye exists to test — is whether that idea can become an **invariant-first, everyday developer experience for ordinary stateful software.** Sideeye's value is measured by how far it carries those ideas into normal development, not by hiding where they came from.

## 17. Success Criteria

The success metric for v0 is not feature count, fault-type count, or GitHub stars.

**Primary criterion.** Sideeye finds a crash-consistency bug that the target's own hand-written tests do not catch — discovered by its deterministic judge from an invariant declared and committed before this project observed any failure of the target in execution (reading a report of a failure while scouting is not observing one), with the question's provenance recorded and labeled: blind (ADR 0012's two-seal protocol) or assisted (a scout read the target; the scout and its sources named). (Redesigned 2026-08-15 in step with PRD criterion 1, ADR 0017; the prior form limited the venue to omamori, the calibration target, or a blind-protocol target — that family itself added 2026-08-13, before any blind campaign ran. Blind remains the stronger provenance; nothing assisted may borrow it, and the ordering requirement keeps timewarrior's "partial" scoring below exactly where it is.) For that bug, all of the following must hold:

- Sideeye discovered it automatically.
- The counterexample is reproducible.
- The counterexample is small.
- The author judges it a real bug or genuinely incorrect failure semantics.
- After the fix, the same counterexample stops reproducing.
- The counterexample is kept as a regression test.

**Second criterion — the loop closes.** Give a coding agent nothing but the counterexample report (JSON + replay command) and the repository. If the agent can produce a fix that makes the replay pass, without a human translating the finding, the report format has met its real audience. A report that needs human interpretation fails the positioning of §3, however correct it is.

**Second criterion status (2026-08-13): met — twice, on the timewarrior finding, through both surfaces.** Two different models (claude-opus-5 and claude-fable-5, both Claude 5 family) each produced a real fix, independently deriving the same three fix targets as the human patch with different implementations. **Run 1 (CLI plumbing, opus)**: a context-free agent (fresh headless session, no memory, tool calls audited, no web use — the server-side web counters read zero) received the report, the case it names, the declared invariant the case points at, the pinned repository, and bug-blind replay plumbing — the input set is declared in the BUILDLOG protocol, and "what the report transitively names" is the honest subject, not "the report alone". The judge's own fresh replay passed (explored 2, all 24 crash points still addressed), a normal-world functional gate confirmed undo still works, and a full re-exploration of the fixed tree passed 25/25 (`spike/runs/sideeye-loop-1/manifest.json`). **Run 2 (the MCP surface, fable)**: the same sealed protocol with the replay carried by `sideeye_replay_case`, plus a third control proven first — the MCP channel itself giving opposite answers on the stage. Its gates: seal restore, fresh replay pass, non-degeneracy pass, audit clean (`spike/runs/sideeye-loop-2/manifest.json`); the run-1 secondary observations (full re-exploration, upstream suites) were **not repeated** for run 2 — its evidence is the three gates, stated as such. Both runs: apparatus first proven by mutual-contrast controls (unpatched must fail, known patch must pass). `spike/loop-closure-timew/`.

**First-condition closure protocol (2026-08-13).** The remaining gap — "discovered automatically" held only for the crash-world search — will be measured by a blind campaign under ADR 0012: candidates, their priority order, the selection predicate, the reference rules and the audit tooling are sealed in one public commit before any candidate is executed; the invariants and checkers are sealed in a second commit after the permitted contract reading and before the first crash measurement, and exploration runs only at that second commit. Three honesty bounds are part of the claim itself: the ordering is auditable to a reader who trusts the public push history, not proven against an author who measured privately first; the sweep's sealed reports are unread by working rule, with a committed hash that only makes later substitution detectable; and the experimenter is a language model whose training may contain public information about any target — the seals make the *recorded* consultations and the commit order auditable, while the ledger itself is self-reported. The targets are high-risk blind targets (file-backed state, several spanning multiple files, chosen on purpose), not a second average-target calibration; §18's calibration stands on timewarrior alone.

**Blind campaign result (2026-08-14, topydo 0.14).** The campaign ran to completion. Seal B is `5a034aff`; exploration ran from it in a clean tree and `verify-seals a21b0933 5a034aff <run-manifest> <sealed-reports>` returns **ALL SEAL CHECKS PASSED (R1 audited)** — the declaration's precedence over the first crash measurement is a machine-checked fact, at the strength the three honesty bounds above allow. Twelve of the thirteen declared operation forms produced a counterexample from the blind-declared conservation invariant; the one declared read-only form recorded no state-changing operations and passed. Scored against the six conditions:

- **"discovered automatically" — clean for the first time.** The invariant and checker were committed before any crash world of this target existed, and the search produced the violating worlds from them. No human read a trace, no hypothesis preceded the checker. This is the condition the timewarrior finding could only score *partial*, and it is the reason the campaign existed.
- **reproducible / small / kept as a regression — clean, and stronger than timewarrior's.** Each FAIL saved a case that replays in the pinned container with nothing else installed (`exit 1`, `the case reproduced`) — no target build, so these are CI-resident cases rather than a recipe (the gap `#82` named; the timewarrior side has since been closed as hygiene by the `timew-regression` CI job, which needs a target build each run and re-records under the current contract).
- **"the author judges it a real bug" — open.** Not asserted here. The sharpest observed behavior sits in the documented recovery path and is *analysis performed after the seal*, not automated discovery; `spike/blind-hunt/analysis/findings.md` separates the two halves explicitly.
- **"after the fix, the same counterexample stops reproducing" — not attempted.**
- **Novelty — checked 2026-08-14, split verdict.** The crash-window destruction is not novel as a phenomenon (`topydo/topydo#318`, the same failure surface under a disk-full write; this campaign adds the mechanism and a replayable case). The post-crash recovery misfire was not found in the tracker — novel as far as the recorded search sees, but it is the post-seal analysis finding, not the blind search's. No single finding holds "found by Sideeye" and "novel" at once; the PRD criterion-1 status carries the consequence.

These were high-risk blind targets, not a second average-target calibration; §18's calibration still stands on timewarrior alone.

**Three selection cohorts followed (2026-08-21 #183, 2026-08-22 #209, 2026-08-23), and through all three the primary criterion stayed open** *(ruled met 2026-08-25 — the closing note of this paragraph)*. Twelve further targets under a freeze published before each ran, and twelve outcomes plus one: **five walls that stood** (KeePassXC at the probe; Jujutsu on static linkage; Bun on threads; cargo on a raw-syscall rename; unison at the probe, on determinism), **one wall lifted** by declared apparatus and turned into a verdict (Borg, #200), and **seven verdicts** — two null-with-verdicts where the tool's own documented contract held in every world (Mercurial 107/107, Borg 119/119), two reproduced checker-red FAILs already on their trackers, one FAIL whose earliest violating world is L0-only, one PASS, and one FAIL through a declared checker carrying `checker_earliest` (himalaya, cohort 4). The measurements are worth reading for what they say about the six conditions above rather than the count: "discovered automatically" and "reproducible" held throughout — from frozen define to reproduced verdict in minutes — and on 2026-08-23 the combination that had been missing arrived. **himalaya is novel, automatically discovered and provenance-clean at the same time**, the first finding to hold all three; what the criterion still lacked when that was written on 2026-08-23 was the author's judgement, a fix, and a regression case that runs — and upstream supplied the first two the same day, fixing the bug in `io-maildir` 0.3.1 and closing the report. **One is left: a regression case that runs.** The saved case refuses against a build carrying the fix, because the fix adds an operation the recording does not contain (`spike/cohort4/himalaya-r2/upstream-fix/`). Records: `spike/cohort2/RESULTS.md`, `spike/cohort3/RESULTS.md`, `spike/cohort4/himalaya-r2/RESULTS.md`. *(Ruled 2026-08-25, owner adjudication of #305: "kept as a replayed regression case" accepts a second shape for a fix that changes the recorded operation sequence — the exhibit replays against the pinned buggy build, and the defect's absence on the fixed build is measured under controls rather than inferred. **The primary criterion is met.** PRD.md carries the ruling and what it deliberately gives up.)*

If the primary criterion holds, Sideeye has partially mechanized a human's way of doubting — not merely re-run existing tests.

**Status (2026-08-12).** The primary criterion is *not* met on omamori and is *substantially but not fully* met on the calibration target §18 requires. This is the survivable pattern §18 describes ("zero findings on omamori is survivable"), not a claim that omamori's criterion was transferred. On timewarrior — a stateful CLI with no hand-written adversarial tests — Sideeye found that a crash between the three commit renames leaves `timew undo` deleting an interval committed before the crash. Scored against the six conditions honestly, four hold cleanly and two carry real gaps:

- **reproducible / small / judged a real bug / stops after the fix** — clean. From the `reproduce` line and by hand with `cp`; one operation, a two-file window at crash point 14; judged real by this project's author (not yet confirmed by timewarrior's maintainers) and filed upstream as GothenburgBitFactory/timewarrior#778; a three-part patch reaches PASS 25/25 (measured).
- **"discovered automatically" — partial.** Manual trace triage seeded the target and the window: a human read the plain strace, confirmed by hand (with `cp` file surgery) that `undo` destroys committed data, and *then* wrote the checker. What Sideeye automated was the crash-world search — finding and minimizing the two violating worlds of nineteen from the human-declared invariant (§4.1, "ask for invariants, invent the failures"). The mechanized half is the search, not the hypothesis.
- **"kept as a regression" — replayed in CI since #82 (re-recorded each run, not a committed case).** The `timew-regression` job (`.github/workflows/ci.yml`) runs the committed measurement (`spike/dogfood-timew-replay.sh`, legs a–c) on every push to main and every pull request: build the pinned timewarrior, record the counterexample, replay it FAIL, rebuild with `spike/timew-undo-ordering.patch`, replay it PASS. The job re-records under the current trace contract each run, so a contract bump does not rot it. This is regression hygiene, deliberately not criterion-1 progress: under ADR 0017's ordering requirement the timewarrior finding stays "discovered automatically — partial" and does not enter criterion 1 whatever its regression form.

On omamori itself the criterion is not met; on `exec`, the operation this evaluation drove, it cannot be (the audit path is crash-safe by construction), and the guarded self-modification commands are not measurable under Sideeye's operation contract without break-glass — see §18.

## 18. Kill Criteria

Sideeye carries explicit failure conditions for itself.

If, after a defined dogfood period, Sideeye finds nothing beyond existing hand-written adversarial tests, the reasons are analyzed. The current direction is stopped or redesigned if any of the following holds:

- It is only useful when humans define failure scenarios in bulk.
- Defining invariants costs about as much as writing ordinary failure tests.
- Counterexamples are too complex to use for actual fixes.
- False positives or environment artifacts make it untrustworthy.
- Reproducibility is too low for findings to serve as evidence.
- Setup is too heavy for ordinary software.
- No UX difference over existing specialized tools can be demonstrated.
- **UNKNOWN dominates:** if a large share of runs on supported targets end UNKNOWN, Sideeye cannot function as a gate, whatever its detection power.

**Reviewed (2026-08-16).** Every condition above has been reviewed against the collected data for v1.0 entry criterion 3 — the review is `docs/kill-criteria-review.md`: none triggered. Row 7 (the UX difference) is scored there as an owner adjudication, its missing head-to-head disclosed; row 2 is scored on the recorded absence of the comparison it asserts; the rest are scored on committed measurements. The review reopens on any future measurement landing on a condition's trigger side.

**Re-reviewed (2026-08-26, #240).** The three selection cohorts' twelve targets have now been entered against all eight rows, in a dated re-review section of that same page. Six rows are corroborated or unchanged; **two carry evidence on their trigger side** — row 4, where Borg's three L0 violations sit in the client cache the apparatus itself relocated, and row 6, where Mercurial's define took four revisions to reach a verdict and Borg's wall fell only to a three-piece declared apparatus. **The reopen condition above has fired, and the re-score is pending owner adjudication**: no verdict was moved, and criterion 3's status in `PRD.md` was not changed. The re-review also re-checked the page's own "one instrument read eight ways" note and found it strengthened rather than weakened **on the instrument axis** — cohort 3 inherits cohort 2's probe gate and cohort 4 sources its predicates in place, so the three cohorts are not three independent apparatuses. Whether their twelve distinct targets and their own checkers add independent evidence is a separate question, and the note does not settle it.

**Adjudicated (2026-08-27, #240): neither reopened row is triggered, and criterion 3 stays met.** Row 4's case is recorded as a second example of an existing class — "tools with non-durable scratch files", precision limit #35 — rather than a new one, adding the property that a target-created scratch path can be relocated into the judged root by the measurement setup rather than sitting there from the start; it is not triggered because the file is a client cache outside the durable repository state Borg's transactional claim covers, and a checker carrying that claim ran in all 119 worlds and held in all of them. Row 4's ruling gives up two things: it does not establish that the relocated file's own documented recovery was exercised successfully (the checker attempts a deletion-and-rebuild but the call is unchecked and the committed drill records it failing on permissions), and it does not cover a relocated path judged by the built-in form with no checker carrying the target's claim at all — either of which reopens the row.

**Row 6's ruling is a definition, and it is the one this section carries.** *Declared apparatus is the instrument's cost and is not setup for the purposes of the condition above.* Apparatus means, narrowly: (a) declared in the public protocol before the define ran, and (b) constraining the **environment** the target runs in — clock, entropy source, kernel copy primitives and the like. **Anything that touches the target's own installation, configuration or state is setup and is not excluded by this definition**, whatever it is called in a protocol. Two further bounds, because (a) and (b) alone are not enough: the control must be **measurement-only and behaviour-preserving** — it may make an execution observable or repeatable, not supply behaviour the target would otherwise have to obtain — and **provisioning what the target depends on is setup**, including a service it needs, a database, credentials, or a stand-in for any of them, however it is injected. A shim that answers a kernel copy primitive in userspace is apparatus; a shim that emulates a network service the target requires is setup wearing a shim's clothes. The cost of revising a define until it reaches a verdict is likewise excluded from this condition by the same adjudication. Where it does belong is left open rather than assigned: the cohort-2 revisions changed state placement, a checker leg and a `sendfile` workaround with the question bytes unchanged, so they are measurement and define-packaging costs and are not evidence for the invariant-authoring comparison two rows above either. **A usage note, because the records say the word more loosely.** `spike/cohort2/borg-r3/RUNLOG.md` places its violating worlds in "the client cache the apparatus itself relocated", meaning the measurement setup taken as a whole. That relocation was the define's r2, not something declared before the define ran, so it does **not** satisfy (a) and is **not** excluded by this definition — it is a define revision and falls under the sentence above. Where this section says apparatus it means the narrow sense defined here, and a protocol cannot widen the exclusion by calling something apparatus after the fact. `docs/kill-criteria-review.md` carries the reasoning, the rejected readings and what each ruling gives up; `PRD.md` carries the criterion's status.
<!-- criterion-3-status: PRD.md -->

The current status of criterion 3 is carried by `PRD.md`'s status line; the dated paragraphs above — the review, the re-review and the adjudication — are the events that produced it, and `spike/check-criterion3-status.sh` holds this section to pointing rather than asserting (#356).

**Calibration.** Judging Sideeye on omamori alone conflates "Sideeye is weak" with "omamori is hardened." The dogfood period must include at least one deliberately average target: a stateful CLI with no hand-written adversarial tests. Zero findings on omamori is survivable; zero findings on an average target is evidence for a kill.

**Calibration result (2026-08-12).** Both branches accounted for. On omamori, zero findings on the `exec` audit path — and the reconnaissance found *why*: the high-water mark is confirmed after the body it confirms, so verify stays conservative in every crash window (the "too hardened" reason, the survivable side). The guarded self-modification commands (config-modify, `init --force`, key rotate — omamori issue #12) refuse to run whether an agent or a human invokes them, so making one a Sideeye `operation` would require break-glass — disabling the very defence under test — and is out of scope on discipline, not measured either way; the remaining surface was enumerated exhaustively later the same day (BUILDLOG: every subcommand including nested arms, the argv0 shim mode and the hook entrypoints, cross-checked from the write-primitive side) — and re-measured under contract v10 (2026-08-16, omamori 1.0.4, #141): **all four unguarded writers explore fully and hold.** The v8-era refusals of install/setup/init at `symlinkat`/`fchmodat` disappeared exactly as predicted when #122 made symlinks first-class and #121 made the chmod family recorded-only, and audit verify's high-water-mark bootstrap write still passes; `spike/dogfood-omamori-surface.sh` pins the current outcomes and fails loudly if any moves again. On the average target — timewarrior, no hand-written adversarial tests — a real crash-consistency bug (§17 above, four of six conditions clean, two with gaps). So: hardened on the path we can drive, and a genuine find on the deliberately-average target. That is the pattern §18 says distinguishes "the tool is weak" from "the target is strong", landing on the strong-target side — which clears the calibration kill condition, not the full v1.0 entry criterion.

"We built an interesting piece of technology" is not a reason to continue.

## 19. Product Quality Bar

Sideeye must be as careful about its own claims as it demands others be about theirs. Phrases like "verifies crash safety" or "explores all crash points" are used only when their meaning can be strictly guaranteed.

Priority order:

1. Findings are real.
2. Findings reproduce.
3. Findings are small.
4. What was verified can be stated.
5. It is easy to use.
6. It handles many failure types.

Quality of evidence beats breadth of coverage.

## 20. Relationship with Ponytail

*Ponytail writes it. Sideeye doesn't believe it.*

Ponytail is a sibling project by the same author; the pairing is a brand contrast, not a dependency. As "making" accelerates, "doubting" has to accelerate with it. Sideeye must stand alone.

## 21. Long-term Direction

Only after process crash × persistent state proves real value does Sideeye consider its next malice. Candidates, in no committed order:

- **Power failure and torn writes** — losing unsynced data, reordered writes; the natural deepening of the crash model.
- Concurrent processes.
- Network ambiguity.
- Clock anomalies.
- Partial remote execution.

The long-term vision is not a fault-type count. It is a habit: a developer writes *"this property must not break,"* and Sideeye does the imagining, the breaking, and the shrinking.

"It went through Sideeye" will never mean "it is safe." It means exactly one thing:

> This software was, at least once, seriously doubted under hostile conditions its author may not have imagined.

## 22. One-Sentence Definition

Sideeye is the deterministic skeptic in the coding loop: it finds the places where your software assumes a well-behaved world, breaks that assumption for real, and brings back the earliest failing crash point, saved as a replayable case.

## 23. The v0 Product Question

From development start until v0, every uncertain decision returns to one question:

> **Does this feature shorten the distance from a declared invariant to a crash bug — one the author, human or AI, would not have imagined — being found, fixed, and proven fixed, inside the loop?**

Yes → it is Sideeye's core. No → at least for v0, it is not built.
