# ADR 0055 — A thread of the subject is the subject, and one writing thread per process is judged

- **Status:** Accepted (2026-09-08)
- **Supersedes in part:** ADR 0002's refusal table, the row "`thread` in the subject —
  operation order stops being deterministic — the core claim": the row stands for two
  writing threads and is withdrawn for one. Narrows the ruling recorded against #202 in
  `docs/freeze-audit.md` ("the deepest of the three reach walls"): the wall is measured
  to be the shim's construction and the oracle reader's notion of the subject, not the
  determinism contract. An amendment on ADR 0002 points here.
- **Scope:** the trace contract (v15 → v16), the shim's per-call state, what the oracle's
  reader calls "the subject", the thread rule and where it is decided, and the oracle
  requirement.

## Context

Eight targets in `docs/target-classes.md` stand behind the thread wall. Measured on
2026-09-07 with strace and a tid-aware analyser (`BUILDLOG.md` of that date): five of
them — sqlfluff, vips, zstd, bundler, beets — create threads and write the judged
directory from **exactly one** of them, and in all five it is the main thread. The wall's
stated reason, "there is no per-thread order the kill can address deterministically", is
true of two threads writing and false of one: a single thread's writes are in program
order whatever runs beside them, and since ADR 0053 a crash point is an address in the
run rather than in a process, so one writer means one sequence.

The first plan for this admitted a threaded run on the oracle's word alone, without
touching the shim or the contract, because the five measured targets all write from the
main thread and a thread id in the trace "buys no target". A fresh reviewer read
`shim/src/common.zig` and found the three things that plan had not:

1. The module's first paragraph said its globals needed no synchronisation *because
   threads were refused*. `note1` sets `busy` before it resolves the path, so a worker
   thread opening `/dev/null` set the process-wide guard and the main thread's in-scope
   write, arriving inside that window, was dropped without a record. Measured with the
   refusal lifted: the v15 shim's trace held five of the seven records the rotate
   performs — no `fsync`, no `unlink`.
2. Under `--observe syscalls` the seccomp filter is inherited by every thread, and the
   `SIGSYS` handler runs on whichever thread trapped, reaching the same globals.
3. `writeRecord` wrote `getpid()`. Two threads of one process write the same pid, and an
   explored world runs with no oracle, so a thread that wrote in a world had no witness
   at all. The tid buys detection where there is no oracle, not admission width — the
   axis the first plan had measured on was the wrong one.

And a fourth, found by the first measurement rather than by review: strace splits a call
whenever another task's line lands inside it, printing `fsync(4</tmp/s/k> <unfinished ...>`
and, later, `<... fsync resumed>) = 0`. `src/oracle.zig` read neither half as an operation
— the first has no `)`, the second has no name — so a run with every shim record present
refused `oracle_missed_operation`. A parent blocked in `wait4` never made this common; a
second thread that keeps issuing calls makes it the ordinary shape.

## Decision

### 1. The shim keeps its per-call state per thread, in a slot keyed by thread id

`busy`, `record_buf`, `scan_buf`, `count_scanned` and `seq` — the five things one
interposed call needs — live in `ThreadState`, one per thread, claimed on first sight by
`gettid()` and a compare-and-swap. Not `threadlocal`, and decided without measuring it: a
shared object's `threadlocal` compiles to the general-dynamic TLS model, whose first
access from a thread takes `__tls_get_addr`'s slow path under the loader's lock, and
whether that first access happens inside the `SIGSYS` handler depends on the target and
the C library. A run that worked would be evidence about that glibc and that ordering. A
syscall and a CAS are async-signal-safe by construction.

Sixty-four slots, zero-initialised so they land in `.bss`, never freed — nothing in the
shim sees a thread end. The 65th thread takes a shared reserve slot and the run records
`thread-slots-exhausted` once, in front of that thread's first record, which the engine
refuses on. A target that creates and retires threads past sixty-four is refused rather
than judged.

`seq` is not protected by a lock and is not meant to be: `refreshCount` reads the run's
maximum back from the trace before every number, and two writers taking the same number
are refused by `sequence_numbering_broken` — the design its own comment describes for two
processes. A lock is not available here: the SIGSYS handler is a signal context, and the
module's rule against locks is a constraint, not a style.

### 2. Every record names its thread (contract v16)

`Record.tid: u64` — `gettid` on Linux, `pthread_threadid_np` on Darwin, 64 bits because a
Mach thread id is not bounded by a pid. Read live per record like `pid`. The byte shape
changes, so the version moves and a v15 shim under a v16 engine refuses
`contract_version_mismatch` rather than decoding eight bytes into the path. `tid` has no
default: every literal that builds a `Record` or an `Op` names one, so a shim that forgot
to write it would be a compile error.

### 3. The subject is the process and the threads it created

`Parsed.subject_tids` and `isSubject`: the subject's own `clone` lines carrying
`CLONE_THREAD` enter the new task's id — from the one line when the number is on it, and
from the `<... clone resumed>` half otherwise, paired to its unfinished half by the pid
column. `is_primary`, the touch predicate, the cwd tracker and `childrenMayBeJudged` all
ask `isSubject`. A thread's write is in the class list the shim's account is compared
against, its relative path resolves against the process's cwd (which its `chdir` moves),
and it is not a child's touch. A thread a child creates stays the child's. The
`CLONE_THREAD` boundary is gone; `CLONE_FS` without it still refuses (ADR 0006), and with
it does not, because a thread's fs context is the subject's own.

`syscallArg` returns the argument an unfinished call ran out on, which is the fix for the
fourth wall in the Context.

### 4. One writing thread per process is judged; a second refuses, and both are named

`engine.trace` keeps the first thread to write a kill-point record in each process. A
record from that process under another thread id sets `second_writer_thread`, and the
first writer's record beside it. The three sites that refused `.thread` as a hard boundary
— the recording, the world loop, preflight's second run — refuse on that instead, each
from its own trace: nothing is inherited, because the record carries the answer. The
refusal names the process, both threads, and what each did where, because which of the
two the trace saw first is the scheduler's choice on that run — the measured toy has its
worker write before the main thread, and a sentence naming only "the second" named the
main thread's own open.

The rule is asked of every process, not only the subject: a child whose two threads
write is as unordered as a subject whose two do.

### 5. A thread needs no oracle

`.thread` leaves `hard_boundary` and `process_boundary`; it stays in `boundary`, so the
quiescence sampling and the world arming, which key on `crossedBoundary`, still see it,
while the oracle requirements — `boundary_without_oracle` on the recording, the world-only
refusal, and preflight's run B — key on `needsOracle`, which is every boundary class but
a lone thread. A thread's writes reach the shim, which shares its process, the PLT and the
trace descriptor; there is no writer a second witness exists to catch (ADR 0002
decision 3's reason). A thread beside a fork, a spawn or a foreign record still needs one,
for those.

### 6. The account says what a judged threaded run was

`processes` gains a clause: how many threads the shim saw created (a floor — a raw
`clone` leaves no `pthread_create` record) and how many thread ids wrote the judged
directory. A run whose only boundary is a thread reads as one process with that clause,
not as "the subject replacing its own image" — which is what the account printed for the
judged toy before this decision gave the recording and world clauses a third shape.

## Alternatives Considered

- **Admit on the oracle's word alone, shim and contract untouched.** The withdrawn first
  plan. Fails on the three findings in the Context; kept under `.claude/plans/` marked
  withdrawn, with the review that withdrew it.
- **`threadlocal` for the shim's state.** Decided against without measuring, for the
  reason in decision 1: the measurement cannot answer the question it would be asked.
- **Keep refusing every thread.** The thread wall is the widest of the reach walls —
  Python C extensions, Node, Rust and Go runtimes — and five of the eight recorded
  targets behind it have one writing thread.
- **Admit every thread and let `preflight --twice` catch the non-deterministic ones.**
  Two writing threads race for a number in `refreshCount`, and the refusal that follows
  (`sequence_numbering_broken`) says the wrong thing about why. "Threads that take
  turns" — the analogue of ADR 0053's reaped child — needs a join the shim can see, and a
  raw `clone`'s join is not one. Left as a second stage, if a target asks for it.

## Consequences

- Contract v16. Saved cases from v15 replay as `case_no_longer_applies`, as every bump
  before this one. The `unknown_reason` set is unchanged (`docs/contract-freeze.md`,
  surface 2); the trace's byte layout is not among the five surfaces.
- Every interposed call pays a `gettid` syscall and a scan of up to sixty-four slots.
  The cost is measured in `spike/followup-item4/` before it is claimed in the CHANGELOG.
- The shim's `.bss` grows by about a megabyte (64 × 2 × `max_record_len`); the file does
  not, because the table is zero-initialised.
- The `#377` ceiling tests moved from 32 KiB to 48 KiB: the wider `Op` pushed one
  100-record trace across an arena chunk boundary (44,688 bytes against 22,580 under
  v15), and the relation they pin — one fits, two do not — needed the room.
- The acceptance suite's thread leg, which asserted `multiple_threads_detected` since
  v0.1, asserts a verdict now, and three shapes stand beside it. Check 2ae's fixture
  carries `CLONE_FS` without `CLONE_THREAD`.
- `docs/target-classes.md`'s Threads line, `DESIGN.md` §"what is explorable" and the
  README's target-class bullet state the rule. The rows for Bun, joplin, beets and the
  macOS `gh` are re-measured under v16 and rewritten from the measurement, not from this
  page.
- ADR 0002's row for threads is amended to point here. #202's ruling is narrowed, not
  overturned: the determinism contract is intact — one writer, one order — and what was
  deep was the construction.
