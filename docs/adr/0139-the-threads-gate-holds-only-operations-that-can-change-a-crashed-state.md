# 0139 — The threads gate holds only operations that can change what a crash leaves

- **Status:** Accepted (2026-10-30)
- **Amends:** ADR 0067 decision 4 (the rule at a kill point): which kill points the order is asked of. ADR 0138 decision 3
  named this cause for vercel and codex.
- **Refs:** #979; `spike/dogfood/2026-10-22-walls-v1150/` (vercel, codex), `spike/dogfood/2026-10-09-followups-4/`.
- **Scope:** the trace reader's thread order (`src/engine/trace.zig`), the three refusal sites in `src/main.zig`, the
  world check (`src/prefix.zig`), `docs/report-schema.md`.

## Context

The threads gate asks every kill point of a second thread to be ordered after the first thread's last one by a recorded
creation or join (ADR 0067). vercel's second thread only issues a `mkdir` of the state root that fails `EEXIST`; codex's
refused pair is that same `mkdir` and a link inside `tmp`, which its define declares scratch. Neither can change what a
crash leaves, so their order cannot either.

A record is written before its call — that is what makes it a place to kill — so the trace does not say whether a call
failed. Whether a `mkdir` changes nothing is read instead from what the state held before the run.

## Decision

1. **Two kinds of kill point are not held to the order** (in every mode, at the recording, preflight's second run and
   each world):
   - one whose every path lies under a declared scratch path, in either spelling of the root, and passes through no
     name that may be another name for something else: a symbolic link the state started with, or a name a symlink, a
     hard link or a rename brings into the state anywhere in the trace, or a hard link's old name — the record does
     not say which a renamed name is. A call that opens, writes, syncs or truncates is also held when the name itself
     is one of these, since it reaches the file the name stands for; the call creating a link is one of these kinds
     when its own name is under scratch;
   - a `mkdir` of the state root or of a name the initial snapshot holds (of any kind, as `prefix.same()` reads it),
     passing through no link, when no removal or rename names that name or one above it — compared without regard to
     case, for a case-folding filesystem — or passes through a link: none earlier on its own thread, and none on any
     other thread anywhere in the trace, since records are written before their calls and between threads their order
     is not the order the calls ran. A removal of another name does not make the directory disappear.
   Such a kill point keeps its number and is neither a writer nor compared. Its thread is still counted among the thread
   ids that wrote: the fs_usage witness on macOS reads that list to tell the subject's writes from another party's.
2. **The world check holds both sides to the same kind.** At each compared position, a kill point whose paths all lie
   under scratch, or that is a `mkdir` of the root or of a name the state started with, matches only another of those
   kinds. Read from the operation alone — not from the removals and links that decision 1 also looks for later in the
   trace — because a world stops at its crash point and would otherwise read the same operation differently from its
   recording. Without this, a scratch write under a name the recording never spelled would be read as the same as a
   state write that traded places with it.

Why a run admitted this way is judged at the right address, kill point by kill point: the engine kills whichever thread
reaches number `k` (the shim at `s == kill_at` in any thread; the supervising engine numbers serially); an operation
after `k` that runs leaves a gap the world's numbering check refuses (`sequence_numbering_broken`); before `k`, the
world check refuses a trade between the two kinds (decision 2). A trade at `k` itself leaves the same state, because
the operation not held to the order changes nothing.

## Alternatives considered

- **Leave every failed call out of the gate** (#979's direction as written). It needs a record after each call, in all
  three observers, and a contract version.
- **Leave `fsync` out too** (it changes nothing a process kill leaves). Wider than #979; not decided here.

## Consequences

- Measured with 2026-10-09's defines (`spike/dogfood/2026-10-30-threads-gate/`): vercel 62.2.0 `telemetry
  disable` with `UV_THREADPOOL_SIZE=1` was refused `multiple_threads_detected` in 10 runs of 10 on main and reached
  PASS 20/20 in 10 of 10 with this change (an earlier, unrecorded set of ten had one run stop at the update notifier's
  child, `child_process_detected`);
  codex-scratch under `--observe supervised` went from refused in 3 of 3 to PASS 21/21 in 3 of 3.
- Two threads that take a number at once can now reach the numbering check, which refuses the run
  `sequence_numbering_broken` where the gate refused it before: the shim's threads each read the trace's maximum and
  take the next. Two workers making the state root at the same instant met it in the acceptance toy's first form;
  vercel's ten runs did not. The supervising engine numbers serially and cannot.
- A checker that reads scratch may see two scratch writes in either order; scratch is what the built-in invariants leave
  alone, and the define declared it.
