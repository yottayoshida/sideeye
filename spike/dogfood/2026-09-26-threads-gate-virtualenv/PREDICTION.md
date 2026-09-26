# Prediction — the 2026-09-26 threads-gate run

Committed before the box was built or anything ran.

## The question and why the answer does not wait on this run

ADR 0085's 2026-09-22 amendment left the entry gate's threads question open: it counts the
thread ids that write inside the state root without reading their order, so it is stricter
than the engine, and "the next run that uses this gate either drops the question or says what
it still catches".

`entry.sh` asks threads on two paths, both `gate=0`:

- **preflight accepted.** preflight asks the engine's own thread rule of both of its recorded
  runs (`src/main.zig`, `trace.second_writer_thread` after run A's structural checks and again
  in run B's), contract 18 at the v1.6.0 tag. A threads red after that can only be the gate
  disagreeing with the engine — the proxy ADR 0085's rule 3 forbids.
- **preflight answered FOLLOW** (`--observe syscalls`). The engine's rule has not necessarily
  run: FOLLOW comes from an operation the shim did not number. But what follows FOLLOW is a
  preflight or an explore under syscalls, and there the engine asks the same rule.

On neither path does the question tell the run anything the engine will not decide itself.
**The question is dropped whatever this run shows.** The run records whether the disagreement
occurs on a real target, not whether to drop it.

## The target

virtualenv 20.31.2 as Debian packages it (`python3-virtualenv`), the target the 2026-09-16
threads-take-turns run judged PASS 1382/1382 under contract v18 on main `d5911cd`: the main
thread writes the environment's skeleton, a worker installs pip, the main thread joins it and
writes the activation scripts. The engine's account there: *2 thread id(s) of the subject's
own process wrote the judged directory; 2 hand-over(s) … 2 join(s)*. The LD_PRELOAD probe of
the same run named the roles: main tid 10 with 18 operations, the pip thread with 499.

## The prediction

- Contrasts, in this box, first: `legs/joinedthreads` gate=1 with threads rc=1;
  `defines/js-beautify` gate=0 with threads rc=0.
- virtualenv: preflight rc=0, accepted, about 1381 operations; threads rc=1 with **2** writer
  thread ids — the same count as the engine's account and the probe's two roles. **Row 1.**

## How the entry's answer is read — four rows, by `entry.sh`'s gate value

1. accepted (gate=0, N ≥ 2) and threads red → the disagreement, on a real target. Written into
   the ADR as that.
2. accepted (gate=0, N ≥ 2) and threads green → the gate counted one writer or none here. Why,
   from the strace lines.
3. FOLLOW (gate=0) → threads' answer is recorded and not read as a disagreement. 2026-09-16's
   main accepted this target under wrappers, so this is a difference from then; whether it is
   a wrong verdict is decided separately.
4. threads never asked (gate=1: wall, interior, byte-repeatability; gate=DEFINE; gate=2:
   environment, setup, unmapped) → DEFINE and gate=2 are fixed and re-run once. Anything else,
   or the same answer twice, is recorded as a difference from 2026-09-16, and the question is
   dropped without a real-target measurement.

A gate writer count that differs from the engine's is checked against the strace lines before
it is called a miscount: the gate counts every id under `strace -f`, children included; the
engine counts the subject's own process.
