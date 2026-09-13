# 0065 — A process that leaves the process group is contained in a cgroup, and judged where the run was held

- **Status:** Accepted (2026-09-13)
- **Amends:** ADR 0002 decision 1 (containment) and decision 5's row "leaving the process group";
  ADR 0053 decision 2 (the kill takes the process group). Amendment notes on both pages point here.
- **Scope:** trace contract v17 (#581, the mechanism) and the refusal it lifts (#559's second half)

## Context

ADR 0002 contains a run by process group. The engine makes the direct child a group leader before
it execs, a world's crash point signals that group (ADR 0053 decision 2), and the cleanup signals
it again once the direct child has exited. A process that calls `setsid`, or a `setpgid` that
moves it, leaves the group, and neither signal reaches it — so ADR 0002 refused the escape by
name: the shim records `.detached`, and the engine refuses `child_process_detected`.

That refusal turned away a class rather than a target. ansible-core forks a process that calls
`setsid`, and the one write its `lineinfile` module makes to the judged state was read by the
2026-09-11 run, from a plain `strace`, as a `python3` renaming a temporary over the file
(`spike/dogfood/2026-09-11-past-walls/`, `docs/target-classes.md`). On 2026-09-13 the owner ruled
to contain such a process rather than document the wall, provided ansible was measured reaching a
verdict before any of it was built.

The throwaway prototype that measured it (`BUILDLOG.md`, the 2026-09-13 entry on #559's mechanism
half) put each run in a cgroup and had the crash point write that cgroup's `cgroup.kill`. Under
both observation modes, as root in a `--privileged` container, ansible's `lineinfile` reached PASS
2/2. With the crash point's cgroup kill removed and only the cleanup's left, ansible printed that a
worker was found dead and the world refused `kill_did_not_land`: the kill at the crash point has to
reach the cgroup, not only the one after the run.

## Decision

### 1. Where the engine can make cgroups, each observed run gets one of its own

The engine asks once whether it can make a child cgroup under its own and move a process into it —
what a writable cgroup v2 delegated to its user grants, and what root has over a writable one (a
default container mounts the cgroup filesystem read-only, and root there cannot). Where it can, the
recording run, every explored world and the baseline, and `preflight --twice`'s second run each run
in a new cgroup `R`, with the run's processes in `R/work`; the setup, the checker and the MCP
server do not. The cleanup writes `R`'s `cgroup.kill` and waits for the cgroup to empty. A world's
crash point moves its own process up into `R`, writes `work`'s `cgroup.kill`, and then signals its
process group, so it stops what the group kill stopped and everything in the cgroup besides (ADR
0053's amendment). It signals the group only while the group's leader stands inside the run's
cgroup: a process that joined another group in the session, with `setpgid(0, pgid)`, would
otherwise take that group — the engine's own, or its caller's — down with it, and dies alone instead. The shim says where it stands in a `cgroup` record — right after its
announcement, at every process boundary it records, and at a crash point whose kill came back —
and contract v17 carries that record and the three variables that name the cgroup. Where the probe
fails — macOS, a default container, an engine given no delegation — a run is what it was under v16.

### 2. What containment refuses

Each watch is asked after the refusals of its run's phase: a cgroup that does not empty within five
seconds of its `cgroup.kill`; a process that reports itself outside the run's cgroup, or cannot read
where it stands; a writer still in the run's cgroup when the direct child exited; a process the
trace names that is alive after the cgroup was stopped; a world holding a record numbered at or past
its crash point, or whose crash point could not step aside and so killed with the cgroup alone; and,
under `--oracle`, a write-open of `cgroup.procs`, `cgroup.threads` or `cgroup.type`, an
`open_by_handle_at` of one, or a `clone3` with `CLONE_INTO_CGROUP`.

### 3. A detach is judged where the engine held the run

A run is **held** when its spawn joined the cgroup and every image that announced itself said it
stood inside the cgroup before it did anything else (`containment.holds`). In a world killed at its
crash point, an announcement with no answer and nothing after it from that process is not held
against the run: the shim writes the announcement and the answer back to back, and a kill landing
between them is the kill at work, not an escape. An image that went on without answering is never
forgiven. A world's `cgroup.kill` is not part of the question: an image that reaches the crash
point without it cannot kill, records that, and the world is refused (`killCameBack`).

In a held run a process that left the process group is a child like any other: ADR 0053 decision 3
decides whether its operations may be judged, the oracle requirement applies as it does to every
process boundary, and the `processes` account says of it what it says of any child.

A run that is not held refuses the detach as it always did, `child_process_detected`, and says why:

| the run | the detail says | next step |
|---|---|---|
| Linux, and the engine cannot make cgroups | the engine could not give the run a cgroup of its own; a writable cgroup v2 delegated to its user, or root over a writable one, would let it | `environment` |
| Linux, where the engine can make cgroups and this run did not get one | that | `retry_then_report` |
| Linux, with a cgroup that some image did not answer to before going on | that | `class_wall` |
| macOS | the platform gives the engine no cgroup | `class_wall` |

No `unknown_reason` and no `next_step` value is added: `environment` already says to fix what the
detail names. The question is asked where the refusal stood — the recording run's structural
detectors, the oracle comparison (for a child's `setsid` or `setpgid` the shim did not record), every
explored world by its own trace and cgroup, and `preflight --twice`'s second run by its own.

### 4. The detach is read apart from the hard boundaries, and the subject's own is not a second process

`TraceInfo.hard_boundary` keeps the first hard boundary a trace holds, and `.detached` was one of its
values. Lifting the detach inside it would have let a detach recorded first hide an image change
recorded after it, in exactly the runs this lets through. The trace keeps the first detach in a field
of its own, and every reader asks the two separately. The oracle's parse is split the same way: a
child's `setsid` or `setpgid` no longer sits beside a filesystem-sharing `clone` and an `unshare`,
which stay refusals whatever is held.

Under `--oracle`, strace leads the process group, so the subject's own `setsid` succeeds where it
would fail for the engine's direct child. The trace keeps that record apart (`subject_detached`) and
does not count it as a process boundary, so the account never reports it as a second process the
oracle failed to see; it names the subject leaving its process group only where no witness's
account was read, and a run whose witness saw one process reads "single process".

## What containment cannot see

A process that leaves both the cgroup and the process group where the shim does not ask — at no
boundary it records, in no image it is loaded into — and touches nothing in the judged state while
its world runs. The cleanup's kill does not reach it and the trace does not name it, so no watch can.
What it writes afterwards lands in whatever runs next: a later explored world, whose verdict can take
it in, or the state after the run. Under `--oracle` the recording run refuses a process that moves
itself between cgroups, so a target has to do this in explored worlds only. This is ADR 0002's
knowingly-open window — a child whose behaviour a world did not account for — narrowed to a process
that does all of that; before this change a shimmed detach in the recording run refused first.

## The environment decides whether the target is judged

The same define is judged on a Linux host whose engine can make cgroups, and refused on one that
cannot and on macOS. That is the rule a process boundary already follows on a platform without an
oracle: judge where the thing can be measured, refuse where it cannot, and say in the refusal what
would let it be measured — which is why the Linux refusal's step is the environment. CI runs the
acceptance suite both ways, and acceptance check 2cg asserts from the traces which of the two each
run was.

## Alternatives considered

- **Keep the refusal and document the wall.** Declined by the owner in favour of containment, on the
  condition that ansible was measured reaching a verdict first. It was (Context).
- **`PR_SET_CHILD_SUBREAPER` and a kill that walks the process tree.** The crash point runs inside
  the target and cannot walk the tree, and a walk from the engine signals pids it read at one moment
  and signals at another, which the engine's rule against signalling a pid it has not pinned
  (`src/posix.zig`) forbids.
- **Killing the process group of each `.detached` pid.** The record is written after the call
  returns, so there is a window in which the process is outside the group and unnamed, and a
  grandchild it starts has a pid the engine never pinned.
- **A cgroup namespace with `nsdelegate`, closing the exit instead of watching it.** It needs a user
  namespace or `CAP_SYS_ADMIN`, which narrows the hosts where a detach is judged further than
  delegation already does.

## Consequences

- Contract v17: a case saved under v16 replays as `case_no_longer_applies`, and a v16 shim refuses
  `contract_version_mismatch` (#581).
- A world the engine did not contain still signals the caller's process group at its crash point,
  whatever that group is. A process that joins a group outside the run is recorded as a detach and
  refused at the recording run, so only a target that does it in explored worlds alone reaches that
  kill; the guard in §1 is where a cgroup gives the crash point a way to tell the run's group apart.
- Whether a target that detaches is judged depends on where it runs, and the refusal's step says
  which change of environment would let it be.
- The watch on a record at or past a crash point is reached second for every write the shim numbers.
  The shim counts `kill_landed` toward the run's maximum, so a process the kill missed takes the
  number after the crash point and leaves a gap at it, and the world's numbering check refuses
  `sequence_numbering_broken` before any watch is asked. Measured on the acceptance leg built for
  that watch: with the watch removed the run is still refused, and with the numbering check removed
  as well it reaches PASS. The watch stays for a write that took the crash point's own number while
  the process holding that number was dying at it, and for a crash point that could not step aside.
- Acceptance holds ansible's shape, the three ways out of a cgroup, and each of the four places the
  detach refusal is asked with a toy of its own; which of them were seen red with a mutation, and
  which were not, is recorded in `BUILDLOG.md`. The answer condition of §3 is held by unit tests
  only: no toy makes an image that announces itself and does not answer.
- ansible-core's `lineinfile` reaches PASS 2/2 in both observation modes as root in a `--privileged`
  container, the only place it was measured, and is refused naming the environment in a default
  container (`spike/dogfood/2026-09-13-cgroup-559/`). A non-root engine in a delegated cgroup runs
  the acceptance suite in CI and was not pointed at ansible.
