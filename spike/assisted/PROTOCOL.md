# Assisted discovery — the experiment protocol (#118)

**Assisted, never blind.** The scout reads source, docs, tests, trackers,
anything — which is exactly what ADR 0012 forbids, so no run under this
protocol may ever be described with the word "blind". No seals, no reviewer
covenant; the normal review discipline applies. The blind campaigns
(`spike/blind-hunt*/`) stay what they are: the strict instrument. This
directory measures the product question instead: **how high is the wall
between a fresh repo and a first meaningful exploration, when an agent is
allowed to scout?**

## Targets (fixed before any measured contact)

Five, chosen for installability and for diverse state shapes, none
previously explored by this project, none overlapping a
previously-explored format class (todo.txt-cli was verified installable and
then EXCLUDED for exactly that reason: the scout already knows the todo.txt
format's crash shapes from campaign 1, which would deflate its time and
inflate its hypothesis quality):

| Target | Install | State shape |
|--------|---------|-------------|
| buku 4.7 | apt | bookmarks in a single sqlite db |
| pass | apt | gpg files + optional git |
| calcurse 4.7.1 | apt | its own text files under ~/.calcurse |
| stow 2.3.1 | apt | a symlink farm |
| devtodo 0.1.20 | apt | XML (.todo) |

Cost, accepted at selection (2026-08-14): all five become blind-ineligible
forever once the scout reads their internals. None of them is hledger (the
one remaining blind-eligible candidate), which this experiment must not
touch.

**A cost NOT accounted for at selection, added 2026-08-15 after it came
due.** Selection weighed installability and state-shape diversity. It did
not ask who bears the cost if a finding is reported. That asymmetry is
real: a target chosen for our convenience gets a data-loss report from
someone who does not use it, and the work lands on a maintainer who never
asked for the attention while the evidence value accrues here. devtodo was
the case that made it visible — a legacy project whose author describes it
as stable, whose weakness already has adjacent reports in Debian's tracker,
picked because apt had it. Its report was filed and then withdrawn.

The rule for any future cohort, applied AT SELECTION rather than at report
time:

- Report-eligible: the project is active (issues moving, more than one
  contributor), has real users, and a report would actually help someone.
- Not report-eligible: we do not use it AND it is small, effectively
  dormant, or its sole maintainer has said it is in maintenance mode.
  Adjacent known reports lower the value further.
- A target may still be EXPLORED when it is not report-eligible — the
  measurement is legitimate. What changes is that its finding stays in this
  repository and is never filed upstream, and the selection record says so
  before the exploration runs, not after.

## Honest-measurement rules

- **Pre-window contact is install + `--version` only.** Reading a target's
  source or docs outside its measured window would smuggle knowledge into
  the clock. The installability probe did exactly install + version and
  nothing else; its record lives at COHORT level (this file's target table
  and the apparatus commit), not per-RUNLOG — so the rule is auditable for
  the cohort, and per-target only on trust (R1 finding 15, stated rather
  than papered over).
- **The window opens at the scout's first repo/docs contact** for that
  target and every phase boundary is timestamped (`date -u`).
- **The window closes at first meaningful exploration**: the engine
  completes an explore over a define that passed checker falsification and
  preflight. Time-to-define, falsification/preflight iterations, and every
  UNKNOWN fix are recorded separately.
- **Scout budget ~15 minutes per target** (soft: actuals are the data;
  overruns are recorded, not hidden).
- One target at a time, start to finish, no interleaving — interleaving
  would let one target's reading time hide in another's window.

## The funnel, per target

1. **Scout** (agent; DeepWiki MCP and web docs permitted): read the repo,
   propose **at most 3** candidate sets (state / operation / invariant).
2. **Every proposal carries metadata, separate from any verdict**:
   *why this operation is interesting*, *what user-visible or documented
   property the checker represents*, *where that claim came from* (a doc
   sentence, a test, a code path). A proposal without metadata does not
   count toward the funnel — this is how a human later judges whether the
   loop produced a meaningful question, because checker falsification
   proves a checker can reject something, not that it represents a
   contract anyone cares about.
3. **Define**: pick one proposal, write the explicit `sideeye.toml` +
   checker (fail-closed; the file-first/query-last structure is good
   practice but not a blindness requirement here).
4. **Falsify + preflight**; fix UNKNOWNs and record each fix.
5. **Explore** (the pinned container, the same cross-built engine).
6. **Record**: timestamps per phase, verdicts, useful counterexample /
   UNKNOWN / null, where the loop stalled, and the proposal metadata —
   with an empty "human judgement" column for yotta to score afterwards.

## Success signal (from #118, verbatim in substance)

Setup time lands at roughly 1–10 minutes AND the funnel reliably reaches
meaningful explorations — meaningful judged by a human against the
recorded proposal metadata, after the run. A state dir found in five
minutes, an arbitrary write command, a "the JSON parses" checker and a
PASS does not clear the bar. Findings are welcome but not required: the
thing being measured is the wall and the quality of the questions, not the
luck. An assisted success is never scored against criterion 1; the only
path it opens is an explicit entry-criteria redesign in PRD (§18-class).

## Apparatus

- `Dockerfile` → image `sideeye-assisted` (bookworm + the five targets +
  strace + python3 + gnupg/git for pass).
- Engine: the repo's cross-built `zig-out/bin/sideeye` +
  `libsideeye_shim.so`, mounted at /work as in the campaigns.
- `SCOUT.md`: the agent-facing skill — the loop above as instructions any
  agent can follow. This file IS the first deliverable of #118; the
  experiment measures whether it works.
- `runs/<target>/`: per-target working artifacts (gitignored); the
  committed record is `RESULTS.md` (written as targets complete) plus each
  target's final `sideeye.toml` + checker + proposal metadata.
