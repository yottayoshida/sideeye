# 0072 — A declared recovery is a second observation over a saved FAIL, reported beside the verdict

Status: Accepted (2026-09-17)

## Context

A FAIL says the state a crash left violates an invariant. It cannot say what happens next, and
for the maintainer deciding whether to act, that is often the question: ninja rebuilds an output
its log marks stale, while a tool that "recovers" by deleting the file it cannot parse turns a
torn write into lost data. On 2026-09-16 the ninja run had to answer this with a probe outside
Sideeye. #606 asks for it inside.

The owner set the frame on the issue before any design: recovery is strictly downstream of the
crash model and never part of PASS/FAIL; it does not enlarge the crash-point space; it is
preferably a second-stage observation over a crash world that is already materialized, such as
a saved FAIL; it does not multiply exploration; and its cost is measurable apart from
exploration's.

Four facts about the code decided most of the shape.

**The state directory after a world is not the crash state.** The world checker runs in it
before the exhibit is latched and may rewrite it (`spike/dogfood-timew.sh`'s checker runs
`timew undo`), and after the loop the directory holds the baseline's result.

**The next world's restore resets only the tree.** A process a world leaves behind, or a write
outside the state directory, survives into every later world and into the baseline.

**A snapshot holds names, kinds and contents.** `engine.restore` rebuilds exactly those; files
come back with restore-time timestamps and the engine's fixed modes.

**Replay refuses the define-surface flags (ADR 0009), and `--config` is exclusive with them
(ADR 0007)**, because a case and a config each carry the whole question.

## Decision

A define may declare a recovery: `[recovery] command` and `check` in `sideeye.toml`, or
`--recovery` with `--recovery-check`. Declaring one changes no verdict and no exit code; for
each saved FAIL world it adds what the tool's own recovery did when handed that world's crash
state — its names, kinds and contents, not its timestamps or permissions.

1. **When: after the exploration loop, once the verdict is decided, and only when there is a
   FAIL.** Nothing a recovery does can reach a world or the verdict, because none is left.
2. **Which worlds: the saved exhibits** — `earliest` and `checker_earliest`, once if they are one
   world. The latch keeps each one's `crashed` snapshot past its iteration instead of freeing
   it. The account says how many of the run's failing worlds that was; a saved world does not
   stand for the others.
3. **Which state: the crash state, rebuilt.** Before each leg, `engine.restore(crashed,
   state_abs)`. Timestamps and permissions are not restored to crash-time values (owner's
   ruling); the limit is written where the result is read — the account, the evidence bundle's
   caveats, `docs/cli.md`.
4. **What one leg starts is stopped before the next, where the engine can stop it.** Where the
   engine can make cgroups (Linux), the command and the checker each run in a cgroup of their
   own, as a world does (ADR 0065), and everything they started is stopped when they exit; the
   account says how many processes a command left, because a repair handed to one of them was
   cut short. One that outlives the kill is `unknown`, and so is the claim exhibit's leg after
   an earliest leg whose survivor could reach it. Elsewhere only the process group is stopped, so a daemon
   that left the group, or a write outside the state directory anywhere, reaches the next leg —
   a limit `docs/cli.md` names. Either way the state is then snapshotted twice, and a difference
   is `unknown` — an observation that nothing was still writing, not a proof, as elsewhere in the
   engine. `--world-timeout` bounds the command and the checker, and `--stop-when-orphaned` is
   checked before each leg, since no world boundary checks it after the loop.
5. **The recovery checker is trusted only after two controls, the world checker's two.** It
   must reject a probe built from `final` with distinct junk in every file, and it must accept
   what the recovery leaves on `final` itself — the completed, uncrashed state, the world
   loop's baseline carried over. Either control failing makes every leg `unknown` with the
   reason, and the run goes on.
6. **`fail` is spent on one observation.** The command ran and ended (any exit other than 125,
   126 or 127, or a signal), the state stopped changing, and the checker rejected it. A command
   or checker that could not start, ended in 125, 126 or 127 — the codes the engine's own child
   uses when it could not enter the cwd, be arranged, or exec — or overran the budget is
   `unknown`, as is anything under 4 or 5. A command or check of spaces, which splits into no
   words and would die before exec, is refused when the define is read. `pass` is the same observation with the checker accepting.
7. **`src/recovery.zig` never ends the process.** It calls none of `setupError`,
   `spawnFailure`, `unknown`, the `refuse.*` helpers, `snapshotOrRefuse`, or the containment
   functions that end it (`afterRun`, `refuseDetach`, `killCameBack`, `pastCrashPoint`) — it
   imports `containment` for `spawn` alone; a recovery failure that reached one would replace a FAIL with a refusal
   about the recovery. The acceptance suite greps the file for them and for `@panic` and
   `unreachable`, and a planted copy is seen red; the grep sees calls by name in this file, not
   paths through a callee, which were read by hand.
8. **The public surface is additive and present only when a recovery was declared.** The report
   gains the account string `recovery` and `earliest.recovery` / `checker_earliest.recovery` =
   `{result, seconds, command_exit}`, `result` from a closed set of three; a define without a
   recovery gets none of them (a FAIL's and a PASS's reports compared byte for byte against the
   base build on macOS), though two refusal messages now name the recovery whatever the define
   declares. The evidence bundle's `recovery.result` slot, held open by ADR 0071, gets a value; `evidence_version` stays 1. No `unknown_reason`
   member is added, since nothing a recovery does makes the run unknown. The case file, the trace
   contract and the MCP input schemas are unchanged.
9. **Two exceptions to earlier decisions.** Replay accepts `--recovery` and `--recovery-check` —
   the one exception to ADR 0009's refusal of define-surface flags, because the recovery is not
   part of the question a case re-asks — and the replay line prints them, single-quoted with
   `shellSingleQuote`. `--config` is exclusive with both flags, on ADR 0007's never-a-merge
   rule. Both keys and both flags take the string form only: a flag has no argv form, and the
   same recovery has to read the same on explore and replay.

## Alternatives considered

**Run the recovery inside the loop, at the branch that latches each exhibit.** The first draft.
Rejected in review: the checker has already run in that directory and may have rewritten it,
and a recovery's writes outside the state directory, or a process it leaves, survive into later
worlds and the baseline — a FAIL could come out UNKNOWN from a line that never touches the
verdict. Seen red: with the command run at the latch, a define whose recovery writes a file its
world checker refuses goes from FAIL exit 1 to UNKNOWN exit 2.

**Recovery on replay only.** Rejected by the owner. Replay writes no evidence bundle, so the slot
#607 left for this would stay empty, and the result would exist only for someone who replays.

**Restore crash-time timestamps and permissions.** Rejected by the owner. It widens what every
snapshot carries and what every restore does, for every world of every run, to serve the subset
of recoveries that decide by time or mode. The limit is stated instead, including that a `pass`
from such a tool (make, ninja) can be manufactured by it.

**Falsify with the engine's `corruptState`.** Rejected: it writes one string to every file, so two
files that were equal stay equal and a checker of the `cmp out in` shape — the shape a recovery
check most often takes — passes the probe. **Build the probe from the crash state** was rejected
too: a file the crash already removed makes an existence-only checker exit non-zero without
reading a byte.

**The corrupted-state control alone.** The first implementation, which passed every check on
macOS. The Linux container showed the gap: an acceptance leg whose environment did not reach
the recovery checker read `fail` — the checker rejecting everything, reported as the tool's
recovery failing. The world checker already has the accept-side control (its baseline world);
the recovery checker now has the same. A checker that requires evidence that a repair happened,
rather than judging the state, is refused by it as `unknown`; the checks in `spike/` were
rewritten to judge the state.

**Leave the legs uncontained, with the settle check as the only guard.** The plan's choice,
reversed in the diff review: two snapshots see only a writer still writing at that moment, so a
daemon the baseline control started (`pg_ctl start`) survives quietly, and the next leg's own
start fails against it — a recovery that works reported `fail`. The containment every world
already has on Linux is reused rather than a mechanism added, and on macOS, where no cgroup
exists, the reach is a documented limit rather than a guard. The cost is the other direction: a
recovery checker that queries a daemon the recovery left running meets a stopped daemon.

**Carry the recovery in the case file.** Rejected for ADR 0071's reason: the case's version ladder
is a promise about the question a replay re-asks, and a recovery is not part of that question.

**Report the recovery through the verdict or an `unknown_reason`.** Rejected by the owner's frame,
and by surface 2 of `docs/contract-freeze.md`: an `unknown_reason` addition is a break, and a
recovery that succeeds does not make the crash state correct.

## Consequences

- The state directory after a run with a recovery holds what the last recovery leg left, not the
  baseline's result. `docs/cli.md` and the `recovery` row of `docs/report-schema.md` say so.
- Up to two more crash snapshots are held past the loop (each under the existing 256 MiB cap).
- A recovery costs one probe check, one baseline leg and at most two exhibit legs, whatever the
  run's crash-point count, and the account gives the total time apart from exploration's.
- Only saved exhibits are recovered. A run with many failing worlds says how many were not.
- Under MCP, `[recovery]` is part of the vetted config boundary and runs without
  `--world-timeout`, and `sideeye_replay_case` has no recovery parameter — surface 5 would allow
  one as a new optional parameter; this change does not add it. `docs/mcp.md` says both.
- `src/main.zig` stays at its declaration ceiling: the phase lives in `src/recovery.zig`, and the
  wiring is inside existing functions.
