# 0067 — A process's threads are judged in the order its creations and joins give their writes

- **Status:** Accepted (2026-09-16)
- **Amends:** ADR 0055 decision 4 ("one writing thread per process is judged; a second
  refuses") — the count is no longer the rule; the order is. Takes the "second stage" that
  ADR 0055's Alternatives left "if a target asks for it": one did (#539), and the measurement
  that answered it is in the Context. ADR 0053 decision 3's reaped child is the process-level
  analogue of this decision's joined thread.
- **Scope:** the trace contract (v17 → v18: three records), the shim's `pthread_create`,
  `pthread_join` and `pthread_detach` wrappers and two static tables, the trace reader's
  thread rule, the refusal's sentence and the account's thread clause. Not the oracle: a
  thread needs none (ADR 0055 decision 5), and nothing here changes what either witness is
  asked.

## Context

ADR 0055 admitted a process whose state-directory writes all came from one thread and
refused a second writing thread by count, with the reason that two threads' writes are
ordered by the scheduler. That reason is true of two threads nothing synchronises and false
of two threads a join or a creation orders: a worker that writes and is joined before the
main thread writes has one order, and so does a main thread that writes, creates a worker
that writes, joins it and writes again. #539 asked for the join to be seen.

Two targets behind the thread wall were measured before anything was designed, without
Sideeye, under an `LD_PRELOAD` library that logs `pthread_create` (with the new thread's own
id, through a trampoline), `pthread_join`, `pthread_detach` and every open of the state
directory, three runs each (`spike/dogfood/2026-09-16-threads-take-turns/`). CPython 3.13
joins with a real `pthread_join`; 3.12 detached every thread and waited on a lock, so
nothing below reaches a Python target older than that.

- **beets 2.1.0**, the issue's own target: the main thread opens `library.db`, creates three
  pipeline workers, two of them write the database and its journal in turn, the main thread
  joins all three afterwards and writes nothing more. The two writers are siblings — no join
  and no creation between them; their order comes from the pipeline's queue, which the shim
  cannot see. **No rule built on what the shim records admits beets**, and this decision
  does not try to. #580, closed, is where that question went.
- **virtualenv 20.31.2**: the main thread writes 23 records, creates a thread and joins it at
  once (it writes nothing), creates a second that installs pip (499 records, the main thread
  silent throughout), joins it, and writes the six activation files and `pyvenv.cfg` again. A creation and a join fix
  that order end to end. A rule that reads joins alone does not admit it — the worker's
  writes come after the main thread's first ones by the *creation*; one that reads creations
  and joins does. The owner chose the latter over "joins only" and over closing the issue.

Two facts about the platform shaped the design and were found by the plan's reviews, not by
its first draft. **glibc reuses a joined thread's `pthread_t` for the next `pthread_create`**
— virtualenv's silent thread and its pip thread carry the same value — so a join resolved
after it returns can name a thread that is alive. **The `.thread` record a creator writes is
dropped when the shim is re-entered** (`noteBoundary` returns on `busy`), so nothing that pairs
a child with its creator may depend on that record being present or on where it sits.

## Decision

### 1. Three records, and what each carries (contract v18)

- **`thread_started`** is the new thread's first record, written before its start routine
  runs. Its `aux` names the creating thread's id, **how many records that creator had written
  through its own slot when it called `pthread_create`**, and which of the creator's
  creations this is (1-based). The count is what lets the reader rebuild where the creator
  stood (decision 3); the ordinal is what a join names the thread by (decision 2).
- **`thread_join`** is written by the joiner after `pthread_join` returned 0. Its `aux` is the
  collected thread's (creator, ordinal) pair, or `?` when the shim could not name it.
- **`thread_detach`** is written after `pthread_detach` returned 0, with the same `aux`. A
  detach creates no order; it is recorded because it is the call that says the join will
  never come, and the refusal says so.

The creator's `.thread` record is unchanged. None of the three is a boundary, a kill point
or a marker (`OpClass.isThreadSync`); the spelling of `aux` is `contract.thread_aux`, one
place for both writers.

### 2. The shim: a trampoline and two static tables

`pthread_create` installs a trampoline as the start routine where an entry of a 64-entry
static table is free; the entry carries the target's routine and argument and what the
start record must say. The new thread copies the entry out, returns it, writes
`thread_started` **from a stack buffer without claiming a per-thread slot** — being started
costs the slot table nothing; what claims a slot is a thread's first interposed call, as
before, so a pool whose workers enter the shim is refused at the sixty-fifth as under v16
(DESIGN §9) and one whose workers never do is judged however many there are — and runs the
routine, whose return value is the trampoline's. A `pthread_exit` and a cancellation unwind
through the trampoline's frame; measured on the Linux acceptance's `TOY_THREAD_EXIT` and
`TOY_THREAD_CANCEL`, not asserted. A failed `pthread_create` returns the entry too. When no entry is
free the routine is installed as given: that thread writes no start record, the reader knows
no creator for it, and its writes are ordered with nobody's — the refusing side.

**The creator fills the join table**, right after `pthread_create` returns with the handle in
hand: `pthread_t` → (creator, ordinal). Filled by the new thread it was a race — a creator
that joins at once looked the value up before the child had run and recorded `?` on a run
that was in order. **The joiner reads and clears the entry before the real `pthread_join`**,
while the thread is still joinable and the value still its own; read after the join returns,
the value can already be the next thread's. An insert for a value already present overwrites,
because that value's previous holder is finished; a full table drops the insert and the later
join records `?`. Both tables are cleared in the fork child, with each slot's record and
creation counts.

### 3. The order: vector clocks, rebuilt from a count

The reader keeps, per process, one vector per thread over that process's threads. Every
record a thread writes advances its own component (`thread_started` excepted, which the shim
writes outside the slot whose count the creator reports, so the two sides count the same
records). A `thread_join` merges the collected thread's final vector into the joiner's. A
`thread_started` **assigns** the new thread its creator's vector **as the creator stood at the
reported count**: the reader keeps, per thread, the vector after each record that brought in
another thread's component — its own start, each join — together with the count *after* that
record, and the creator's vector at count `n` is the latest such snapshot at or below `n`
with the creator's own component set to `n`. After, not before: filed under the count before
the record, a join at count 3 would sit under 2, and a child created at 2 would inherit what
the join brought (review). The creator's records up to `n` were written before it called
`pthread_create`, so they precede the child's start in the trace and the snapshot is there
when the start is read; a count the creator has not reached, or a creator never seen, leaves
the child without a creator. A creator that reports a count but whose `.thread` record was
dropped costs nothing here — the record is not read for this.

Assignment, not merge, because Linux recycles thread ids: a start on an id the reader already
holds is a new thread, kept as a new entry so that a join naming the earlier one by its pair
merges the earlier one's final vector and nothing the later one wrote; the new entry's count
continues from the old one's, as the shim's slot — found by id — does. A new image announcing
itself (an exec continuation) starts the process's order over, as the shim's slot table does.

### 4. The rule at a kill point

Each process has a current writer: the first thread to write a kill point. A kill point by
another thread is **in order** when that thread's vector component for the writer has reached
the writer's own count at its last kill point — the writer's last write happened-before this
one, through some chain of the creations and joins the shim recorded — and the write passes to
it. Otherwise the two are ordered by nothing the shim saw, and the run refuses
`multiple_threads_detected`, naming the writer's last write and the record that is not ordered
after it, and saying that no recorded creation or join orders the one before the other — with
"was detached, so no join could order it" where that is why. Asked of every process's own
trace, so a world and preflight's second run decide it for themselves, as under v16.

### 5. The account

The thread clause says how many thread ids wrote, how many times the write passed between
threads in causal order, and how many joins and detaches were recorded, so a reader of "2
thread id(s) wrote" sees what made that a judged run. The count of threads created is the
larger of the creators' `.thread` records and the threads' own start records: a creator's
record is dropped when the shim is re-entered, the child's is not, and a run whose only
creation records are starts is not one whose threads the shim never saw — the "count is a
floor" clause (#543) is reserved for a run holding neither (review).

## Alternatives considered

- **Joins only** (the issue's words). Admits the toy and neither measured target: virtualenv
  needs the creation edge for its main thread's first writes. Adding the edge later would move
  the contract again.
- **A token passed at joins, no clocks.** Refuses "the main thread writes, creates a worker
  that writes" and every grandchild. The general answer is a hundred lines.
- **Infer the creator from record order** (no trampoline). A start following some thread's
  `.thread` record is not that thread's creation, and a wrong creator is an edge that is not
  there — a judged run whose writes are concurrent.
- **Pair child and creator through the `.thread` record** (a per-creator ordinal in its
  `aux`, a snapshot table keyed on it, and "the creator's current vector" when the start
  arrived first). The `.thread` record is dropped under `busy`; the fallback then read the
  creator later than the creation and inherited writes made after it (review). The count the
  child carries has no such dependence.
- **Resolve the join target from the slot table, after the join returns** (a `pthread_self`
  field per slot). The value is reused the moment the join returns, a thread that never
  entered the shim has no slot, and the new thread filling the table opened the race in
  decision 2 (review, twice).
- **`pthread_threadid_np` on Darwin** for the join target. Exact there, a second mechanism
  everywhere.

## Consequences

- Contract v18. Saved cases from v17 replay as `case_no_longer_applies`, as every bump
  before. The `unknown_reason` set is unchanged (`docs/contract-freeze.md`, surface 2).
- What the reader keeps per process joins the trace's arena: the #377 fixture's 100-record
  trace costs the budget 51,318 bytes under v18 against 44,688 under v16, and the shared-
  ceiling test's limit moved from 48 to 64 KiB by its own arithmetic (one fits, two do not).
- The refusal sentence changed shape; the two thread ids and both operations are still named.
- Fourteen toy shapes pin the rule in `spike/acceptance.sh` (v16's three and eleven for v18:
  seven judged — a joined worker, which v16 refused; both sides of a joined worker; one
  `pthread_t` for a silent and a writing thread; a grandchild up the chain; a `pthread_exit`; a
  cancellation; seventy threads that never enter the shim — and four refused — siblings, a
  write before the join, a detached writer, a join of the wrong thread).
- Windows left open, each on the refusing side: a `pthread_t` another thread received through
  shared memory and joined before its creator reached the table records `?`; a thread
  cancelled asynchronously before its first instruction leaks one pending-start entry; a
  thread whose creation raced sixty-four others for the table writes no start record; the
  slot-exhaustion notice is counted by the reader and not by the shim, so every edge from a
  thread that announced exhaustion is short by one; the creation ordinal of a thread on the
  shared reserve slot is not taken atomically, and two such threads can report one pair —
  unreachable in a judged run, which the exhaustion notice refuses first. None admits a run;
  each refuses one that might have been in order.
- beets stays refused, and its refusal now says the two writers are siblings with no creation
  or join between them. virtualenv is measured under v18 in the same record; what it does
  past the thread rule is that record's to say, not this decision's.
- `pthread_timedjoin_np`, `pthread_tryjoin_np` and a raw `clone`'s join are not seen and not
  claimed; nor is C11's `thrd_join`, which glibc implements through an internal alias that
  does not pass the PLT. C++'s `std::thread::join` reaches `pthread_join` through libstdc++'s
  weak reference and is seen. A `pthread_cancel`ed thread is collected by a join like any
  other. Each unseen join leaves two threads unordered and the run refused.
- A thread the shim never saw created (a raw `clone`, #543) has no creator to inherit an order
  from: its writes are unordered with every other thread's and a second writer refuses, as
  under v16. The fs_usage reader is handed the threads the shim saw start, for its
  descriptor namespace and nothing else: a started thread's first act is its own start
  record, a `write` on the trace descriptor that `fs_usage` prints without a path, and a
  thread the reader did not place in the subject's process resolved it against nothing and
  refused the run as a hole (`oracle_saw_nothing`) — the macOS acceptance's check 7, a
  `pthread_create`d worker writing through raw syscalls, measured it on the first push. Such a
  thread is still not the subject to that witness; its raw writes stay another party's and
  refuse `multiple_threads_detected` as they did. The account's "a thread the shim never recorded creating wrote" clause still
  rises only when the trace holds no `.thread` record at all; a run that holds one and also a
  raw-clone writer says two thread ids wrote and no hand-over, and the refusal names the pair.
  Saying "unrecorded" there too would need the reader to know which starts it lacks, which is
  the count it cannot have; not done. The fs_usage oracle is unchanged: it is handed the subject's writing thread ids as
  before, and there can now be two.
