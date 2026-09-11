# mlr under the widened trap set (#542, second of two)

**Question.** #542 asks for mlr's writer count. The first change (PR #561) got the refusal
to name mlr's real wall — `oracle_missed_operation` at the `openat` of `mlr-in-place-*`,
six runs of six — and that wall is not an oracle problem: mlr is Go and issues its file
syscalls without passing through libc, so no interposed wrapper sees any of them. This
change widens `--observe syscalls` from the write family to every kill point, and the
measurement below is the same define run in both modes against the **same build**, so the
pair is a comparison rather than two readings.

**Apparatus.** `apparatus/mlr.sh <label> [mode]`, six explorations each, image
`sideeye-reach:2026-09-07`, mlr 6.13.0, aarch64. The binary is this branch's build, not a
release: `sideeye version` prints **1.3.0** in every transcript because the version is bumped
at release and not per change, so the string does not identify the build and nothing here
claims it does. What identifies it is the behaviour — a 1.3.0 release traps four syscalls
and would refuse every `syscalls` row below at operation 1, exactly as the `wrappers` rows do.
Define: `mlr -I --csv put '$c=1' f.csv` over a two-row CSV, with a check that the file
still exists and still has its rows. Transcripts in `transcripts/`, one `.txt` and one
`.json` per run.

## What changed

| mode | 6 runs |
|---|---|
| `wrappers` | 6/6 UNKNOWN `oracle_missed_operation`, every one at operation 1, the `openat` of `mlr-in-place-*`, with **the shim's account ending after 0 operations** |
| `syscalls` | 0/6 that. 5/6 UNKNOWN `multiple_threads_detected`; 1/6 PASS over 4 worlds |

The wall moved, which is the whole change in one line. Under `wrappers` the shim records
nothing at all for a Go target; under `syscalls` it records everything mlr does, and what
stops the run is no longer the observer.

## The writer count, which is what was asked for

The run that reached a verdict (`mlr.after.syscalls.6`) explored **3 crash points**, with
the oracle agreeing on 3 operations out of 183 syscall lines. Those three are mlr's
writers, and the oracle capture names them individually.

**The capture is committed** — `transcripts/mlr.after.syscalls.capture-run.oracle.txt`,
190 lines, from a seventh run of the same define kept for this purpose because the six
above record only the engine's report. That run refused `multiple_threads_detected` like
five of the six; its report is beside it as `…capture-run.txt`. Absolute paths in both were
rewritten to `/RUN`. Verbatim, the three `--- SIGSYS … SYS_SECCOMP ---` lines it holds, one
per trapped call and all three from **one code address** in Go's runtime:

    17  si_code=SYS_SECCOMP, si_call_addr=0x47e740, si_syscall=__NR_openat
    19  si_code=SYS_SECCOMP, si_call_addr=0x47e740, si_syscall=__NR_write
    19  si_code=SYS_SECCOMP, si_call_addr=0x47e740, si_syscall=__NR_renameat

The two thread ids in front of them are the writer count again, from a third direction.

The five runs that refused name the count a different way, and it is the more interesting
answer: **the writes come from two threads of one process.** Verbatim from run 1 —

> two threads of process 25 wrote in the judged directory: tid 25 performed
> `open(…/mlr-in-place-281416832)` and tid 28 performed `write(…/mlr-in-place-281416832)`

Go's runtime schedules the open and the write onto different OS threads, and which thread
gets which varies run to run — run 6 happened to land both on one, which is why it was
judged. That is a true statement about mlr, produced by the v16 thread rule doing its job
on an account it could not previously see; the ordering caveat in the refusal text is the
reason it is a refusal rather than a verdict.

## What this does not say

- **Not a verdict on mlr.** One PASS out of six is not evidence that
  `mlr -I` is crash-safe; it is evidence that the run can be judged at all now. The
  thread-scheduling variance is the next wall, and it belongs to the v16 thread rule
  rather than to the observer.
- **The kept file is unchanged.** The check falsified before the run in every case
  (`falsify: f.csv lost rows`), so the checker was exercised; the verdict above is the
  built-in atomicity invariant, not a domain judgement.
- **aarch64 only.** The eight legacy spellings (`open`, `creat`, `rename`, `unlink`,
  `rmdir`, `mkdir`, `link`, `symlink`) exist as syscalls on x86-64 only and are not
  exercised by anything here; `spike/acceptance.sh`'s `toy-raw raw-all` leg covers them on
  CI's other row.

## A plan premise that was wrong

The plan named the evidence for the `sigaction` interposition as "the
`rt_sigaction(SIGSYS, …) = 0` line in the oracle capture". **That line cannot be there.**
The engine runs strace with `-e trace=%file,%desc,%process,setsid,setpgid`, which does not
include the signal-setting calls, so the capture holds none of them — measured on the
committed capture: `grep -cE 'rt_sig(action|procmask)'` gives **0** across its 190 lines.

The evidence is stronger than the line would have been anyway. Go installs its own
`SIGSYS` handler through libc `sigaction` (measured before this change), and a target that
succeeds in replacing the shim's handler dies at the first trap — rc 159, which is exactly
where mlr was before. Three traps delivered to the shim's handler **and the process
running to completion** says the handler survived; the `rt_sigaction` line would only have
said the call was made.
