# Results — 2026-09-27 supervised-static

Engine: `main` at `01e6760`, built in the box (`transcripts/build.txt`; not a shipped build —
`SELECTION.md`). Box: `apparatus/Dockerfile`, aarch64, privileged, own cgroup namespace,
`--network none`. Every number below is read from `transcripts/<target>/`: `entry-*` is the row
reproduced in its own mode, `sup-preflight-{1..5}.txt` the five `preflight --twice --observe
supervised --oracle /usr/bin/strace`, `sup-explore-{1..3}.{txt,json}` the explores under the same
flags. Predictions: `PREDICTION.md`, committed before any supervised run (`5153ebc`).

## The denominator, all seven

| target | the row's mode, reproduced | preflight under supervised | explores under supervised | files the built-in rule judged | prediction |
|---|---|---|---|---|---|
| jj 0.44.0 `commit` | `no_shim_marker` (wrappers) | **0/5** — `multiple_threads_detected` 5/5: the main thread opens `.jj/working_copy`, another opens a temporary under `.git/objects` | not run | — | missed (predicted a verdict) |
| chezmoi 2.72.1 `apply` | `no_shim_marker` (wrappers) | **0/5** — `recording_run_failed` 5/5: the second observed run exits 1 (below) | not run | — | missed (predicted `multiple_threads_detected`) |
| gopass 1.17.0 `generate` | `no_shim_marker` (wrappers) | **0/5** — `preflight` not accepted 5/5, `test/generated.age (content differs)`: a random secret, age-encrypted | not run | — | missed (predicted `multiple_threads_detected`) |
| gh 2.97.0 `config set` | `no_shim_marker` (wrappers) | **5/5** accepted, 2 operations | **PASS 3/3**, 2 crash points, oracle agreed on 2 | **0** — `config.yml` is created by the operation | missed (predicted `multiple_threads_detected`) |
| lefthook 1.13.6 `install` | `oracle_missed_operation` (syscalls) | **5/5** accepted, 4 operations | **UNKNOWN 3/3** `checker_not_falsified` (below) | — | missed (predicted `multiple_threads_detected` or `child_touched_state_dir`) |
| busybox `sed -i`, direct | `no_shim_marker` (wrappers) | **5/5** accepted, 3 operations | **PASS 3/3**, 3 crash points, oracle agreed on 3 | **1** — `f.txt`, the file it rewrites | met |
| sh → busybox `sed -i` | `recording_run_failed` (syscalls), `SIGSYS si_code=SYS_SECCOMP` on the busybox pid | **5/5** accepted, 3 operations | **PASS 3/3**, 3 crash points, oracle agreed on 3 | **1** — `f.txt` | met — the same verdict and counts as the direct spelling |

Predictions met: 2 of 7. The four Go tools were predicted to stop at the thread wall; one did so
once (chezmoi with `--force`, 1 of 5 preflights); none of the four met it in 4 of 5.

Reference, outside the denominator: lefthook through `sh` (`lefthook-sh`), with the 2026-09-21 checker —
5/5 accepted with 4 operations, explores UNKNOWN 3/3 `checker_not_falsified`, the same as lefthook
direct. It was not run without the checker.

The `*-summary.txt` files of gopass, gh, lefthook, bbsed, shbb and lefthook-sh carry an empty headline after each `preflight`
line: the summary's pattern was fixed between that run and the corrections'. The counts above are
read from the transcripts themselves, not the summaries. jj's own output in its transcripts says
`(divergent)`: its setup rebuilds the repository each world, and this run did not look further — the
refusal is the thread wall either way.

## Three defines corrected after their result, and what they then did

Each correction is to the define, made after the fixed define's result above was recorded, and each
is labelled a correction in `apparatus/run.sh`. The rows above stand as the fixed defines' results.

| target | what was wrong with the define | corrected | preflight | explores | files judged |
|---|---|---|---|---|---|
| chezmoi `apply --force` | `preflight --twice` restores only `--state`; chezmoi's own database under `$HOME` remembers the first run, and the second asks `.second has changed since chezmoi last wrote it` and exits 1. **The same with no engine at all** (`transcripts/chezmoi/no-engine-control.txt`, `apparatus/cz-control.sh`, run in the same `sideeye-217s` box, `--network none`): two plain `apply` runs with the destination emptied between them, the second asks and exits 1 with the same `chezmoi: .second: EOF` the engine's second run printed; with the database removed, 0 | `--force` | **4/5** accepted (5 operations); **1/5** `multiple_threads_detected` — two threads of one process each `rename` a temporary into place, in the second observed run | **PASS 3/3**, 5 crash points, oracle agreed on 5 | **0** — the destination starts empty |
| gopass `rm -f seed/entry0` | not a fault of the define: `generate` writes random bytes by design, so no two runs repeat — a property of that operation | a different operation, one that writes nothing random | **5/5** (3 operations) | **PASS 3/3**, 3 crash points, oracle agreed on 3 | **1** — `.age-recipients`, which the operation does not change; the removed entry is absent afterwards |
| lefthook `install`, no checker | the 2026-09-21 checker accepts a hooks directory with no lefthook hook in it (install had not got there), so it also accepts that directory overwritten with junk | built-in atomicity only | **5/5** (4 operations) | **PASS 3/3**, 4 crash points, oracle agreed on 4 | **13** — git's `*.sample` files, which the operation does not change; the hooks it writes are new |

## What the verdicts say, and what they do not

- **busybox `sed -i`, both spellings, is the only PASS here about a file the tool rewrote.** The
  built-in rule judges a file present both before and after the operation (DESIGN.md, L0): `f.txt`
  is one, and in every explored world it held the old bytes or the new ones.
- **The Go PASSes judged no file the tool wrote.** gh's `config.yml` and chezmoi's destination
  files are created by the operation, and the hooks lefthook writes are new, which L0 leaves
  unconstrained; gopass's judged file is one `rm` does not touch. They show the mode **reaches** a
  verdict on these tools — past `no_shim_marker` and past `oracle_missed_operation`, with strace
  agreeing on the count in the same run — not that their writes are crash-safe. A claim about those
  bytes needs a checker; none is written here.
- **jj is the thread wall, 5 of 5**, where the prediction said a verdict. Two threads write: the
  main thread `.jj/working_copy`, another a temporary under `.git/objects`. This mode records a
  thread's creation but not which thread it created, and no join, so writes from two threads of
  one process refuse (`docs/cli.md`, `--observe supervised`).
- **The unsafe target behaves as the direct one.** Under `--observe syscalls` the dynamic `sh`
  carries the shim's filter into the `exec`, the static busybox has no handler, and the capture
  shows `--- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, …, si_syscall=__NR_openat, …}` and
  `+++ killed by SIGSYS +++` on pid 34, the pid that `execve`d `/bin/busybox`
  (`transcripts/shbb/entry-oracle.txt` lines 54–59). Under supervised nothing is installed in the
  target, and the run reaches the same PASS over the same 3 crash points as the direct spelling.

## #217's closing condition, as fixed before the measurement

1. A target the current engine refuses `no_shim_marker`, accepted 5 of 5 and one verdict in 3 of 3
   under supervised: **busybox `sed -i` — met** (PASS 3/3). jj — not met (thread wall).
2. The structurally unsafe target, SIGSYS and `recording_run_failed` under syscalls, then 5 of 5
   and 3 of 3 under supervised: **sh → busybox `sed -i` — met**.
3. The report's disclosure (PR #664) merged: **met**.

The conditions hold. This pull request still says `Refs #217`: reading the reports for this run
found that under supervised the thread refusal and the `processes` line say "the shim recorded",
and the refusal says a process whose writes a creation or a join orders "is judged" — in a mode
that loads no shim and records no join. The verdicts are right; the sentences are not. The owner's
ruling (2026-09-27): fix the wording in its own pull request, and close #217 there.

## Found in passing

- **Where the report misnames the observer** (above): `src/boundary.zig`'s `threadDetail` and the
  `processes` line, both under `--observe supervised`. Not changed here — this run changes no engine
  code.

## Novelty

No FAIL, so nothing to check upstream and nothing to report.
