# 0088 — The loop-closure replay runs on the image's root filesystem, in a container of its own, and is read only when that container exited 0

- **Status:** Accepted (2026-09-27)
- **Closes:** #603, the residual ADR 0068 named in its Consequences ("Named residual, and a
  separate promise — the measurement's root filesystem"). An amendment note on that page points here.
- **Scope:** `spike/loop-closure-timew/judge.sh` (`cmd_eval`, the header's trust list),
  `spike/container_seals.py` (`judge_eval_split`, `precondition`, their selftest cases),
  `spike/loop-closure-timew/measure.py` (the files it holds for eval and for the controls),
  `spike/loop-closure-timew/seal-reds/MUTATIONS.md`, `CHANGELOG.md`. Nothing in the engine, the
  report schema or any frozen surface.

## Context

`judge.sh eval` built the agent's `repo/` and replayed the sealed case in one `--network none`
container. The container runs as uid 0 on a writable root filesystem, and the agent's code runs
as root before the replay does: `cmake -S` executes the agent's `CMakeLists.txt` at configure
time, and the agent-built `timew` runs during the functional gate. Everything the replay then
loads from the root filesystem was the subject's to replace — `/usr/bin/strace`, which the replay
is given as `--oracle`; the `sh` the checker runs under; `libc`, and through it every dynamically
linked binary exec'd afterwards, the sealed `sideeye` among them (the harness is built for
`aarch64-linux-gnu`, dynamically linked). ADR 0068's seal says the file the judge opens is the file
`sideeye` wrote; it could not say `sideeye` ran on a pristine image.

**Measured on the one-container judge, not argued.** A toy `repo/` whose `CMakeLists.txt`, at
configure time, moves `/usr/bin/strace` aside and puts a wrapper in its place, and replaces
`/bin/sh` with one that answers 0 whenever its first argument ends in `check.sh`, was judged
`eval --mode run` on a fresh stage: the replaced `sh` ran 243 times and the replaced `strace` once
during the replay (both appended to a file in the replay's output directory), and the replay gate
moved from `fail_reproduced` — what the same unpatched tree gets — to `other`
(`checker_not_falsified`: the engine noticed a checker that never fails, which is the only reason
the forgery did not read as a PASS). The same toy without the checker rule reached the replay as
well and left the gate `fail_reproduced`: the replacement arriving was never in doubt, only what
the subject chose to do with it.

Two reviews of the plan found a second hole on the same line as ADR 0068's, and it is closed here
too because the split would otherwise have widened it. The seal rule — a token counts wherever it
appears and must appear exactly once — stops a forgery being **added**; it does not stop the real
token being **withheld**. A build that prints a forged `replay-rc`, a forged seal and the two
functional-gate tokens, then fails, leaves each token exactly once in the stream, and a report
whose digest matches sits where the measurement would have written: every channel sealed, the
forged PASS among them, and `finalize`'s `loop_closed` — which reads the gates and not the
container's exit — true. That is reproduced as case (a) of `container_seals.py --selftest`, which
asserts that the one-stream reading seals it.

## Decision

1. **Two containers.** The build and the functional gate stay in the first, as they were; the
   built `timew` leaves it through a directory of its own (`/out`). The replay runs in a second
   container started from the image **by id**, `--read-only`, with `--mount type=volume,dst=/tmp`
   (an anonymous volume, removed with the container), the stage read-only, `timew` in a
   directory holding nothing else mounted read-only at `/tmp/loop-bin`, and one output directory.
   `/tmp/loop-bin` keeps the path the case was recorded with, and read-only it cannot have
   another `sh` planted ahead of the image's on `PATH`.
2. **The ground is the volume, admitted by measurement.** The case was recorded over the
   container's overlayfs; the volume is ext4 on Docker Desktop's disk. `tmpfs` stays refused, as
   ADR 0068 refused it. The two controls, re-run under this judge on a fresh stage (the pin's case
   `k=19` of 24): neg `fail_reproduced` at 19, pos `pass`, `expectation_met` true for both, both
   containers exiting 0. Had either not reproduced, this would not have shipped.
3. **Each channel from its own container's stream** (`container_seals.judge_eval_split`): the
   functional gate's two tokens from the build's (`<mode>-build.log`), the replay's rc and
   `sideeye`'s seal from the measurement's (`<mode>-measure.log`). A token printed during the
   build can then never stand for the replay. `container_seals.py`'s existing functions are
   unchanged; the split only chooses which bytes each is handed.
4. **Whether the measurement ran is the host's fact** (`container_seals.precondition`): the build
   exited non-zero, or its `timew` did not cross, → `build_failed` and the measurement is never
   started; the measurement exited non-zero → `measurement_did_not_complete`, and no token in its
   stream is read. Only when both exited 0 do the tokens decide. The verdict records `build_rc`
   and `measure_rc` in place of `container_rc`, `build_ok` is `build_rc == 0` rather than "the rc
   token sealed", and a control's expectation requires both statuses 0. A missing rc token with
   both containers at 0 now reads `seal_missing`, not `build_failed`.
5. **Directories the host hands a container are made with `mkdir`, not `mkdir -p`,** under names
   unique to the run, so a name already taken — a leftover, or a symlink planted where the next
   run's would be — fails instead of being followed or reused. `timew` crosses as one regular file
   opened with `O_NOFOLLOW`, under a 512 MiB cap, written with `O_EXCL` and made 0755 on the host.
6. **`measure.py` holds the two streams and the two captures of docker's stderr** for the run and,
   as pre-run inputs, for both controls. `<mode>-container.log` / `.err` are still written — the
   two concatenated, for a person — and are not held: holding a file the verdict does not read
   would attest the wrong ground.

**What the measurement can write**, measured with `--read-only`, the volume and the read-only
bind on Docker Desktop: `/tmp` (the volume), docker's `/dev` (tmpfs), `/dev/shm`, `/dev/mqueue`,
and its output directory. `/`, `/usr/bin`,
`/lib`, `/etc`, `/root`, `/run`, `/var/tmp`, `/tmp/loop-bin`, the stage, and docker's bound
`/etc/hosts`, `/etc/resolv.conf` and `/etc/hostname` are not writable. None of the writable places
is on `PATH`, is searched by the loader (no `LD_LIBRARY_PATH` is set, and `/etc/ld.so.cache` is the
image's), or is the checker's `python3` working directory. That last holds **for this case**: the
checker runs `python3 -`, which puts its working directory first on `sys.path`, and that directory
is the case's `command_cwd` — measured `/work`, the image's WORKDIR, because the define declares no
`cwd`. A define that declared one on the volume would put a place the subject writes ahead of the
standard library. `/dev` being writable means the subject can replace `/dev/null` during the
replay; that is the residual below (what it writes during the replay), not a replacement from before
it, and it reaches no `PATH` entry.

## Alternatives considered

- **One container, `--read-only`.** The build and the functional gate write the root filesystem.
- **`--tmpfs /tmp`.** Moves the observed directory to another filesystem than the one the case
  was recorded on; refused by ADR 0068 and by #603.
- **Name every external binary by absolute path and keep one container.** A replaced `libc` or
  `sh` is not reached by path.
- **One concatenated stream, read as before** (the first draft). The withheld-token forgery above
  seals under it; this was the first review's critical finding.
- **Bind `timew` as a single file.** Leaves `/tmp/loop-bin` itself on the writable volume, and
  `PATH`'s first entry the subject's.
- **The same split for `secondary`.** It is evidence, not a gate (`loop_closed` is audit, replay
  and functional); left as the header already lists it.

## Consequences

- **Still outside, and named in the judge's header:** what the subject writes *during* the replay.
  It is uid 0 in the measurement container too, so the oracle's output and the shim's trace under
  `--work /tmp/judge-work` are within its reach while it runs. Separating them needs another uid for
  the subject, which ADR 0068 declined because the uid enters the operation string the case records.
  What this decision does narrow: `/tmp` is a fresh volume per measurement, so nothing the subject
  did during the build can be waiting there.
- **Still outside:** a same-uid process that ptraces the measurement's shell (PID 1, which a signal
  from inside the namespace cannot kill) or `sideeye`, and has the container exit 0 without the real
  tokens. The measured host has no Yama. This is ADR 0058's same-uid reach, and `measure_rc == 0`
  is claimed against kill, signal and file paths only.
- A stage sealed before this change still judges: nothing in the seal names the container layout.
  **Its controls do not carry over**: `measure.py` now holds `neg`/`pos`-`{build,measure}.{log,err}`
  as pre-run inputs, so a root whose controls ran under the one-container judge refuses to start a
  run until both controls are run again under this one.
- The `timew` the replay judges is the one in `/out` when the build container exits. It is copied
  there before the functional gate, and the gate runs the agent's binary as root, so the two need
  not be the same bytes — as under the one-container judge, where `/tmp/loop-bin/timew` was the
  gate's to rewrite too. The functional gate stays evidence about the binary it ran.
- Each eval leaves its own `<mode>-build-out-<tag>` and `<mode>-bin-<tag>` (a copy of `timew` in
  each) under `spike/runs/<root>/`; nothing removes them, because nothing in this judge deletes
  recursively.
- `<mode>-container-out/` is no longer written by `eval` (`secondary` still uses it); the run's
  directories are `<mode>-build-out-<tag>`, `<mode>-bin-<tag>` and `<mode>-measure-out-<tag>`.
- The judge's own selftest does not run `cmd_eval`; the lines that hand the two streams and the two
  statuses to `container_seals.py` are held by the real-docker runs above, and the functions they
  call by the module's selftest and four recorded mutations (`seal-reds/MUTATIONS.md`).
