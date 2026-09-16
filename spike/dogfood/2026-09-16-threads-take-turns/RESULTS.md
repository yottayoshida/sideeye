# Threads that take turns: what a join rule can reach, and what v18 did reach (#539, ADR 0067) — 2026-09-16

Two measurements of the same two targets. The first, before anything was designed, asked
what the thread API of each target looks like from inside the process — with an `LD_PRELOAD`
probe and no Sideeye — because ADR 0055 had left "threads that take turns" as a second stage
keyed on a join the shim can see, and #539 named beets without saying whether beets joins. The
second, after the design, put the branch build of Sideeye (contract v18) on the same two
defines in both observation modes. **Not a release build**: the transcripts print the branch's
version, the way `2026-09-11-syscall-trap-542b/` did for #542.

## Provenance

| | |
|---|---|
| targets | beets 2.1.0 (`beet import -q`, the `spike/followup-item4/` define), virtualenv 20.31.2 (`virtualenv -q --no-download`, the `2026-09-16-userview-3/` define) |
| platform | Debian trixie in Docker, aarch64, Python 3.13.5, glibc 2.41, strace 6.13 |
| probe | `apparatus/joinlog.c` (`LD_PRELOAD`; logs `pthread_create` with the new thread's id through a trampoline, `pthread_join`, `pthread_detach`, and the state directory's opens, writes, fsyncs, closes, unlinks, mkdirs, renames and symlinks, with the calling thread's id), cross-built on the host with `zig cc -target aarch64-linux-gnu`; drivers `apparatus/run.sh` (beets) and `apparatus/run-venv.sh` (virtualenv); boxes `apparatus/Dockerfile.probe`, `Dockerfile.probe-venv` |
| engine, for the v18 run | the branch build (`zig build -Dtarget=aarch64-linux-gnu` on the host, mounted at `/se`); box `apparatus/Dockerfile.measure`; driver `apparatus/run-v18.sh`; version in `transcripts/v18/version.txt` |
| predictions | `BUILDLOG.md`, the "predictions, written before the v18 run" paragraph of the #539 entry, timestamped |

## 1. The probe: what the thread API looks like, three runs each

Raw output: `transcripts/probe/import.{1,2,3}.jl` (beets), `venv.{1,2,3}.jl` (virtualenv),
`control.jl` (plain Python), `environment.txt`, `venv-environment.txt`. One line per event:
sequence number, thread id, event.

**Plain Python 3.13.5** (`control.jl`): `threading.Thread.join()` is a real `pthread_join` —
`create`, the worker's `started`, its `open64`, `join-enter`, `join-return rc=0`, the main
thread's `open64`, in that order. Through 3.12 CPython detached every thread and waited on a
lock, so nothing below reaches a Python target older than 3.13.

**beets 2.1.0, `import -q`** — 54 events per run, the same shape in three of three:

1. the main thread (tid 18 in run 1) opens `library.db` read-write — its only operation on the
   database; it writes nothing to that descriptor and closes it at the end;
2. it creates three threads (19, 20, 21), one after another;
3. thread 20 opens `library.db` and `library.db-journal`, writes the journal (`pwrite64` ×11,
   `fdatasync` ×2), writes the database (`pwrite64` ×3, `fdatasync`), closes and unlinks the
   journal — 22 operations without the close;
4. thread 21 does the same, in turn, after 20's last operation, with fewer writes (journal
   `pwrite64` ×8, database ×2; 18 operations without the close);
5. the main thread joins 21, then 19, then 20, and closes its descriptors. Thread 19 wrote
   nothing.

Threads 20 and 21 are siblings: both created by the main thread, both joined after both had
written, **no join and no creation between one's writes and the other's**. What orders them is
the import pipeline's queue (`beets/util/pipeline.py`: one `Thread` per stage, a task handed
from stage to stage), which is a lock and a condition variable — not a call the shim
interposes. **No rule built on creations and joins admits beets**, and this record's second
half confirms the refusal and reads its sentence.

**virtualenv 20.31.2** — 991 probe lines per run; the same shape in three of three, with one
difference inside a single thread noted below. Counts below are operations, closes excluded
(the probe logs a `close` for every open it logged):

1. the main thread (tid 10 in run 1) performs 18 operations (23 probe lines): `mkdir` of the
   root, `bin`, `lib`, `lib/python3.13`, `site-packages`; three `symlink`s in `bin`; five files
   opened and written — `pyvenv.cfg`, `_virtualenv.pth`, `_virtualenv.py`, `CACHEDIR.TAG`,
   `.gitignore`;
2. it creates a thread (11) and joins it at once; that thread writes nothing;
3. it creates a second thread (12) — **glibc hands it the same `pthread_t` value as thread 11**
   (`ffffb7f84160` in run 1) — which installs pip into `site-packages`: 499 operations (440
   `open`, 55 `mkdir`, 4 `write`; 939 probe lines), the main thread silent throughout;
4. it joins 12;
5. it performs 14 operations (21 probe lines): the six activation files in `bin` (`activate`,
   `activate.csh`, `.fish`, `.nu`, `.ps1`, `activate_this.py`) and `pyvenv.cfg` again, each
   opened and written.

A creation orders 1 before 3, a join orders 3 before 5. **A rule reading joins alone does not
admit this run** — the worker's first write follows the main thread's first writes by the
creation, not by a join — and a rule reading creations and joins does. The difference between
runs is inside thread 12: the order in which pip writes its four console scripts — `pip3.13`,
`pip-3.13`, `pip`, `pip3` in run 1; `pip-3.13`, `pip`, `pip3`, `pip3.13` in runs 2 and 3
(probe lines 957–968): `pip3.13` moves from the first position to the last, the other three
keep their order. The class sequence is the same at every position.

## 2. The v18 run

`apparatus/run-v18.sh`, the branch build (`transcripts/v18/version.txt`: `sideeye 1.4.0 (trace
contract v18)` — the version string is the release's, the contract is this PR's), in the box
`apparatus/Dockerfile.measure` builds (Python 3.13.5, virtualenv 20.31.2, beets 2.1.0, strace
6.13, aarch64; `transcripts/v18/environment.txt`). Every row is the report's own headline,
copied.

| | `--observe` | runs | what the report said |
|---|---|---|---|
| virtualenv, `preflight --twice` | wrappers | 1 | `PREFLIGHT recording accepted — 1381 state-changing operation(s) observed`; oracle agreed on 1381 operations; two runs left equal state; the account: `2 thread(s) created, and 2 thread id(s) of the subject's own process wrote the judged directory; 2 hand-over(s) between threads in causal order, 2 join(s) and 0 detach(es) recorded` |
| **virtualenv** | wrappers | 1 | **`PASS 1382/1382 explored worlds satisfied the built-in atomicity invariant`** (1381 crash points + the baseline), `oracle_verified` true, the same account |
| virtualenv, `preflight --twice` | syscalls | 1 | accepted, 1381 operations, oracle agreed, two runs equal, the same account |
| **virtualenv** | syscalls | 1 | **`PASS 1382/1382`**, `oracle_verified` true, the same account |
| **beets** | wrappers | 3 | `UNKNOWN multiple_threads_detected`, 3 of 3: *"two threads of process N wrote in the judged directory: tid A performed unlink(…/lib/library.db-journal) and tid B performed open(…/lib/library.db). No thread creation or join the shim recorded orders the first of those before the second, so their order is the scheduler's choice on this run …"*; the account: `3 thread(s) created, and 3 thread id(s) of the subject's own process wrote the judged directory; 1 hand-over(s) between threads in causal order, 3 join(s) and 0 detach(es) recorded` |
| **beets** | syscalls | 3 | the same refusal, 3 of 3, the same sentence shape (six sentences identical once thread ids and paths are masked) |

**virtualenv is the first target judged with two writing threads.** The thread rule admitted
the recording in both modes and in both preflight runs — the account counts two writing thread
ids and two hand-overs, which is the property exercised, not skipped — and the explore ran the
1,381 crash points to a verdict: every world left the first environment's `python` runnable,
which is what the define's checker asks. The PASS was not predicted; "reaches a verdict" was.
Three thread ids wrote in beets' recording — the main thread's open of the database and the
two workers — and two in virtualenv's; the accounts say so.
The two hand-overs are the creation (the main thread's 23 records, then the pip thread's) and
the join (the pip thread's records, then the main thread's six activation files and `pyvenv.cfg`); the two
joins are that one and the silent thread's. The order in which pip writes its four console
scripts varied between the probe runs; it did not refuse the run — the class sequence and the
addresses are what a world is held to, and the checker never looked at those files.

**beets stays refused, and the refusal now says why.** Three writing thread ids: the main
thread's open of the database, then two pipeline workers, each writing the database and its
journal in turn. The sentence names the second worker's first operation (its `open` of the
database) and the first worker's last (its `unlink` of the journal) and says no creation or
join the shim recorded orders the one before the other — which is the probe's finding read
back from the engine: the workers are siblings, and the queue that orders them is not a call
the shim sees. The one hand-over the account counts is the first worker's writes following
the main thread's open, by the creation. The prediction said the sentence would name "two
worker threads' opens of `library.db`"; it names the first worker's *last* operation and the
second's first, which is what ADR 0067 decision 4 says it names — the prediction's wording was
loose, the mechanism was as predicted.

**What was cut, and why the reason was wrong.** The first attempt ran virtualenv three times
per mode; its preflight showed 1,381 kill points, an explore was estimated at an hour, and the
run was stopped and restarted at one explore per mode (`apparatus/run-v18.sh` says so). The
explore then took about seven minutes: the estimate was of two environment builds per world
under strace, and a world is one build plus the setup's, with the first environment cached by
the setup's own `--no-download`. Three per mode would have fit. The record has one explore per
mode and three recordings per mode where the thread rule was asked (the two preflight runs and
the explore's), and says so rather than being re-run to match the plan's number.

## Predictions against measurement

The paragraph in `BUILDLOG.md` ("the predictions, written before the v18 run", timestamped).

- virtualenv not refused `multiple_threads_detected` in either mode, account with two writing
  ids and a hand-over — **held**, both modes, three recordings each.
- virtualenv reaches a verdict — **held**: PASS in both modes. Which verdict was not predicted.
- pip's console-script order does not refuse the run — **held**.
- beets refused `multiple_threads_detected` in both modes, three of three — **held**.
- the sentence names two worker threads and no creation or join between them — **held**; the
  operations named are the first worker's last and the second's first, not two opens.
- three explores per mode for beets, one for virtualenv — **as run**; the reason for one was
  a wrong estimate, above.

## What this record does not claim

- That virtualenv has no crash-consistency defect. The checker asks that the first environment
  still runs; it does not open the second, half-made one, and a PASS over 1,381 worlds is a
  PASS of that question.
- That the build measured is a release. It is this branch's tree before the post-review fixes
  to the reader (an exec-continuation count, `src/engine/trace.zig`) and to the toys and pages;
  neither target replaces its own image (`processes` says so in every report), so the reader
  fix does not reach these runs.
- That three recordings of virtualenv are three explores. They are two preflight runs and one
  explore per mode; the thread rule is asked of every recording, the verdict of the explore.
- Anything about beets past the thread rule: it is refused there, in both modes.

## Files

- `SELECTION.md` — the two targets and the five not taken.
- `apparatus/joinlog.c`, `run.sh`, `run-venv.sh`, `mkwav.py`, `Dockerfile.probe`,
  `Dockerfile.probe-venv` — the probe; `run-v18.sh`, `Dockerfile.measure` — the v18 run.
- `transcripts/probe/` — `import.{1,2,3}.jl`, `ls.jl`, `control.jl`, `venv.{1,2,3}.jl`,
  `environment.txt`, `venv-environment.txt`, `run.log`.
- `transcripts/v18/` — `virtualenv.preflight-twice.{wrappers,syscalls}.txt`,
  `virtualenv.{wrappers,syscalls}.1.{txt,json}`, `beets.{wrappers,syscalls}.{1,2,3}.{txt,json}`,
  `version.txt`, `environment.txt`, `run.log`.
