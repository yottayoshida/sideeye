# 0087 — A refused `setsid` means the child already leads a group of its own, so it is asked again

- **Status:** Accepted (2026-09-22)
- **Amends:** ADR 0075 — its Context's reading that the parent's `setpgid(pid, pid)` is refused by
  the same check, its Decision's "neither should reach this child", and its Consequences' "refused
  by both calls and still exits". Amendment notes on that page point here.
- **Scope:** the engine's fork stub (`src/posix.zig`, `childEnterOwnGroupWith`) on every spawn —
  worlds, the sudo probe, the `fs_usage` sidecar, the MCP adapter's child. No contract change,
  no new `unknown_reason`, no exit-code change.

## Context

ADR 0075 gave a child whose `setpgid(0, 0)` is refused a second call, `setsid`, and argued that
`setsid` could not be refused in that state. On 2026-09-21 it was (CI run 35588812014, the
`macos` job, `spike/thread-kill-lands.sh`): the child read `pid 5884, group 953, session 1`,
called `setsid`, was refused, exited 126, and the world was reported `kill_did_not_land` with
"Change the define" for a define that was fine. #651.

**What the job logs say.** Every macOS job of the `ci` workflow between 2026-09-19 and
2026-09-21 — 33 runs, 34 job logs, read through the Actions API; the earliest run was built
before #632 merged and logged no refusal, so 32 runs carried the fallback — logged six
refusals of `setpgid(0, 0)`, all six on builds that had it:

| Line in the log | Runs | Meaning |
|---|---|---|
| `but the child already leads its own group (pid N, session 1)` (#629's branch) | 5 | the child's call was refused, and its next `getpgid(0)` was already its own pid: **the parent's `setpgid(pid, pid)` had landed** |
| `so the child left group G with setsid` (#632's branch) | 0 | no child has ever survived through `setsid` on the runner |
| `could not be arranged … setpgid(0, 0) (pid 5884, group 953, session 1)` (exit 126) | 1 | #651 |

Two things follow, one about ADR 0075's reading and one about the refusal it did not foresee.

**The pointer reading explains less than it claimed.** ADR 0075 read XNU's `setpgid`
(`bsd/kern/kern_prot.c`) as refusing a self-call only at `SESS_LEADER(targp, …)`, a proc-pointer
compare against an `s_leader` nothing clears when a session leader exits, and concluded that a
`proc` reused at a dead leader's address is refused permanently — **and that the parent's
`setpgid(pid, pid)` is refused by the same check, since the check is on the target.** The
second half is what five of the six occurrences contradict: the parent's call landed. The
source, re-read on 2026-09-22 (`kern_prot.c`, `setpgid`, the `SESS_LEADER` check after the
`inferior()` branch), still puts the same check on the same target for both callers. So either
the first refusal is transient, or it comes from a path the source as published does not show.
Either way the mechanism is **unexplained again**, and this ADR does not replace the reading
with another; it records that the observable is a refusal of the child's own call that the
parent's call does not share.

**The `setsid` refusal needs no third mechanism.** `setsid_internal` (`kern_prot.c`) refuses a
process for exactly one thing:

```c
if (p->p_pgrpid == proc_getpid(p) || (pg = pgrp_find(proc_getpid(p)))) {
        return EPERM;
```

— its pid already names a process group. At the moment of the `fork` no such group exists:
the pid allocator (`bsd/kern/kern_fork.c`) skips any pid for which `pghash_exists_locked` or
`session_find_locked` answers, which is the POSIX rule ADR 0075 cited. But a group named by
that pid can come to exist a moment later, and the only path that creates one is `enterpgrp`
(`bsd/kern/kern_proc.c`), which **always places its subject inside the group it creates**. Any
caller allowed to reach it for this child — the child itself, or any ancestor in the same
session, since `inferior()` walks `p_pptr` — puts the child in that group. For a freshly forked
child the two conditions in the code above are therefore the same condition, and "`setsid` was
refused" is the same statement as "this child leads a group of its own".

That is what happened on 2026-09-21. The engine issues `setpgid(pid, pid)` in the parent right
after `fork` returns, as a rescue for the window before the child has been scheduled. The child
read its group (still the engine's, 953), asked for a session, and in between the parent's call
landed: `setsid` was refused because the child now led group 5884. The child was where it
needed to be and exited 126 on the refusal alone; the `group 953` in its note was read before
the move. ADR 0075's Consequences had said exactly this — "A child whose pid already names a
group is refused by both calls and still exits" — without noticing that the one way the pid
comes to name a group puts the child in it.

## Decision

After a refused `setsid`, the child asks `getpgid(0)` once more. If the group is its own, it
runs, and writes a note naming both errnos and the session it kept; if it is not, it exits 126
as before, with a note that names what both calls answered (`setpgid(0, 0) (pid, group,
session) failed, errno E, then setsid failed, errno F` — or, in the one shape the source does
not allow, that `setsid` answered 0 and the group did not follow) and the state read after the
second call.

This is ADR 0075's own rule applied one branch further — "what the `exec` depends on is the
group `getpgid` reports" — and it is the whole of the change. The `setsid` call and its order
are unchanged; a child the parent has not rescued by the time it asks still gets a session of
its own, with the costs ADR 0075 records.

Read from the source above, the 126 exit is now unreachable: a refused `setsid` implies a group
named by the child's pid, which implies the child inside it. The exit stays. The first refusal
is itself one the source does not explain, and an argument from that source is an argument,
not a measurement; the exit is where the next unexplained thing will say what it read.

## Alternatives Considered

**Wait for the parent's rescue before calling `setsid`** (the first draft: poll `getpgid` for up
to 100 ms, retrying the child's own `setpgid(0, 0)`, and only then `setsid`). Rejected in
review. It does not change what can be lost — the branch above already makes the exit
unreachable — and it only trades the #630 cost (a world with a session of its own) in a case
never observed: no runner child has yet gone through `setsid`. Its costs were real: the wait is
paid out of `--world-timeout`'s budget (`budget_t0` is read before the `fork`); the `fs_usage`
sidecar's spawn issues no parent-side `setpgid(pid, pid)`, so there the wait could never be
answered; the child's own retry is dead code under the one reading of the first refusal that
exists; and 100 ms was a number with no measurement behind it. A world that goes through
`setsid` on the runner would be the observation that reopens this.

**Report the 126 world as the environment's refusal** rather than `kill_did_not_land` with
"Change the define". Deferred, as ADR 0075 already deferred it ("Refuse louder … remains open
as part of #630"). With the branch above, a child that reaches 126 is one the source says
cannot exist; a test engine and an acceptance leg for that path would be built for a
population of zero observations. #630 keeps it.

**Have the parent signal the child** over a pipe once its `setpgid(pid, pid)` has landed, the
way the cgroup join does on Linux. Rejected: a descriptor on every spawn, on every platform,
for a race the child can close by asking one more question.

**Fork again.** Rejected by ADR 0075 for the exit-code freeze; nothing here changes that.

## Consequences

- A run that lost a world this way now reaches a verdict, and that world keeps its
  controlling terminal — unlike the #632 branch, `setsid` did not go through.
- Three surviving notes can now appear on the engine's stderr, all opening
  `sideeye: setpgid(0, 0) failed`, which `spike/thread-kill-lands.sh` counts by. The new one
  names both errnos.
- The 126 note names what both calls answered. The `errno 1` a search would look for is a
  substring of `errno 13`, so the test that reads it compares the whole line.
- ADR 0075's reading of the first refusal is no longer relied on by anything: the branch above
  does not care why `setpgid` was refused. What is still true of that reading is recorded on
  ADR 0075's page; what was contradicted is recorded there too.
- The `fs_usage` sidecar is unchanged and unequal: its spawn has no parent-side rescue, so a
  refused child there always goes through `setsid` and pays the controlling-terminal cost.
  Adding the parent's call would be one line that no test can attribute (the child moves
  itself in the same instant), and it is not made here.
- `setsid` can be made to refuse on a laptop after all — by a child that already leads a
  group of its own, which is how the new branch is tested against the real call rather than a
  fake's `-1`. ADR 0075's "no host available here can be made to refuse either" was true of
  `setpgid` only.
