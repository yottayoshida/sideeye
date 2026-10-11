# 0118 — The recording run starts from the rebuilt state every world starts from

- **Status:** Accepted (2026-10-11)
- **Refs:** #815 (measured on 2026-10-11: a target whose write order varies between runs was judged
  PASS in 2 of 6 explorations of one define, because the crash points are numbered by the recording
  and no world was held to its order); DESIGN.md §14 item 11; ADR 0109 (the rebuild keeps permission
  bits); ADR 0024 and ADR 0037 (the root the rebuild vets).
- **Scope:** `src/main.zig` (`phaseRecording`, and the refusal of `--state-under` without `--twice`
  removed from `phaseDefine`), `src/cli.zig`, `src/mcp.zig` (`sideeye_preflight`), `spike/acceptance.sh` checks 16, 27 and the rewrite
  legs of #363, `spike/toys/toy_listing.c`, DESIGN.md, `docs/cli.md`, `--help`.

## Context

An exploration snapshots the state the setup left, runs the operation once to record it, and then
starts every world from a rebuild of that snapshot: the state emptied, and its entries written back
in name order with their contents, link targets and permission bits. The recording alone ran on the
setup's own copy. Whatever the rebuild does not carry — the order the filesystem lists a directory
in, owners, hard links, set-id bits, timestamps — could differ between the recording and every
world, while the worlds' crash points stay numbered by the recording.

Measured on 2026-10-11 in a container, a directory whose entries were created c, b, a lists in
another order than the same entries created a, b, c on tmpfs, btrfs and XFS, and in the same order on
overlay over ext4. So on those three, a target that lists its state and writes in that order does one
thing in the recording and another in every world: the baseline world disagrees with the recording
(`baseline_violates_invariant`) or, when the bytes come out alike, the crash points name the
recording's operations while the worlds perform others. Holding a world to the recording's
operations, #815's other half, needs the two to start alike, or it would refuse those targets for a
difference the engine made.

## Decision

1. **Rebuild before the recording run.** `engine.restore(initial, state_abs)` runs once more,
   after every refusal of a mistake that needs no rebuild — the define's, the oracle's, the
   observation mode's, the depth `--oracle-fs-usage` can scope — and before the image reading, the
   macOS observer and the recording run, in explore, replay and preflight. Both of `--twice`'s runs now start from the
   rebuild. A failure there is a SETUP ERROR of the environment (`restoreFailure` before the run's
   phase becomes `exploring`), raised before the operation has run, with "could not restore the
   state directory before the recording run".
2. **A plain `preflight` rebuilds too, and so takes `--state-under`.** Preflight promises the
   detector explore's recording would use (`docs/cli.md`), and the recording now starts from the
   rebuild; a preflight that observed the setup's copy would accept what explore then refuses — a
   state it cannot rebuild, a root replaced by a link — or say `nothing_could_fail` of a target
   that changes the rebuilt state. Rebuilding is what made #717 confine `--twice` and refuse the
   flag elsewhere ("one observed run rebuilds nothing"), so the flag is now taken by every
   preflight and the MCP server passes `SIDEEYE_MCP_STATE_ROOT` on every `sideeye_preflight` call
   (owner, 2026-10-11).

No `unknown_reason`, `setup_error_reason` or NextStep is added.

## Alternatives considered

- **Compare only names new to the run** (#815's other fix). Leaves a fixed scratch name rewritten in
  hash order unseen. Not taken (owner, 2026-10-11).
- **Refuse a run whose listing order differs between the recording and a world.** It would turn
  verdicts that are sound today into UNKNOWN, and a user cannot change the order a filesystem keeps.
- **Hold worlds to the baseline instead of the recording.** The crash points would then be named by
  two runs, the recording and the baseline.
- **Leave a plain `preflight` on the setup's copy and say so.** It keeps one command that rewrites
  nothing, at the price of a preflight that can accept a define explore refuses, which is the
  question preflight exists to answer. Not taken (owner, 2026-10-11).

## Consequences

- A target that depends on the setup's own copy — a listing order, an owner, a hard link, a set-id
  bit, a timestamp — meets the rebuilt copy from its recording on, as its worlds always did. Measured
  before and after on 2026-10-11, with the same defines and the same container: the acceptance suite
  (as root and as a non-root user) and six real targets — `chdman addmeta` (FAIL 2/5, earliest 3),
  `hunspell -p` (PASS 3/3), `libdeflate-gzip` with its checker (PASS), the mode-bit probe of
  #678 (`nothing_could_fail`, 4 crash points), upx 5.2.1 (FAIL 1/35 at 34, supervised) and argocd
  3.5.3 (FAIL 1/3 at 2, supervised) — gave the same verdicts, counts and earliest crash points, and
  their `preflight --twice` the same answers.
- Two shapes now stop earlier, before the operation runs. A setup that replaced the state directory
  with a symlink was recorded writing through the link, outside the state, and then refused
  `state_changed_without_ops`; it is now a SETUP ERROR saying the state directory no longer resolves to
  the one the run resolved, and nothing is written. A state holding an entry the engine cannot remove (a directory without its
  write bit, as a non-root user) was recorded and then refused `state_rewrite_failed` at the first
  world; it is now a SETUP ERROR of the environment before the recording run.
- A plain `preflight` now rewrites the state directory as explore does, and is refused a state
  outside the range it is given: `--state-under` on the command line, `SIDEEYE_MCP_STATE_ROOT` over
  MCP, where a call without `twice` used to run on any state.
- `docs/contract-freeze.md` records the runs whose exit code moved (surface 3), how a case saved
  before reads on replay (surface 4) and the narrowing of `sideeye_preflight` (surface 5), dated
  2026-10-11.
- One restore more per run: a run costs one rebuild of the state more than before, the cost of one
  world's rebuild (DESIGN.md's cost bullet).
