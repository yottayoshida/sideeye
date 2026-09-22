# 0075. A child the kernel will not regroup leaves the engine's group with `setsid`

Status: Accepted (2026-09-19)

## Context

The engine puts each child in a process group of its own before `exec`, because the shim's
crash point kills `kill(0, SIGKILL)` — the caller's whole group. A child left in the engine's
group would take the exploration down with it, so a child that cannot leave exits 126 and the
run ends `kill_did_not_land` with no verdict (#625, five occurrences on hosted macOS runners
between 2026-09-16 and 2026-09-18).

#629 established what the refusal is not. `man 2 setpgid` allows a self-call exactly one
EPERM — the caller is a session leader — and a session leader already leads a group of its
own, so that case needs no move. The diagnostics it shipped named the state on the next
occurrence: `pid 5173, group 971, session 1`. Session 1 is not the child's pid: the kernel
refused a leadership the session id says the child does not have.

XNU explains it — `bsd/kern/kern_prot.c` and `bsd/sys/proc_internal.h`, read from
`apple-oss-distributions/xnu` on 2026-09-19. `setpgid`'s only EPERM branch reachable for
`(0, 0)` is `SESS_LEADER(targp, targp_pg->pg_session)`, and the macro compares
**proc pointers**:

```c
#define SESS_LEADER(p, sessp)   ((sessp)->s_leader == (p))
```

`s_leader` is annotated `(C)` — constant, set at session creation — and nothing clears it when
the leader exits. A `proc` allocated at a dead session leader's address compares equal. The
refusal is then permanent for that child, and the parent's `setpgid(pid, pid)` is refused by
the same check, which tests the target. Nothing outside the child can move it either.

**Amended 2026-09-22 (#651, ADR 0087).** The last two sentences are contradicted by the
runner. Of the six refusals the macOS job logged in the three days after this ADR shipped,
five ended with the child already leading a group of its own — the parent's `setpgid(pid,
pid)` had landed. The source still puts the `SESS_LEADER` check on the target for both
callers, so the pointer reading does not explain those five, and the mechanism of the refusal
is unexplained again. Nothing below depends on it, as the next paragraph says.

**The decision does not rest on that reading.** The refusal is measured; the reuse is
inferred, and not reproduced. Whatever the kernel's reason, the observable is a child the
`setpgid` family will not move, and the second call below is a different family.

## Decision

When `setpgid(0, 0)` is refused and the child is still in the engine's group, the child calls
`setsid()`. If that leaves it leading a group of its own, it runs; otherwise it exits 126 as
before, naming the pid, group and session it read.

`setsid` is refused on different grounds, and neither should reach this child.
`setsid_internal` refuses a process that is already a group leader — excluded, since the
child's group is the engine's — or one whose pid already names a process group anywhere,
which POSIX excludes for a child this young: `fork` may not return a pid that "match[es] any
active process group ID". That is the same rule ADR 0002 decision 1 leans on when it argues a
freshly allocated pid cannot name a live group, and the two now agree; an earlier draft of
this ADR said the opposite and contradicted it.

**Amended 2026-09-22 (#651, ADR 0087).** The second refusal does reach this child, and it is
the engine's own doing: `fork` excludes a group named by the child's pid at the moment of the
fork, and the parent's `setpgid(pid, pid)`, issued right after `fork` returns there, creates
one a moment later — with the child inside it, since `enterpgrp` always places its subject in
the group it creates. A `setsid` refused between the child's reading of its group and the
call is therefore a child that already leads a group of its own. It now asks `getpgid` once
more after that refusal and runs if the group is its own; the exit below remains for a kernel
that still reports the engine's group, and names both refusals. The Consequences' "refused by
both calls and still exits" was written without noticing this.

The 126 exit stays regardless. What the `exec` depends on is the group `getpgid` reports after
the call, not an argument about which refusals are possible — the refusal this ADR is about
was itself one the manual does not describe.

## Alternatives Considered

**Fork again.** A second child gets a different `proc`, so the stale pointer is very unlikely
to match twice. Rejected for this round: the parent would have to tell this refusal from the
other 126s (a `dup2` failure), which share one exit code, and the exit codes are a frozen
surface (`docs/contract-freeze.md`, surface 3) — the signal would have to be something other
than a new code, which is a larger change than the one this replaces.

**Leave it and re-run CI.** Rejected by the owner on 2026-09-19: two of the five occurrences
landed within two minutes of each other on different checks, so re-running is not a bounded
cost, and a lost run is a run with no verdict.

**Refuse louder** (a distinct reason instead of `kill_did_not_land`). Not an alternative to
this: it improves the report of a run that still dies. It remains open as part of #630.

## Consequences

- A run that would have been lost now reaches a verdict.
- That world runs with a **session of its own**, so a target arranging its own process group —
  a shell does — has its `setpgid(0, 0)` refused by the kernel where it normally succeeds. The
  report has no field that says which kind of world it was: #630 carries that, and this ADR is
  the reason its state is now deliberately reachable rather than only accidental.
- **A session of one's own has no controlling terminal**, and on macOS `sudo -n`'s ticket is
  cached per terminal — this repository's own note at the sudo probe says so. The probe and
  the `fs_usage` sidecar reach their group through the same helper, so a child that takes this
  fallback on either can be told to run `sudo -v` in the terminal where it just did. Reasoned
  from that note and from what `setsid` means, not measured: the kernel state cannot be
  produced on any host available here. **The user-facing sentence does not change**: the sudo
  probe reads any non-zero exit as a missing ticket (`src/main.zig`) and the sidecar refuses on
  its handshake, so 126 and a ticketless `sudo -n` already produce the same message. What
  differs is the note on stderr, which now says the child left the group.
- The 126 exit is not removed. A child whose pid already names a group is refused by both
  calls and still exits, naming the pid, group and session it read.
  **Amended 2026-09-22 (#651, ADR 0087): the second sentence is false.** A pid that already
  names a group names the group this child is in — `enterpgrp` places its subject inside the
  group it creates — so such a child runs, after asking `getpgid` once more; it happened on
  the runner, with the parent's `setpgid(pid, pid)` landing between the child's reading and
  its `setsid`. The exit remains for a kernel that still reports the engine's group, and its
  note names what both calls answered.
- **The world itself loses its controlling terminal too**, not only the two helper spawns: a
  target that opens `/dev/tty` or expects a terminal signal behaves differently in that world
  from every other world of the same run. Unmeasured for the same reason, and it is the class
  #630 is about — the report does not say which kind of world produced the verdict.
- The child writes one line to the engine's stderr saying which group it left, so the state is
  legible in a transcript (since #651 one of three surviving notes, all opening the same way).
  `spike/thread-kill-lands.sh` prints any such line on the job log, green or red, with a count
  either way.
- The fallback cannot be exercised by the kernel on any host available here, so it is tested
  with a fake refusal and the real `setsid`; the 126 exit below it needs both calls faked.
