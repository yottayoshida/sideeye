# 0113 — The threads refusal names a tool's own switch for one thread, in every mode

- **Status:** Accepted (2026-10-10)
- **Amends:** ADR 0097 — `threads_limit`'s "No flag", and the supervised threads refusal among its
  four exceptions.
- **Refs:** #686 (from the 2026-10-05 whole-product review); #687, whose measurement this leans on
  for the supervised half; `spike/dogfood/2026-10-09-followups-3/`, `-4/`,
  `spike/dogfood/2026-10-10-uv-threadpool/`, `spike/dogfood/2026-10-10-thread-order/`.
- **Scope:** `contract.NextStep` (`threads_limit`'s sentence, a new `threads_supervised`),
  `boundary.threadsStep`, `docs/apparatus.md`, `docs/report-schema.md`. Not `unknown_reason`, not
  `contract_version`: `next_step` is not a frozen surface (ADR 0090's correction of ADR 0089).

## Context

`multiple_threads_detected` stops more recorded targets than any other wall. ADR 0097 (2026-10-08)
gave it a step that names the README's threads limit and offered no flag, because "the targets the
records met here (node, Go, Python) have none that runs them on one thread". Under `--observe
supervised` it kept `class_wall`: that mode records no join, and the shim's sentence would send a
reader to look for one.

The premise did not survive the next day. 2026-10-09 follow-ups 3 tried each tool's own switch for
one thread, and 2026-10-10 took #686's missing half — the thirteen Node targets without the switch, on
the same released engine:

- **Node, `UV_THREADPOOL_SIZE=1`**: all thirteen refuse without it on v1.10.0; with it, ten get past
  (nine to a verdict, lingui to its next wall). Bitwarden CLI, vercel and gemini-cli have a second
  writer the pool's size does not remove. Declared as `env:UV_THREADPOOL_SIZE=1`, the run is accepted
  and the report names it.
- **Go, `GOMAXPROCS=1`**, under `--observe supervised`: doctl, infracost and plakar reach a verdict;
  OpenTofu does not (with one P the writing thread is still the scheduler's choice).
- **Rust** (`RAYON_NUM_THREADS=1 TOKIO_WORKER_THREADS=1`): none of four moved; each has a second
  writer neither variable removes (follow-ups 4's `strace -f` readings).

And for the supervised half, #687 measured the alternative — recording thread creations and exits from
outside — and found it admits almost nothing: 48 of 50 refused recording runs of the static targets
hold a hand-over neither event orders. A switch is the way past there.

## Decision

1. **`threads_limit` keeps its sentence and adds one**: a tool's own switch for running its file calls
   on one thread can move the run past this — `UV_THREADPOOL_SIZE=1` for Node, `GOMAXPROCS=1` for Go —
   set in the environment Sideeye runs in and declared in the define's `apparatus`, with
   `docs/apparatus.md` listing the switches measured and the targets each did not move.
2. **`--observe supervised` gets `threads_supervised`**, the same switch said without the shim: that
   mode records no join and not which thread a creation made — the words of the refusal's own detail
   line — and its refusal names no shim, in text or JSON (#217's acceptance leg).
3. **Both sentences open with "Two threads of one process wrote the judged directory"**: the dogfood
   entry gate sorts refusals by the step's opening words, and the supervised refusal now sorts with
   the other threads refusals instead of the class wall.
4. **`docs/apparatus.md` carries the table**: switch, how the define says it, what it moved, what it did
   not and why, the record — and that a verdict under the switch is about the tool run that way.

## Alternatives considered

- **Name only the switch that fits the target** (Node when the operation or its `#!` interpreter is
  `node`, Go when the image carries Go's build info). A wrong guess would name the wrong switch with
  confidence, and a target with no switch (Python's threads, Rust's blocking pool) would need its own
  sentence anyway. One fixed sentence naming both does not guess.
- **One sentence for every mode** (the plan's first draft). It cannot hold the shim's rule for the
  modes that load one and say nothing of a shim under supervised; the two acceptance legs that pin
  those (`#710`'s and `#217`'s) are why there are two members.
- **Leave the step and only document the switches.** The step is where a reader stopped by the wall
  is; a page nobody is sent to is the state ADR 0097 found `class_wall` in.

## Consequences

- ADR 0097's exceptions are three: `unresolvable_path`, `unsupported_syscall_observed`, and
  `oracle_missed_operation` under `--observe syscalls`.
- **Scope of "every mode": the refusal raised from the run's own record of its threads** — the trace's
  thread order (`threadsStep`, at the recording, a world and preflight's second run). The same reason
  raised under `--oracle-fs-usage` on macOS for a writer the shim never recorded
  (`unattributedWriterReason`, ADR 0060 decision 8) keeps `childTouchedNext`'s step: that writer went
  around the shim, which a pool's size does not change, and nothing measured it. Owner's ruling,
  2026-10-10, on the diff's first review.
- Over MCP the server passes its children `PATH` and the names `SIDEEYE_MCP_CHILD_ENV` lists; a switch
  not listed there leaves the declared run a SETUP ERROR, which `docs/apparatus.md` says.
- The switch changes the target's run: a verdict under it is about one thread. `docs/apparatus.md`
  says so where the switch is offered.
- Rust targets behind this wall (codex, rustic, prek, steamguard-cli, jj) have no measured way past;
  the sentence's "can" is the honest word for them.
