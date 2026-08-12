# Sideeye — Design Document

**Status:** design finalized, pre-implementation
**Name:** Sideeye (confirmed 2026-08-10)
**Tagline:** *Sideeye doesn't believe it.*
**Initial focus:** process crash × persistent state consistency

---

## 1. Overview

Sideeye deliberately removes software from the well-behaved world it was written for, and searches for the smallest counterexample that breaks a property its developer declared must hold. It is a mean-spirited reviewer.

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
3. **Minimal counterexamples as the deliverable.** Evidence a developer (or an agent) can paste into an issue, a regression test, and a fix verification, unchanged.

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
- A target that **creates other processes** is explorable when an oracle can account for all of them — the rule is that no process other than the subject touched the state directory, and it requires `--oracle`, which exists on Linux only (ADR 0002). A target that `exec`s over itself, creates threads, or leaves the containment group is refused; so is any process boundary on a platform without an oracle.
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

The most important UI is the counterexample report. It ships in two forms with identical content: **JSON for the caller, text for the reader.**

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
PASS  rotate-key: 5/5 crash worlds satisfied the invariant
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

**Primary criterion.** Starting from a state where all of omamori's existing tests pass, Sideeye finds a crash-consistency bug that the author's own hand-written adversarial tests do not catch. For that bug, all of the following must hold:

- Sideeye discovered it automatically.
- The counterexample is reproducible.
- The counterexample is small.
- The author judges it a real bug or genuinely incorrect failure semantics.
- After the fix, the same counterexample stops reproducing.
- The counterexample is kept as a regression test.

**Second criterion — the loop closes.** Give a coding agent nothing but the counterexample report (JSON + replay command) and the repository. If the agent can produce a fix that makes the replay pass, without a human translating the finding, the report format has met its real audience. A report that needs human interpretation fails the positioning of §3, however correct it is.

If the primary criterion holds, Sideeye has partially mechanized a human's way of doubting — not merely re-run existing tests.

**Status (2026-08-12).** The primary criterion is *not* met on omamori and is *substantially but not fully* met on the calibration target §18 requires. This is the survivable pattern §18 describes ("zero findings on omamori is survivable"), not a claim that omamori's criterion was transferred. On timewarrior — a stateful CLI with no hand-written adversarial tests — Sideeye found that a crash between the three commit renames leaves `timew undo` deleting an interval committed before the crash. Scored against the six conditions honestly, four hold cleanly and two carry real gaps:

- **reproducible / small / judged a real bug / stops after the fix** — clean. From the `reproduce` line and by hand with `cp`; one operation, a two-file window at crash point 14; judged real by this project's author (not yet confirmed by timewarrior's maintainers) and filed upstream as GothenburgBitFactory/timewarrior#778; a three-part patch reaches PASS 25/25 (measured).
- **"discovered automatically" — partial.** Manual trace triage seeded the target and the window: a human read the plain strace, confirmed by hand (with `cp` file surgery) that `undo` destroys committed data, and *then* wrote the checker. What Sideeye automated was the crash-world search — finding and minimizing the two violating worlds of nineteen from the human-declared invariant (§4.1, "ask for invariants, invent the failures"). The mechanized half is the search, not the hypothesis.
- **"kept as a regression" — a recipe, not a replayed case.** The recipe (`spike/dogfood-timew.sh`) and the fix (`spike/timew-undo-ordering.patch`) live in the repo and reproduce the finding, but it needs a built timewarrior, so it is not a CI-resident `sideeye replay` case. v1.0's entry criterion 1 ("kept as a replayed regression case") is therefore not yet satisfied by this.

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

**Calibration.** Judging Sideeye on omamori alone conflates "Sideeye is weak" with "omamori is hardened." The dogfood period must include at least one deliberately average target: a stateful CLI with no hand-written adversarial tests. Zero findings on omamori is survivable; zero findings on an average target is evidence for a kill.

**Calibration result (2026-08-12).** Both branches accounted for. On omamori, zero findings on the `exec` audit path — and the reconnaissance found *why*: the high-water mark is confirmed after the body it confirms, so verify stays conservative in every crash window (the "too hardened" reason, the survivable side). The guarded self-modification commands (config-modify, `init --force`, key rotate — omamori issue #12) refuse to run whether an agent or a human invokes them, so making one a Sideeye `operation` would require break-glass — disabling the very defence under test — and is out of scope on discipline, not measured either way; other state-changing surfaces beyond `exec` were not enumerated exhaustively. On the average target — timewarrior, no hand-written adversarial tests — a real crash-consistency bug (§17 above, four of six conditions clean, two with gaps). So: hardened on the path we can drive, and a genuine find on the deliberately-average target. That is the pattern §18 says distinguishes "the tool is weak" from "the target is strong", landing on the strong-target side — which clears the calibration kill condition, not the full v1.0 entry criterion.

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

Sideeye is the deterministic skeptic in the coding loop: it finds the places where your software assumes a well-behaved world, breaks that assumption for real, and brings back the smallest reproducible counterexample.

## 23. The v0 Product Question

From development start until v0, every uncertain decision returns to one question:

> **Does this feature shorten the distance from a declared invariant to a crash bug — one the author, human or AI, would not have imagined — being found, fixed, and proven fixed, inside the loop?**

Yes → it is Sideeye's core. No → at least for v0, it is not built.
