# ADR 0008 — L1 judges the whole post snapshot, and an unobservable marker refuses

- **Status:** Accepted (2026-08-12)
- **Supersedes:** nothing. Implements DESIGN §4.1's post-success invariant and §12's
  L1 level; extends the report with an `l1` line and `not tested` with the one gap
  the judgement keeps
- **Scope:** stdout capture for every operation run, the `marker` key / `--marker`
  flag, `engine.judgeL1`, the `not_durable` violation, the `marker_never_observed`
  refusal

## Context

DESIGN §4.1: in worlds where the operation reported success before dying, the new
state must survive restart — the program is held to its own words. Two ways to build
this are wrong in instructive ways. Judging only the files both snapshots share (a
strengthened L0) misses exactly what a success claim covers: a file the operation
*created* that vanished, and a file it *deleted* that returned. And treating "the
marker never appeared" as a report footnote leaves a silent hole: a misspelled
marker, or a target that never prints to stdout, would make every L1 obligation
vacuous while the verdict still said PASS.

A conditional invariant also has a vacuity trap on the other side (PRD v0.3
acceptance): most crash worlds die before the marker, and that is *correct* — the
claim was never made there. The design has to keep "not applicable" and "not
observable" apart.

## Decision

1. **Every operation run captures stdout to the work directory** — recording run,
   every crash world, the baseline — all through the same redirection, so an
   `isatty` branch in the target cannot make the recorded operation sequence
   describe a different execution than the worlds replay. Addressing is unaffected
   by construction: stdout writes are not state-directory operations and consume no
   crash-point address.
2. **A marker world is one where the marker's bytes reached the capture before the
   kill.** In those worlds — and only those — `judgeL1` runs, against the whole post
   snapshot: shared standard-form files must hold the post content; history-form
   files must still extend their pre content *and be longer than it* (success
   claimed an append; equality to pre is the loss of it); post-only files must
   exist; pre-only files must be gone. Any of these failing is the `not_durable`
   violation. The one deliberate gap: a post-only file's *content* is not judged —
   it may legitimately differ between runs — and `not tested` says so.
3. **A marker that never appears in the recording run refuses**:
   `marker_never_observed`, UNKNOWN. The recording run completes normally, so even
   an unflushed stdio buffer reaches the capture through libc's exit-time flush — a
   marker absent there is a misconfiguration or an unobservable claim, not a crash
   effect. A crash world without the marker is *not* this: the conditional simply
   does not apply there, and L0 and the checker judged that world anyway.
4. **The report carries the L1 story**: an `l1` line (text) and field (JSON) naming
   how many crash worlds observed the marker, mirroring `checker`'s
   one-variable-read-by-both plumbing; the checker line likewise gains how many
   worlds it ran in (DESIGN §14-12's counts).

## Alternatives considered

- **L1 as a strengthened L0 over shared files only** — rejected: misses created
  files vanishing and deleted files returning, which are the claim's content.
- **Report-line-only treatment of an unobservable marker** — rejected: a vacuous L1
  behind a green PASS is this tool's worst shape.
- **Judging post-only file contents** — rejected: nondeterministic content
  (timestamps, ids) would make correct targets FAIL; existence is what the claim
  guarantees, and the gap is named in `not tested`.
- **A regex marker** — rejected: substring match is weaker but honest, and the
  contract stays inspectable byte-for-byte.

## Consequences

- The v0.3 Define contract's L1 level is real: `marker` joined the toml schema in
  this same change (ADR 0007's "keys exist only once they are enforced").
- Target stdout no longer leaks into the engine's console; it is evidence, in the
  work directory.
- A target whose success message is buffered and unflushed yields an honestly
  vacuous L1 (0 marker worlds, reported as such) rather than a false refusal — the
  planning draft assumed this case would be `marker_never_observed`, and the
  exit-time-flush measurement corrected it.
