# 0138 — Threads that only a lock, a queue or a wake orders stay outside; two thread ids writing in turn under supervised are to be judged; the threads refusal stops naming a switch the run already set

- **Status:** Accepted (2026-10-29)
- **Amends:** ADR 0067 (revisited, its line kept — decision 1) and ADR 0113 (the threads refusal's step is chosen from
  the environment — decision 3).
- **Refs:** #980, #981, #987; #580 and #687, whose rulings decision 1 stays consistent with;
  `spike/dogfood/2026-10-22-walls-v1150/`, `spike/dogfood/2026-10-25-shipped-v1160/`,
  `spike/dogfood/2026-10-29-go-handoff/` (decision 2's measurement).
- **Scope:** `contract.NextStep` (the four threads members), `boundary.threadsStep`, `src/mcp.zig`'s sentences,
  `docs/apparatus.md`, `docs/report-schema.md`. Not `contract_version`, not `unknown_reason`: `next_step` is not a frozen
  surface (ADR 0090).

## Context

Three issues meet one refusal, `multiple_threads_detected`.

- **#980**: its step names `UV_THREADPOOL_SIZE=1` and `GOMAXPROCS=1` whatever the run had. Bitwarden CLI and vercel were run
  with the first already set and told to set it; prek, rustic and steamguard-cli were run with the Rust switches set and told
  only about Node's and Go's.
- **#981**: seven targets (Electrum, basic-memory, Bitwarden CLI, prek, rustic, steamguard-cli, lz4 `-T1 -BD`) have two
  threads write the judged state with nothing a creation or a join orders, their own one-thread switch set wherever one
  exists.
- **#987**: under `--observe supervised`, eight static Go tools are refused because their writes move from one thread id to
  another, and `GOMAXPROCS=1` does not stop it. For etcd's `etcdutl defrag`, `strace -f -y` shows one run of `pwrite64` to
  `db.tmp.*` move from one tid to another midway. For Dolt the two tids write different databases, so the eight are not
  shown to be one shape.

## Decision

### 1. A recorded lock, futex, pipe or channel hand-over is not an order (#981)

ADR 0067's line is kept: a process's threads are judged where a creation or a join orders their writes. A record of a
hand-over by a lock, a futex wake, a pipe or a channel is not counted as one. A creation and a join point the same way on
every run; such a hand-over says which thread went first on this run, and on the next the other may. An uncontended lock
makes no system call, so neither the shim nor the supervising engine would see it. Consistent with #687 (Jujutsu's
hand-over is a futex wake) and #580 (not planned). This decision is about the hand-over's record as evidence; it does not
rule on a rule built from other evidence, which decision 2 measures.

### 2. Two thread ids writing in turn under `--observe supervised` (#987)

**Build: a rule that judges two thread ids of one process writing in turn under this mode, as a change of
its own, whose first step answers the three questions below.** Until it ships, these runs stay refused, and
the step says why (decision 3).

Decided from `spike/dogfood/2026-10-29-go-handoff/`, by criteria registered before its runs. A target
*passes* when, in plain runs under `strace -f` with `GOMAXPROCS=1`, no hand-over between two thread ids
overlaps (the earlier write returned before the later one started) and the sequence of writes is the same in
ten runs of ten, compared as `src/prefix.zig` compares a world with its recording; bytes no other run wrote
at a write are counted apart. With five or more measured, two-thirds passing and the two controls as stated
mean *build*. Of the eight, seven were measured (etcd handed over once in forty runs under strace, and in no arm-1 run,
the arm the hand-over criterion reads),
and six passed: Dolt, Grafana, Gogs, gqlgen, JuiceFS and Navidrome's `backup restore`; vmrestore removes
files in a different order each run, threads or not. No target's hand-over overlapped in 1,189; the race
control's did in every run. The first measurement, read with a reader that compared an open's descriptor
number, gave four of seven; the owner chose to fix the reader, register the rules again and measure again
rather than read the same captures twice (`RESULTS.md`).

What the measurement does not settle, and the rule's change answers first:

1. **Under the engine, not strace.** strace's stops line threads up — under it a race control alternated
   the same way in ten runs of ten. The supervising engine also stops each notified call; how much order
   that imposes, and whether the six still hand over without overlap under it, is measured there.
2. **How the engine knows the earlier write returned.** It answers a call and is not told when it
   returns. In 1,072 of 1,189 hand-overs the earlier thread had entered another call before the later
   write started, mostly `futex` or `fcntl`, which the filter does not notify.
3. **Decision 1.** The measurement does not tell one goroutine moving between threads from two threads a
   condition variable hands writes between; the turn-taking control passed. A rule that judges both by
   showing every world the same as its recording, not by a recorded hand-over, has to say what that does
   to decision 1, which keeps that shape out when the record is the evidence.

### 3. The step is chosen from the environment the operation inherits (#980)

The four environment switches `docs/apparatus.md` lists — `UV_THREADPOOL_SIZE`, `GOMAXPROCS`, `RAYON_NUM_THREADS`,
`TOKIO_WORKER_THREADS` — count as set when the variable is exactly `1` in the environment Sideeye runs in, read as the
apparatus `env:` check reads it. When one is set the refusal says that switch is not the target's runtime's or did not
remove the second writer, and sends the reader to the list for the others; it asks for no switch. Not "did not remove the
second writer" alone: one bit says a switch is set, not whose, and `GOMAXPROCS=1` exported for another tool would make that
a claim about a Node target's pool the run never tried. Two members are added,
`threads_switch_set` and `threads_switch_set_supervised`, beside `threads_limit` and `threads_supervised`. All four say that
these two writes are ordered by no creation or join — the side of decision 1's line they are on — and none says the target
can never be judged: an environment does not say why the second writer is there (vercel and codex meet this refusal for
another cause, #979).

## Alternatives considered

- **Count futex wakes or pipe hand-overs as edges** (#981's other branch). Rejected in decision 1.
- **Name the switch by the target's runtime** (#980's direction). ADR 0113 rejected it: a wrong guess names the wrong switch
  with confidence. Whether a variable is set is read, not guessed.
- **Name in the step which switch was set.** `NextStep` renders fixed sentences; a sentence per combination, or a dynamic
  one through every mode's output path, for what the report's apparatus field already says when the switch is declared.
- **Say, once a switch is set, that the target is out of reach by design.** False for a target refused for another cause.

## Consequences

- A switch set inside the operation (`env GOMAXPROCS=1 tool`) is not seen; `docs/apparatus.md` says the switch is read from
  the environment Sideeye runs in.
- Over MCP the engine's environment is what `SIDEEYE_MCP_CHILD_ENV` passed, so a set switch is one that reached the target.
- Each new member has a server sentence in `src/mcp.zig`.
