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

- **Eligible (owner rule, 2026-08-16, quantified): ≥500 stars, more than
  one contributor, and some activity within the last month** (a merged PR,
  a release or version bump, or similar). All three, not any.
- **Selection requires the owner's sign-off before any measured contact.**
  The candidate list — with each target's stars, contributor count and
  latest activity — goes to the owner for approval; nothing is installed,
  read or measured before it. This is a hard gate, not a review-time check.
- Not eligible: anything below that bar — small, effectively dormant, a
  sole maintainer, or in declared maintenance mode. Adjacent known reports
  lower the value further.
- **Tightened 2026-08-16 (owner): a target that is not report-eligible is
  not a legitimate measurement target either.** Do not select it, do not
  explore it, and do not let any score lean on a run against one. The
  earlier form of this rule ("a target may still be EXPLORED when it is not
  report-eligible; the finding stays in-repo") stood from 2026-08-15 to
  2026-08-16; hnb — measured under that allowance in `spike/followup-95/`
  as the contract check for #95 — is what showed the allowance's cost: even
  an unreported finding puts a dormant project's name in this repository's
  public records. The owner closed the allowance and struck the half point
  a score had briefly taken from that run (`RESULTS.md`, Correction).

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

## Claiming criterion 1 (the mini-seal rule, 2026-08-15, #130)

Exploration stays free: UNKNOWN retries, define iteration, re-recording — none
of it is gated. What is gated is the CLAIM. An assisted finding may be scored
against criterion 1 only when the pushed history shows the question preceding
the answer:

1. **Push the define first.** The complete define (toml + checker + setup, and
   the launcher when one exists) reaches main before the exploration whose
   artifacts will be claimed.
2. **Then explore, then push the artifacts.** The first report/case/transcript
   artifact for that target reaches main in a later push.
3. **The claim runs `verify-assisted.sh <target>` and commits its transcript.**
   The check anchors on the FIRST-PARENT order of main — squash merges and merge
   commits read the same way, and locally splitting commits cannot reorder a
   pushed history. Commits that travel in ONE push are still ordered by that
   line, not by push events: the ordering the rule buys is between pushes,
   which is why steps 1 and 2 are separate pushes. The file sets are the
   anchor tree UNITED with every path the first-parent history ever introduced
   under the target — never the working tree, and never the tree alone: an
   answer that existed and was then deleted by a commit is still an answer
   that existed. An artifact anchors at its OLDEST in-target existence event
   with rename hops followed in both directions (delete-and-re-add,
   move-out-and-back and committed deletion cannot launder its age, and git's
   cross-repo similarity noise — a fresh report once linked C071 to an
   unrelated JSON — stops counting on its own). Its legs: D1 the define's
   introduction strictly precedes the first artifact's and is a different
   commit; D2 the define blobs are byte-identical at both points (not
   evaluated when D1 already failed — a same-commit comparison is vacuously
   true); D3 every scanned file is listed with its introducing commit, and a
   file whose introduction cannot be resolved stops the run (exit 2) rather
   than narrowing the anchor set.

Like verify-seals, this audits the history as pushed — it cannot prove what
happened on a private disk first. The first cohort predates this rule: its five
targets run red (define and first artifact in one merge), recorded in
`verify-assisted-run-2026-08-15.txt` as a record, not a certification, exactly
as ADR 0017 said while the check did not yet exist. Every leg AND every walker
mechanism of the checker has been seen red once: thirteen drills
(`verify-assisted-drills.sh`), one per mechanism, after the first review round
showed the original five drills killed none of the rename/copy machinery and
the second caught a committed deletion shrinking the tree-only denominator.

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
