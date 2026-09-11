# 2026-09-11 — results

Host: macOS on Apple Silicon, Docker 29.4.0, `linux/arm64`, base image
`debian:trixie-slim`. **Sideeye is the released v1.3.0, not a build**:
`sideeye-v1.3.0-aarch64-linux.tar.gz` from the GitHub release, its sha256
(`ef94464f5d96f2e23b65ab8a55abe7cc34bafe1c2a5295cba303a23bfc92db8e`) matched
against the digest the release publishes, mounted read-only. It reports
`sideeye 1.3.0 (trace contract v16)`. The 2026-09-06 run built from its own
branch and got the wrong version (`spike/dogfood/README.md`, "Which build a run
measures"); taking the tarball removes the build step
rather than checking it. State and work live on the container's own filesystem
(#528). Every quoted report line below is the report's own, and `…` marks where one is
cut. What was measured by hand during the run and quoted here is recorded under
`transcripts/probes/`: the release digest, the versions, the ELF headers, the `ulimit`
and `strace -k` runs, the newsboat `--twice` runs, the `setsid` capture and the novelty
searches.

## Seven targets: three verdicts, two refusals that now say the true reason, two new walls

| Target | Turned away before for | Under v1.3.0 | Transcripts |
|---|---|---|---|
| **oxipng** 10.2.1 | threads (rayon) | **FAIL** 1/3, crash point 2 of 2 — both modes; 5 of 5 repeats under wrappers | `transcripts/explore/oxipng.*` |
| **rsync** 3.4.1 | forked children | **PASS** 7/7 — both modes; 5 of 5 repeats under wrappers | `transcripts/explore/rsync.*` |
| **newsboat** 2.36 | threads | **PASS** 44/44 judged by SQLite's own recovery; strict **FAIL** 15/44 by bytes | `transcripts/explore/newsboat3*` |
| joplin CLI 3.7.1 | threads (any) | `multiple_threads_detected` **by the writer count**: four threads write | `transcripts/screen/joplin.*`, `transcripts/explore/joplin.prep*` |
| Bun 1.4.2 | threads (any) | past the writer count; `oracle_missed_operation` on a raw `openat` | `transcripts/screen/bun.*`, `transcripts/explore/bun.prep*` |
| ansible-core 2.19.4 | threads + children | `child_process_detected` — a process leaves the containment group | `transcripts/screen/ansible.*` |
| ocrmypdf 16.7.0 | children | `unsupported_syscall_observed` on `faccessat2` | `transcripts/screen/ocrmypdf.*` |

Behind two of the refusals, read to the end, were two defects in Sideeye itself:
**#555** (loading the shim refuses a thread with a small stack) and **#556**
(under `--observe syscalls`, a Python child whose exec fails along `PATH` dies of
`SIGSYS`). Neither changes a verdict recorded here. Both are below.

## oxipng: the truncating create, reached through the thread rule

```
FAIL  1 of 3 explored worlds violated an invariant
earliest    crash point 2 of 2
            after  open(/localrun/st/wrappers/oxipng/a.png)
            before write(/localrun/st/wrappers/oxipng/a.png)
path        a.png
observed    holding neither the old nor the new content
processes   single process in the recording; a thread was created in an explored world;
            the shim recorded 10 thread(s) created, and 1 thread id(s) of the subject's
            own process wrote the judged directory (v16: one per process is judged, two refuse)
```

The rayon pool does the compression and the main thread alone opens and writes
the file, so the thread rule admits it. The checker decodes the PNG and demands
the setup's exact pixels (oxipng is lossless, so old and new decode the same); in
the failing world it printed `a.png is not a PNG (0 bytes)`, and its falsification
line reads `a.png is not a PNG (25 bytes)`. `--observe syscalls` gives the same
verdict at the same crash point, and five repetitions under wrappers each give
`FAIL cp=2`.

The write path, on `master` and in v10.2.1 alike, is `src/lib.rs` line 254:
`File::create(output_path)` and then `write_all(&optimized_output)`. `strace`
(`transcripts/probes/probes-review.txt`):

```
[pid   270] openat(AT_FDCWD</w>, "/localrun/st/ulimit/a.png", O_RDONLY|O_CLOEXEC) = 3</localrun/st/ulimit/a.png>
[pid   270] openat(AT_FDCWD</w>, "/localrun/st/ulimit/a.png", O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0666) = 3</localrun/st/ulimit/a.png>
[pid   270] write(3</localrun/st/ulimit/a.png>, "\211PNG\r\n\32\n…"..., 177) = 177
```

It reproduces with no crash at all: `( ulimit -f 0; oxipng -q -o 2 a.png )` exits
153 (`File size limit exceeded`) and leaves 0 bytes where there were 12,420, in the same
transcript. The
shape is jpegtran's, fonttools' and bean-format's — the new bytes are in memory
before the old ones are truncated. It is the first of that shape to arrive through the
thread rule: the two zero-byte FAILs that arrived that way on 2026-09-08 — bundler's
`Gemfile` and vips's `out.png` — were new files left empty, with no original to lose
(`spike/followup-item4/run.sh`: neither setup creates the file).

**Novelty.** One `gh search issues` query per word on `oxipng/oxipng`
(`transcripts/probes/novelty-oxipng.txt`, re-run after the filing, so #873 is among the
hits where it matches): `interrupted` #566 #873, `atomic` #333, `truncate` #452 #678
#714 #873, `in place` eight hits, `0 bytes` ten, `data loss` #478, `temporary file`
#275 #436 #549 #873, `killed` #100 #125 #834. Apart from #873, none is about an
interrupted in-place write. The same queries before the filing gave each count less
#873; that run's output was not kept. The nearest,
oxipng#478 "Thinking about output validation", is about checking the output's
pixels, not about how the output is written. **Rule 11**: the six most recent
issues drew a first reply from someone other than the reporter in 0.0–2.8 days
(#836, a bug, 0.0 d; #834, a crash, 0.1 d) — measured through the GitHub API before
filing; that output was not kept.

**Filed** as [oxipng/oxipng#873](https://github.com/oxipng/oxipng/issues/873), after the owner signed off on the full text (`report-oxipng.md`, beside this file). It is 224 words against a median of 110 over the tracker's eleven most recent issues
(measured before filing through the GitHub API; that output was not kept), with the provenance and the not-measured line folded into a `<details>`. It opens with the loss and the `ulimit -f 0` reproduction rather than a mitigating line, because the original is not recoverable (`spike/upstream-report-template.md`, third row).

## rsync: the first dogfood target through contract v15's awaited child

```
PASS  7/7 explored worlds satisfied the built-in atomicity invariant
      explored 7 worlds (crash points 6 + 1 baseline)
      oracle: agreed on 0 operations (521 syscall lines examined, 0 in scope of the
              judged state), witness strace — the SUBJECT's operations only. This run's
              crash points include operations performed by an awaited child, and those the
              oracle placed and ordered rather than compared one by one: this is
              `oracle_verified_subject_only`, and `oracle_verified` stays false. …
      processes: a process other than the subject operated on the judged directory, and
              those operations hold crash-point addresses: no two processes' operations
              interleaved and every writing child was reaped (contract v15). …
```

Each file is written to `.f1.txt.XXXXXX` in the destination and renamed over the
name, so every crash point leaves each file old or new. The checker compares both
files to both versions byte for byte and the untouched `keep.txt` to its original.
Five repetitions: `PASS cp=6` each. The claim is `oracle_verified_subject_only`,
weaker than `oracle_verified`, and the report says so in its own oracle line. The
oracle compared **none** of the subject's operations (`agreed on 0 operations`,
`0 in scope`): the subject writes nothing, so every crash point is the child's — the
slice the `pass` row of `docs/target-classes.md` calls the dangerous one.

**The first screen measured the apparatus.** It left `f1.txt` alone and wrote only
`f2.txt`: rsync's quick check compares size and mtime, and the setup wrote
`old one` and `new one` — eight bytes each — in the same second. The destination's
`f1.txt` became `old` (four bytes), and the second screen wrote both.

## newsboat: two refusals were the apparatus's, then the buku lesson a third time

Three defines, each one's result the reason for the next:

1. **`setup-newsboat2.sh`: `UNKNOWN baseline_violates_invariant`** on `cache.db`, in
   both modes. The feed carried no `pubDate`, and newsboat stores the second it read an
   undated item as its date: two reloads two seconds apart stored `1789105606` and
   `1789105608`, each the second its reload started. Measured after the first review
   asked (`transcripts/probes/probes-review.txt`): a plain `preflight` of this define
   accepts it (43 operations, both modes), and `preflight --twice` refuses it —
   `cache.db (content differs)`, two runs 2004–2005 ms apart, both modes. With a date
   on every item (`setup-newsboat3.sh`), `--twice` accepts in both modes.
2. **`setup-newsboat3.sh`: `FAIL` 15 of 44** under the built-in byte comparison,
   earliest crash point 26 of 43 — `after write(cache.db)`, `before write(cache.db)`.
   SQLite rewrites pages in place under a rollback journal, and the bytes between
   two page writes are what the journal is for. This is the class
   `docs/target-classes.md` records for buku and for bogofilter-sqlite: judging a
   journalled store by file bytes is stricter than its contract.
3. **The same define with `cache.db` and `cache.db-journal` declared scratch:
   `PASS` 44/44** in both modes, the checker falsified before the run. The checker is
   what decides: SQLite's `integrity_check` returns `ok`, the item from before the
   operation is still there, and the next reload — newsboat's own recovery, which is
   running it again — succeeds.

Two apparatus errors on the way. The first run of the dated define ran nothing
(`transcripts/runs/explore-run2.txt` — the name `newsboat3` had no call line, and the
`sed` meant to add one was pointed at `/dev/null`). The first scratch attempt passed
absolute paths and was refused at setup; that run's output was not kept, and the
refusal was reproduced afterwards with one absolute scratch path
(`transcripts/probes/probes-review.txt`: `a scratch path is relative to the state
directory; an absolute path cannot be under it`). `apparatus/explore-newsboat-scratch.sh`
is the second attempt.

## joplin: the writer count refuses it, and the error it printed was ours (#540, #555)

The strace screen: ten threads created, and **four tids of the one `node` process
wrote the profile** — one `unlinkat`s `tmp`, one `mkdirat`s it, one opens
`database.sqlite`, one writes and `fsync`s its journal, and all four write `log.txt`.
None of the four is the main thread. Node runs its asynchronous file calls on
libuv's thread pool, the likely owner of all four — that is Node's design, not
something this run measured. The refusal names two of them:

```
UNKNOWN  multiple_threads_detected
         two threads of process 430 wrote in the judged directory: tid 436 performed
         rmdir(/localrun/st/wrappers/joplin/tmp) and tid 437 performed
         mkdir(/localrun/st/wrappers/joplin). …
```

Both modes, and five of five repeated preflights under wrappers, name the same pair of operations. This is the
refusal v16 is meant to give. Whether the pool's writes overlap or take turns — the
question #539 would ask — is not measured.

**`node[430]: pthread_create: Invalid argument` is Sideeye's.** `docs/target-classes.md`
has carried that line against joplin since 2026-09-05 as unexplained, and #540 said
it "would need attributing before the count is even asked". The plain run under
`strace` printed nothing; the preflight printed it. Then, with no engine at all:
`LD_PRELOAD=libsideeye_shim.so node -e 1` prints it and `node -e 1` does not
(`transcripts/probes/probe-tls.txt`). The shim carries a `PT_TLS` segment of 262,165
bytes (`apparatus/elfsyms.py`'s `phdr` and `tls` modes, `transcripts/probes/elf.txt`),
262,144 of them in
`Thread.maybeAttachSignalStack.global.signal_stack` — Zig std's per-thread signal
stack, not the shim's own state, which is deliberately not `threadlocal`. A
preloaded library's TLS is part of the static block every thread's stack must hold,
and glibc refuses a smaller stack with `EINVAL`. The message is printed by node's
`StartDebugSignalHandler` (`src/inspector_agent.cc` line 126 at `v20.19.2`), which
starts the SIGUSR1 watchdog thread with a stack of `max(4 * 8192, PTHREAD_STACK_MIN)`
(line 108) — 128 KiB on this aarch64 host, where `PTHREAD_STACK_MIN` is 131072:

| requested stack | plain | `LD_PRELOAD=libsideeye_shim.so` |
|---|---|---|
| 128 KiB | ok | `Invalid argument` |
| 256 KiB | ok | `Invalid argument` |
| 384 KiB | ok | ok |

Filed as #555. It changes no verdict recorded here — joplin is refused for its
writers either way — but a target that asks for a small thread stack runs a different
program under observation: the probe's thread fails at 128 and 256 KiB and starts at
384 KiB, and where between 256 and 384 KiB the boundary falls is not measured.

## Bun: past the thread rule, and the raw-syscall wall behind it (#540)

```
UNKNOWN  oracle_missed_operation
         the oracle saw a state-directory operation the shim did not record; divergence
         at operation 1: the oracle saw: 541   openat(AT_FDCWD</…/bun>, "/…/bun/package.json",
         O_RDWR|O_LARGEFILE|O_CLOEXEC …
processes   single process in the recording; the shim recorded 6 thread(s) created, and
            1 thread id(s) of the subject's own process wrote the judged directory
```

The writer count admits Bun — one thread writes — and then the first operation is
one the shim never saw. Both modes; five of five repeated preflights under wrappers. Bun 1.4 is a Rust code
base (GitHub's language count for the repository today: Rust 41.7 M bytes, C++ 11.9 M, TypeScript 5.6 M,
C 1.4 M); its `src/sys/linux_syscall.rs` opens with *"Raw Linux syscalls via
`rustix` (linux_raw backend — no libc trampoline)"*, and `openat` on Linux calls
into it (`src/sys/lib.rs` line 1916, tag `bun-v1.4.2`). Not every file call does: the
shim records Bun's `mkdir` of `node_modules`, so the claim is about `openat`. The
binary does import `openat` from libc (`transcripts/probes/elf.txt`), which is why the
import table was not the answer; the call site is. This image's `strace` has no `-k`
(*"Stack traces (-k/--stack-trace option) are not supported by this build of
strace"*, `transcripts/probes/probes-review.txt`), so the attribution rests on the
source rather than on a stack.

That is the class of cargo's row and of #217: state-changing calls that bypass libc.
`--observe syscalls` does not reach it — it traps the write family only, and the
README says a raw `openat` is refused in either mode. The thread wall stood in front
of another one, as it did for zstd on 2026-09-08 (past the thread rule, onto the stdio
wall).

## ansible: a process leaves the group

```
UNKNOWN  child_process_detected
         a process left the containment group (setsid/setpgid); the engine cannot claim
         to have stopped it
```

Both modes. The strace screen counts one thread and 26 processes (`sh` ×10,
`sleep` ×5, …); the one write to the state is a module's `python3` renaming a
temporary file over `f.txt` — `renameat(tmpe1wb2a2c, f.txt)`, the safe shape. The
report says `setsid/setpgid`. A plain `strace` of the same command, tracing those two
and the process calls (`transcripts/probes/probes-review.txt`), finds one completed
`setsid()`, from a process forked from `/usr/bin/ansible` with no exec of its own in the
capture — plausibly a worker the controller detaches. That capture ran without Sideeye,
and its reader skips split `<unfinished ...>` lines; that this `setsid` is the one the
refusal saw is the likely reading, not a measured one. A containment escape is refused
by design, so this is a wall and not a gap.

## ocrmypdf: `faccessat2`, and #556 behind it

Both modes refuse `unsupported_syscall_observed` naming `faccessat2` — a permission
query, which changes nothing. That is #542's shape (mlr's `epoll_ctl`): a call
neither observer models, refused rather than classed as read-only. The fourteen
helper processes (`tesseract` ×6, `gs` ×5 in the screen) never touch the state.

Under `--observe syscalls` the transcript also carried
`Command '['jbig2', '--version']' died with <Signals.SIGSYS: 31>`, and the same for
`pngquant` — two optional tools that are not installed. **The first guess was wrong**:
a probe that runs a missing program by absolute path gets `FileNotFoundError` in
every mode. Copying ocrmypdf's own `get_version` reproduced it, and four variants
separated the cause (`transcripts/probes/probe-subprocess.txt`):

| `subprocess.run` of a missing program | plain, and `--observe wrappers` | `--observe syscalls` |
|---|---|---|
| absolute path, with or without pipes | `FileNotFoundError` | `FileNotFoundError` |
| bare name (PATH search), with or without pipes | `FileNotFoundError` | returns, `returncode -31` |

The preflight says `recording accepted` either way. The mechanism is inferred, not
measured (about 75%): CPython takes `posix_spawn` when the executable has a
directory part, which reports a failed exec through shared memory; for a bare name
it takes `_posixsubprocess`, whose child resets its signal handlers and then
`write`s the errno to the error pipe — a write the inherited filter traps while
`SIGSYS` is at its default. The README says a child the shim is loaded into "is
unaffected". Filed as #556.

## The screen, and what it missed

The screen ran two instruments per target before any checker existed: `strace -f`
read by `apparatus/screen-strace.py` (threads, processes, and which tids of which
process wrote the state — the question v16 asks), and `sideeye preflight` in both
modes. It named every refusal above before an explore ran, with one exception:
newsboat, and there the screen had preflighted a different define — the first reload
into an empty directory — not the one with a cache already in the state that the
explore used. A plain `preflight` of the explored define accepts it too; `--twice`
refuses it, which the review's probes measured. **The screen should run `--twice`,
on the define that will be explored.** The
ordering rule's sunset condition — the screen says measurable, the engine refuses —
is not met by that case, because the refusal was the apparatus's and the fixed
define was judged. Bun is the other near miss: the strace instrument said one writer,
which is true, and preflight refused on an axis that instrument does not claim to
measure.

## What the run cost, and the apparatus errors inside it

Two image builds (the second only to add oxipng, which Debian trixie does not
package; `transcripts/runs/build.log`, `build2.log`), two screen runs, five explore
invocations (one judged nothing, one was refused at setup), one run of the review's
probes, and five apparatus errors:
`mkpdf.py` copied into the build context instead of the mounted apparatus directory
(ocrmypdf's first setup failed), rsync's same-size same-second setup, newsboat's
undated feed, the define with no call line, and the absolute scratch paths. One
hypothesis was wrong and refuted by measurement (the absolute-path `SIGSYS` probe).

The three largest `strace` captures (ocrmypdf 900 KB, joplin 684 KB, ansible 308 KB)
are not committed; `apparatus/screen.sh` regenerates them.

## What moves upward

- `docs/target-classes.md`: three verdict rows (oxipng, rsync, newsboat); the joplin
  and Bun rows rewritten from this measurement, which answers #540; two refusal rows
  (ansible, ocrmypdf).
- `spike/dogfood/RUNS.md`: one row.
- #555 and #556, filed the same day.
- `spike/upstream-reports.tsv`: nothing unless oxipng is filed.
