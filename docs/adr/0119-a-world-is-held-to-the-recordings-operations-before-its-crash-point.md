# 0119 — A world is held to the recording's operations before its crash point

- **Status:** Accepted (2026-10-11)
- **Refs:** #815 (measured on 2026-10-11: two files written in a Python set's order under a random
  `PYTHONHASHSEED` were judged PASS in 2 of 6 explorations of one define, and in 7 of 30 here);
  ADR 0118 (the recording run starts from the rebuild every world starts from, which this needs);
  ADR 0053 (the class-only prefix comparison for runs with admitted children, which this replaces).
- **Scope:** `src/prefix.zig`, `src/main.zig` (`phaseExploration`), `src/contract.zig` (`not_repeating`'s sentence), `src/engine/snapshot.zig`
  (`relUnderRoot` made public), `spike/acceptance.sh` check 28, `spike/toys/toy_order.c`,
  DESIGN.md, `docs/report-schema.md`.

## Context

A crash point is a number in the recording run's count of state-changing operations, and the world
for crash point k is the operation run again and killed in front of its k-th operation. Nothing
held the world to the recording's first k-1 operations except, for a run with an admitted child, a
hash of their classes. A target whose order varies between runs therefore had its worlds killed in
front of other operations than the crash points name: with alpha written before beta in the
recording and beta first in a world, the world for "before the write of beta" died before the
write of alpha, and the state it left was judged as if it were the first. #815's shape was judged
PASS in 7 of 30 explorations, 6 of them with a compared world writing the other order and 4 having
recorded alpha first, the order the checker fails in. A class-only comparison
does not see it: the two opens and the two writes are the same classes in either order.

## Decision

1. **The first k-1 operations of every crash world are compared with the recording's**, in every
   exploration and every replay, before the world's state is judged: the same class at each
   number, and the same path at that number wherever the world names a path the recording spells —
   in its own operations, a rename's or a link's second path included, or in its initial or final
   snapshot — or the recording named there a path the state started with. A rename's or a link's
   two paths are compared each on its own. A world that differs is refused `kill_did_not_land` with
   the step `not_repeating`, its message naming the number and the world's and the recording's
   operation there, relative to the state. The step's sentence, which named only what the rebuild
   does not carry, now says that every run starts from the same rebuild, so what varied is the
   target's own order — a hash seed (`PYTHONHASHSEED` for a Python set), a random choice, a thread,
   the clock — or something outside the state, and to pin it in the define's environment as
   apparatus. No reason or step is added.
2. **Not compared**: the bytes written; an operation that is not a crash point; an `fsync`, which
   changes nothing a snapshot reads; a `mkdir` that is a no-op in both runs — on a directory present
   from the start, before anything in that run was removed or renamed (a removal can reach a name
   it does not spell, through a symlink, a case-folding filesystem or a directory above); and a name the
   recording never spelled, where the recording's own name there is not one the state started with,
   which is how a pid, a random suffix or a clock in a scratch name differs between runs without
   saying anything about order. The names the state started with come from the same rebuild in every
   run (ADR 0118), so holding a world to them refuses only an order that moved. The baseline world, which is not killed, is not compared.
3. **The comparison lives in `src/prefix.zig`**: the recording's operations indexed by number, the
   names it spells and the no-op `mkdir`s are computed once per run; each world's index and its own
   no-op `mkdir`s are built in an arena freed when the world's comparison ends, so the memory does
   not grow with worlds times operations.

## Alternatives considered

- **Compare every path.** Refuses every target that writes through a pid- or random-named scratch
  file, which is the safe way to write a file.
- **Treat only the snapshot's names as stable** (the first draft). Misses a fixed scratch name such
  as `alpha.tmp`, which the snapshots never hold, and refuses a random name the final snapshot
  keeps.
- **Run a world again until it draws the recording's order.** A recording that drew the harmless
  order would then always PASS.
- **Count crash points by the operation's identity instead of its number.** A change of
  architecture that reaches the saved case and replay; not taken here.
- **Compare `preflight --twice`'s two runs' operations.** The preflight document is a frozen
  surface with no field for an order-only difference; left to the owner.

## Consequences

- A target whose order varies reaches a verdict only when the recording and every crash world draw
  the same order, and the verdict is about that order. Measured on #815's shape (four crash
  worlds, three compared; `spike/dogfood/2026-10-11-order-815/`): 12 of 120 explorations reached one, 4 PASS where the recording wrote beta first and 8
  FAIL where it wrote alpha first, each with every compared world in the recording's order; the
  other 108 were refused at world 2 (59), 3 (36) or 4 (13). The window narrows; it does not close.
- A target that varies only in names it never spelled before — scratch names — keeps its verdict:
  check 28's random-named control, and the acceptance suite as a whole, are unchanged.
- The saved case's `prefix_hash` still compares classes only (frozen surface 4); a replay's worlds
  pass through this comparison like any other.
