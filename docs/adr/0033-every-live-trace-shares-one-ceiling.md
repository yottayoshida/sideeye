# 0033 — Every live trace shares one ceiling

Status: Accepted (2026-08-30)

Supersedes nothing. Sibling of ADR 0029, which did this for the snapshot.

## Context

`max_trace_bytes` bounds one trace read at 64 MiB. Nothing bounded the sum. The total was
held by an argument — there are two read sites, both in one function, so the engine holds
at most twice the cap — and that argument had already gone stale when #377 was filed:

- There are **three** read sites: the recording read and the world-loop read in `main`,
  and `preflight --twice`'s second observation in `observeAgain`.
- Six comments and documents still said two, including `main.zig`'s own note that "a
  third read site COULD read and never answer" — written while the third existed, and a
  few lines from the third site's own comment saying "**this is that third site**".
- The third site answers for the per-read cap but has no acceptance leg: the
  `-Dtest-trace-cap` engines lower the shared constant, so run A's read fires first and
  run B is never reached.

A bound a call site can move is not a bound. This is the same shape ADR 0029 removed from
the snapshot path one level down: there `max_state_file_bytes` bounded one read and the
sum was left to the reader.

## Decision

**The trace arenas allocate from one `TraceBudget`, which refuses before the allocation.**

- `max_trace_bytes_total = 512 MiB`. `max_trace_bytes` stays: without it one trace could
  take the whole ceiling.
- `TraceBudget` is an `Allocator` sitting between the trace arenas and the general
  allocator. Its `alloc`/`resize`/`remap` answer `null` when the request would put the
  total past the limit; `free` returns the charge. Every `TraceInfo.arena` is built on it,
  so `TraceInfo.deinit`'s existing `arena.deinit()` returns everything with no call site
  having to remember.
- **`readTrace` and `readTraceCapped` take the budget, not an allocator.** A fourth read
  site inherits the ceiling because it cannot express a read without one, and
  `unboundedBudget` is how a caller opts out in a way a reader can see. The first draft
  injected the budget in `main.zig`'s wrapper instead and left the engine's public API
  accepting any allocator — the documents said every `TraceInfo` was built on a budget
  while the type said otherwise, which review caught.
- Exhaustion refuses with a new `unknown_reason`, `trace_budget_exhausted`. UNKNOWN, not
  SETUP_ERROR: every trace read is at or past the recording run.

### The value, measured

What a trace costs is not its file size. `readWhole` reserves from the file's length (a
flat 1.50x, the arena's node growth factor) and the decode then duplicates every record's
`path` and `aux` and grows an `ArrayList(Op)` in the same arena.

| shape | file bytes | budget bytes | ratio |
|---|---|---|---|
| header only | 36 | 542 | 15.1x |
| 100 records, 16-byte paths | 3,436 | 22,580 | 6.6x |
| 10,000 records, 16-byte paths | 340,036 | 2,680,986 | 7.9x |
| 100 records, 3000-byte path and aux | 601,836 | 2,285,906 | 3.8x |
| 2,000 records, 3000-byte path and aux | 12,036,036 | 45,139,816 | 3.75x |
| 1,973,000 records, 16-byte paths | 67,082,036 | 521,200,426 | 7.77x |
| **3,532,000 records, 1-byte paths** | **67,108,036** | **1,523,533,632** | **22.7x** |

**Shorter records cost more**: the per-record overhead dominates, so the same file size
decoded from more records holds more — six times more between the last two rows, at the
same file size.

**512 MiB does not clear one read at the per-read cap, and that is the decision.**
Clearing the last row would need 1.5 GiB, and two of them 3 GiB — the resident set this
ceiling exists to prevent. An unreported OOM kill is worse than a refusal that names
itself, so where the two ceilings disagree, this one wins. **The value is sized against
the corpus, not the cap — and that half is an estimate.** The largest exploration recorded
here is 119 worlds (Borg, cohort 2), which at `contract.max_record_len` comes to 976,990
bytes. That is a calculated bound taken from `max_trace_bytes`'s own comment, and it
carries that comment's caveat: worlds are not records, and a trace also holds lifecycle,
boundary and marker records the figure does not count. At the worst ratio in the table it
suggests roughly 22 MB for one trace and 45 MB for two, which 512 MiB clears by a wide
margin. **No trace from that exploration was weighed.** The table is the measurement; the
corpus margin is a reading off it, and is written here as an estimate rather than a
result.

**The two ceilings therefore disagree about some traces.** `max_trace_bytes` admits a
file this one will not hold. ADR 0029 records the same shape one level down — a tree can
break both the per-file cap and the tree ceiling, and which one fires depends on `readdir`
order — so the arrangement is not new, but here it is a refusal an operator can meet with
a trace that passed the cap, and the refusal says which ceiling it was.

**This ADR's first draft claimed the opposite**, on the strength of the 16-byte row and an
argument that the shim cannot write shorter paths because every one carries the state
root. Review asked for the 1-byte shape; the shim can write a one-character unresolved
operand (`shim/src/common.zig`), and the measurement above is what came back. The claim
was six times off, in the direction that would have shipped a ceiling advertised as
clearing something it refuses.

## Alternatives considered

**Correct the six stale sentences and add the third site's leg.** Rejected: it restores
the argument rather than replacing it, so a fourth site starts the cycle again. #377's own
words are that the property should live somewhere other than an argument.

**Count the read sites and their answers from source, and fail CI when they disagree** —
the shape of `spike/check-shim-coverage.py`. Rejected: it makes the counting reliable
instead of unnecessary. The total would still be a number derived from how many callers
exist.

**Charge the budget after each read from `ArenaAllocator.queryCapacity()`.** Rejected on
review, and the reason is in ADR 0029's own text: "the run that refuses may hold more". A
ceiling checked after the allocation cannot promise the total is not exceeded — at the
moment it refuses, the memory is taken. It would also miss the decode's allocations
unless every `try` in the decode loop were wrapped.

**Reuse `trace_too_large` for exhaustion.** Rejected: it changes a frozen machine meaning
rather than adding to the closed set. `contract.zig` already gives the reason for keeping
`state_tree_too_large` apart from `state_file_too_large` — an operator reading "too large"
goes to look for one oversized file, and under a shared ceiling there may be none.

## Consequences

- **The `unknown_reason` closed set goes from 33 to 34**, the second break of the freeze
  declaration, by owner ruling on this change's own merits. `docs/contract-freeze.md`
  carries the amendment. The first break is not a precedent this leans on; that amendment
  says so.
- A run may now refuse for a reason no single input explains. The refusal says so in as
  many words: "each trace involved may be well under the per-read cap — what ran out is
  the sum".
- **The per-read cap's pairing rule survives.** `answerForOversizedTrace` is still
  something a caller must reach, and the third site still has no leg for it. This ADR
  moves the ceiling, not the cap.
- **A trace that passes `max_trace_bytes` can be refused by this ceiling**, and an
  operator can meet that: it takes a trace of many short records. The refusal names the
  ceiling and says the sum is what ran out, so the two are distinguishable in a report.
  If the corpus ever grows traces that size, the value is what changes, not the mechanism.
- The budget's refusal is indistinguishable from a real allocation failure at the type
  level — Zig's `Allocator` vtable answers `?[*]u8` and carries no error — so the caller
  reads a side-channel on the budget. It is cleared by every successful allocation, so it
  always names the failure that actually propagated rather than `readWhole`'s deliberately
  swallowed reservation.
- **A refusal during the raw read does not arrive as an error at all.**
  `readTraceCapped` collapses every `readWhole` failure except the per-read cap into an
  empty `TraceInfo` and returns it normally, and the engine reads an empty `TraceInfo` as
  `no_shim_marker`. The first implementation of this decision shipped exactly that — a
  budget refusal reported as "the shim never initialised", measured on a real
  `preflight --twice` under a lowered ceiling. `readTraceCapped` is therefore a thin
  wrapper over the read: it asks the budget after every attempt — collapse or error —
  and turns either into `TraceInfo.budget_exhausted`, which the caller answers for after
  it has classified. Answering at the read instead cost the recording site its L0
  account, measured as `atomicity: not classified`.
