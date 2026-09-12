# ADR 0060 — The fs_usage oracle is told which threads are the subject's

Status: Accepted (2026-09-12)

Amends ADR 0055 (a thread of the subject is the subject) — the consequence that exempted
`--oracle-fs-usage` from the thread rule — and ADR 0031 §3, "The subject is the thread that
writes the shim's trace", which this makes "that thread, or one the trace names beside
it". (Earlier drafts of this ADR, the CHANGELOG entry and the BUILDLOG entry all cited
§2a; that section is the process boundary and carries no thread clause. Review caught it —
the miscitation is the failure mode this repository's own conventions warn about, since a
bare section reference is checked by nothing.) Neither
is withdrawn: ADR 0031's measurement of what `fs_usage` prints stands unchanged, and this
decision is about where the missing fact comes from rather than about that reader learning
something new.

## Context

Contract v16 (ADR 0055) made a thread judgeable. A run whose state-directory writes come
from one thread of each process is explored and judged, however many threads it created; a
second writing thread of one process refuses, naming both threads. The rule is decided from
the shim's trace alone, because **every record names the process that wrote it and the
thread that performed it**. It needs no oracle: a thread's writes reach the shim, which
shares its process.

`--oracle-fs-usage` was exempted from that. `src/main.zig` refused any run carrying a
`pthread_create` record under that flag, with `multiple_threads_detected` naming the
oracle's limit rather than the target's shape. The limit is real and ADR 0031 §2 records
it: `fs_usage` attributes a line to a **thread id** and prints no process for it, so
`src/fsusage.zig` sets no `primary_pid`. Without a map from thread to process, a subject
thread's write reached `childTouched()` as another party's, and the run would have refused
`child_touched_state_dir` instead — the right exit for the wrong reason, calling a thread
another process. Refusing by name kept the account true while nothing supplied the map.

The map was never missing from the system, only from that reader. The trace holds it: the
shim already counted **which thread ids wrote a kill point under the subject's pid**
(`TraceInfo.subject_writer_tids`, the number the report's account prints). The reader that
cannot see a process was never going to derive it from the capture; the side that names
both on every record can hand it over.

The concrete cost of the exemption: on macOS, the only oracle this platform has could
verify nothing about any threaded target. How large that class is, read off
`docs/target-classes.md` rather than recalled — **an earlier draft of this paragraph said
"sqlfluff, zstd, Bun and mlr all reach a verdict only because their writer count is read",
and three of the four were wrong**:

- **sqlfluff** is the one row that supports the claim as written: PASS 5/5,
  `oracle_verified`, in both observation modes, and recorded there as "the first target
  judged through the thread rule".
- **zstd** reaches PASS 9/9 only under `--observe syscalls`, a Linux-only mode, so it says
  nothing about what macOS would have done; under the default mode it stops on the stdio
  wall.
- **mlr** refuses `multiple_threads_detected` in five runs of six — the writer count
  refusing it, not admitting it — and its one judged run is also `--observe syscalls`.
- **Bun 1.4.2** passes the writer count and then meets `oracle_missed_operation`, so it
  reaches no verdict at all.

One row, not four. The exemption still cost macOS every threaded run, which is the reason
to lift it; what the evidence does not support is a count of recorded targets it turned
away. The paragraph was written from memory of a page that was open in the same session.

## Decision

1. **The trace supplies the map.** `TraceInfo` carries `subject_writer_tid_list`, the
   thread ids that wrote a kill-point record under the subject's pid — the same variable
   the existing count was taken from, published as a list rather than recomputed.
   `fsusage.read` takes it as its last parameter and fills `Parsed.subject_tids`.
2. **The list is the shim's recorded writers, and nothing wider.** Not every thread the
   process started, and not every thread `fs_usage` printed: only the ones the shim
   recorded performing a counted operation under the subject's pid. A reader handed a
   wider list would call lines the subject's that no record backs.
3. **Under a witness that names threads, a writer outside the list is refused as an id
   rather than as a process.** With the early refusal gone, such a writer falls to
   `childrenMayBeJudged`, whose refusal said "process N". That claim holds for a witness
   that reads pids and not for this one, so the wording is chosen on `Parsed.primary_pid`
   — set from a pid by the strace reader, never set by the fs_usage reader, and the same
   absence `childTouched()` already keys on. The run is refused either way; what changed is
   the sentence, and only on the path where the ambiguity is real.

   **The report's `processes` account carries the same correction**, because it is rendered
   by different code and would otherwise contradict the refusal inside one report. It
   softens when the evidence is a thread-naming oracle *and* the shim recorded no foreign
   pid of its own; with one, "a process" is established and the sentence stands.

   The first implementation asked the trace instead — whether it held any record from a
   process with that id. It reads as the same question and is not: it reworded the strace
   path too, where the id really is a pid, and the v15 fixture in `src/main.zig` failed on
   it. Recorded here because the wrong version was written first, and because the two
   questions are close enough to be swapped again.
4. **The early refusal is removed.** A threaded run under `--oracle-fs-usage` is decided by
   the v16 thread rule, from the trace, exactly as on Linux. A second writing thread of one
   process still refuses `multiple_threads_detected` — and now the reason names the target's
   shape rather than the oracle's limit.
5. **The scope is a single process.** Process boundaries under this oracle refuse as they
   did (`boundary_without_oracle`, ADR 0031 §2): `fs_usage` drops whole processes by name
   and `-e` does not lift that, so its silence is never an assertion of absence. This
   decision moves the thread wall only.
6. **Empty means untouched.** A single-threaded run passes an empty list, and every
   decision in that reader stands where it stood — the widened predicate is `subject` or a
   member of the list, and with no members it is the old predicate byte for byte.

7. **The subject's threads share one descriptor namespace in that reader.** Its fd table is
   keyed by `(tid, fd)` because `fs_usage` prints no path on a write and no pid on any
   line, so a write can only be placed through the open that preceded it on the same
   thread. Once the trace says which threads are one process, that key is too narrow: the
   shim keeps one trace descriptor per process, opened by the thread that initialises, and
   every thread that records an operation writes to it. Keyed by thread, a worker's write
   to that descriptor resolves against nothing and the run refuses as a hole — and since a
   worker reaches decision 1's list only by having written a record, that is the same line,
   so the list could never have been exercised. Within a process an fd number names one
   open file, so merging the namespace for the subject's threads is exact rather than
   approximate. A tid the list does not name keeps its own: nothing places it in the
   subject's process, and a system-wide capture holds other processes using the same small
   numbers.

8. **The reason an unattributable writer refuses under is chosen on evidence.** Decision 3
   fixes the sentence; this fixes the machine-readable `unknown_reason`, which has to pick
   one of the two. A process boundary the shim saw has already refused by the time this is
   asked (`boundary_without_oracle`), so if the shim ALSO recorded threads being created
   and recorded no boundary, "another thread of this process wrote" is the reading the run
   supports — a child with no boundary record needs a raw `fork`, while an unattributed
   thread needs only that the shim missed its writes, which is the class this oracle exists
   to catch. That case reports `multiple_threads_detected`. With no thread records the
   raw-fork shape is what is left and `child_touched_state_dir` stands (#405). This is also
   the reason the build before this ADR produced for the class, by refusing at the flag, so
   removing that refusal costs nothing here.

9. **The reader's other thread predicate is widened with it.** `relevant()` — which decides
   whether a hole in a line is a hole in the account of the judged directory — was keyed on
   the threads that named a path under the root. That is a different set from the list: a
   worker's `write` and `fsync` name no path, so a thread can be the subject and still sit
   outside every refusal `relevant()` gates. Since those refusals are what keeps a `chdir`
   from silently disarming §2b's guard, widening one predicate and not the other would
   disable a guard for exactly the threads this ADR newly admits.

   Widening turns silent drops into refusals at every gate but one, so it cannot make a
   PASS. **The exception is worth naming rather than rounding off**: a `chdir` INTO the
   judged directory is in scope and used to refuse as an unknown call; widened, it sets
   `cwd_moved` and continues, so that line refuses LESS. The behaviour is the right one — a
   `chdir` changes no state, and everything relative after it is unplaceable from that
   point, so the run still closes rather than opens — but "only ever refuses more" was
   false as stated, and the test written for this very decision names the counterexample in
   its own comment. It is safe only after decision 7, since before the namespaces merged it
   would have turned the trace-descriptor write into a refusal on every run.

   The cost is real and is paid by a shape nobody has measured: `cwd_moved` is one flag for
   the whole run, and the gate it sits behind also admits `__pthread_chdir` /
   `__pthread_fchdir`, which on macOS move only the calling thread's directory. A listed
   worker calling one of those now disarms relative operands for the main thread as well,
   so a run that could have been judged refuses instead. That is the safe direction and it
   is not free. Giving this reader per-thread working directories is a separate change.

## Alternatives Considered

- **Teach the fs_usage reader to map thread to process itself.** Rejected on the
  measurement ADR 0031 already carries: the capture prints no process on any line, in any
  class. Thread creation would have to be inferred from calls that are not in the `filesys`
  class this oracle runs with, and the inference would be a second witness's guess about
  the first — precisely the shape this repository refuses elsewhere.
- **Keep refusing under the flag.** Honest, and it was the decision until now. Rejected
  because the fact that made it necessary is available: refusing while holding the answer
  is a wall of our own construction, and it stood in front of every threaded target on the
  only platform where this oracle runs.
- **Hand the reader the whole `TraceInfo`.** Rejected: it needs one fact, and a module that
  takes the engine's trace type is harder to test with a synthetic capture — which is how
  every check in that file is written.
- **Derive the list inside the reader from the trace file it is already given the path
  of.** Rejected: that path is used to recognise and exclude the shim's own writes, not to
  parse; giving this module a second parser for the trace duplicates `engine/trace.zig`.

## Consequences

- A single-process run under `--oracle-fs-usage` whose state-directory writes come from one
  thread the shim recorded — the main thread or a worker — is explored and judged. That is
  the property this decision buys, and `spike/fsusage/acceptance-local.sh` pins it against a
  real `fs_usage`, with a second writing thread as the control that must still refuse.
- **A writer the shim never recorded is still refused**, and this decision widens the path
  it takes to get there. A thread reached through a raw `clone`, or one writing through raw
  syscalls, is not in the list; it used to meet the early refusal and now meets
  `childrenMayBeJudged`. Decision 3 is what keeps that refusal from asserting the writer is
  another process. The verdict is UNKNOWN in both arrangements — only the sentence differs
  — but the sentence is the part an operator acts on.
- The report's `processes` account is unchanged in shape: it prints the number of threads
  the shim saw created (a floor — a raw `clone` leaves no record) and the number of thread
  ids that wrote. What changes is that on macOS a run can now reach a verdict with that
  clause in it.
- **A subject thread that recorded nothing stays invisible to this reader's `chdir` guard,
  and that cannot be closed here.** The list holds threads that wrote a kill-point record;
  a pure helper — one that only reads, or only computes — is on neither the list nor
  `state_tids`, so its `chdir` does not arm `cwd_moved`. `fs_usage` prints no process on any
  line, so this reader cannot enumerate a process's threads, and arming the flag from any
  thread's `chdir` would arm it from the neighbours' too, in a system-wide capture. ADR
  0031 §2b is titled "A `chdir` by the subject leaves relative operands unplaceable"; this
  decision widens who "the subject" is, so that section's scope moves with it — **as far as
  the threads the trace names, and no further.** Reaching past it takes the subject itself
  writing a relative path through a raw syscall after a helper thread's `chdir`, and the
  snapshot layer still refuses that result as `state_changed_unaccounted`.

- The list is arena-backed and lives as long as the `TraceInfo` does, like `ops`. It is
  handed over whole rather than copied: the count beside it was already being kept from the
  same variable.
- `fsusage.read` grows a parameter, which landed on the twenty-three in-file test call
  sites the file held when the signature changed, and one caller in `src/main.zig`. The
  count in the file is higher now because this change also added tests, so it is written
  here as the size of that edit rather than as a property of the file — a number that
  describes a moment goes stale the moment after. Mechanical either way, and the compiler
  finds every one.
