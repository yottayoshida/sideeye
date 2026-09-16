# 2026-09-16 — results: cargo, re-met with the shipped v1.4.0 in both observation modes (#538)

Host: macOS on Apple Silicon, Docker 29.4.0, `linux/arm64`. **Sideeye is the released v1.4.0,
not a build**: `sideeye-v1.4.0-aarch64-linux.tar.gz` from the GitHub release, sha256
`709057371894565cbfc368cd2cc3402282f65f453520acb5cb4e9a2fb5b08820` matching the digest the
release publishes for the asset, untarred on the host and mounted read-only at `/se`. It reports
`sideeye 1.4.0 (trace contract v17)` (`transcripts/environment.txt`). The image is this run's
own (`apparatus/Dockerfile`, `rust:1.97.1-slim-bookworm` + strace 6.1, python3, procps):
**cargo 1.97.1 (c980f4866 2026-06-30), rustc 1.97.1** — not the 1.98.0 cohort 3 measured on
2026-08-22. `cgroup: not writable (default container)`, so v17's containment did not apply and
the run is judged as under v16 (ADR 0065). State and work on the container's own filesystem
(#528). Every quoted report line below is the report's own.

The define is cohort 3 r2's (`spike/cohort3/cargo-r2/ops/`), paths under `/localrun`:
`cargo add --offline --manifest-path …/state/Cargo.toml --path …/depcrate`, checker legs V/T/C
(manifest survival). `--oracle /usr/bin/strace` throughout. The predictions were written into
`BUILDLOG.md` (2026-09-16 (second)) and committed before this ran; the paragraph "Predictions
against measurement" below quotes them.

## Four configurations, two run

| | stand-in | `--observe` | runs | what the report said |
|---|---|---|---|---|
| preflight `--twice` | no | wrappers | 1 | `UNKNOWN  oracle_missed_operation` (rc 2) — refused at preflight, the same wall the explore hits |
| **A** | no | wrappers | 3 | `UNKNOWN  oracle_missed_operation`, 3 of 3, `divergence  renameat` — the manifest's rename |
| preflight `--twice` | no | syscalls | 1 | `PREFLIGHT  recording accepted — 7 state-changing operation(s) observed` (rc 0): two runs, equal |
| **B** | no | syscalls | 3 | **`FAIL  1 of 8 explored worlds violated an invariant`**, 3 of 3, the same world each time |
| C | r2's | wrappers | 0 | not run: A read `oracle_missed_operation` in all three, r2's wall, nothing to compare (`transcripts/C.not-run.txt`) |
| D | r2's | syscalls | 0 | not run: B reached a verdict in all three (`transcripts/D.not-run.txt`) |

## A: the first wall is gone, the second stands — under `--observe wrappers`

```
UNKNOWN  oracle_missed_operation
         the oracle saw a state-directory operation the shim did not record; divergence at operation 3: the oracle saw: 85    renameat(AT_FDCWD</w>, "/localrun/A/1/state/Cargo.tomlp00QNY", AT_FDCWD</w>, "/localrun/A/1/state/Cargo.toml") = 0
divergence  renameat
processes   2 other process(es) observed; none touched the state directory. … the shim recorded 9 thread(s) created, and 1 thread id(s) of the subject's own process wrote the judged directory
```

(`transcripts/A.1.txt`; A.2 and A.3 read the same.) The row's first wall — `child_process_detected`
on the `rustc -vV` child, which cohort 3 r1 hit and r2 lifted with the RUSTC stand-in — does not
appear: the two other processes touched nothing in the state directory, and the nine threads cargo
created have one writer, which v16 judges. Which two: `strace -f -e trace=execve` on the same
`cargo add` (`transcripts/probes.txt`) shows the rustup proxy exec'ing the toolchain's cargo in the
same pid (the report's "image replaced 1 time(s)") and one `execve` of `rustc -vV` in a child;
the second other process the oracle counted made no `execve` and was not identified.
**No stand-in was needed to reach the rename.** The second wall is r2's, verbatim in kind: the
manifest's atomic rename reaches the kernel as a `renameat` the interposed libc never sees. So the
row's "two named walls in sequence" is now one wall, reached by plain cargo.

## B: judged, and a counterexample — under `--observe syscalls`

```
FAIL  1 of 8 explored worlds violated an invariant

invariant   built-in atomicity (L0)
earliest    crash point 6 of 7
            after  truncate(/localrun/B/1/state/Cargo.lock)
            before write(/localrun/B/1/state/Cargo.lock)
path        Cargo.lock
observed    present, but its recorded history is no longer a prefix of its content
explored    8 worlds (crash points 7 + 1 baseline)
atomicity   2 path(s) judged pre-or-post; 2 file(s) judged by the history form (appended tails not judged): Cargo.lock, Cargo.toml
oracle      agreed on 7 operations (1114 syscall lines examined, 98 in scope of the judged state), witness strace of THIS run
checker     falsified before the run (corrupted state -> check failed); ran in 8 world(s)
processes   2 other process(es) observed; none touched the state directory. … the shim recorded 9 thread(s) created, and 1 thread id(s) of the subject's own process wrote the judged directory (v16: one per process is judged, two refuse); the subject's image replaced 1 time(s), chain unbroken (#123)
replay      sideeye replay /localrun/B/1/wk/cases/000001.json --shim /se/libsideeye_shim.so
```

(`transcripts/B.1.txt`; B.2 and B.3: the same verdict, the same earliest crash point, the same
window — `transcripts/B.{2,3}.json`.) With the trap set counting `renameat` (ADR 0059), the
recording is accepted, seven crash points are explored, and the oracle agrees on every operation.
**The counterexample is `Cargo.lock`, not `Cargo.toml`.** The manifest goes through
temp-file-plus-rename and survives every world. The lockfile is rewritten in place — `truncate`
then `write` — and the world killed between the two leaves a zero-length `Cargo.lock`: "its
recorded history is no longer a prefix of its content", the built-in L0 atomicity invariant.

**The declared checker passed in that world.** Leg V runs `cargo metadata` against the crashed
project and it exits 0. Measured on the state that world leaves, by emptying `Cargo.lock` by hand
(`transcripts/probes.txt`): `cargo metadata --offline` exits 0, prints `Locking 1 package to
latest compatible version` and `Adding depcrate v0.1.0` on stderr, and rewrites the lockfile —
**to the same 228 bytes**, because this define's one dependency is a local path resolved offline.
So in the measured world no resolution was lost, and what cargo prints is its ordinary resolving
line, not a word about the file having been empty. Where a lockfile pins registry versions the
rewrite can differ; that was not measured here and the record does not claim it. The r2 ruling
that left the torn-lock question "asked, not answered" now has both halves measured: the *empty*
window is this run's world; the *torn* window — a lock `cargo metadata` cannot parse — was made
without Sideeye, `ulimit -f 2` with 19 path dependencies (below), and the three commands tried
after it all fail on it.

## Predictions against measurement (the paragraph in `BUILDLOG.md`, committed first)

The prediction paragraph is the one in commit `00b4b74`; two of its sentences, verbatim, so that the
commit can be held to them: *"the oracle sees the manifest's `renameat` and the shim has no record of
it"* (A) and *"the trap counts `renameat`, so the run reaches a verdict"* (B).

- **A — held.** Predicted `oracle_missed_operation` with no `child_process_detected`; measured
  exactly that, three of three, and the `processes` line says why the child is no wall.
- **B — the verdict held, the mechanism did not.** Predicted FAIL through the declared checker's
  leg V on a torn `Cargo.lock`. Measured FAIL through the built-in L0 invariant at the lockfile's
  truncate, with the declared checker passing (cargo re-resolves the empty lock). The prediction
  named the right file and the right operation and the wrong judge; its "the pinned resolution is
  lost" was not measured and, in this offline define, is not what happens.
- **B's open way not to reach a verdict — did not appear.** The `posix_spawn` file-action shape
  (ADR 0063 decision 3) was given middling odds; `rustc -vV` ran, `2 other process(es) observed`,
  and the recording was accepted three of three. Whether cargo's spawn path avoids a writing
  `addopen` or never takes the `posix_spawn` route was not measured — only that nothing died of
  signal 31 here. The #556 shape was, as predicted, absent.
- **C, D — not run,** by the rule written before the run.

## What this record does not claim

- cargo 1.97.1 is not cohort 3's 1.98.0. The manifest rename's route (`renameat` past libc) is
  the same in both; nothing else about 1.98.0 is asserted here.
- A default container, no cgroup: v17's containment (ADR 0065) was not exercised.
- Not measured: Bun's `--observe syscalls` half (#217's row, the same "not re-measured" shape);
  a lockfile with registry dependencies, where re-resolving an empty lock could change versions;
  the identity of the second other process; whether the empty-lock window is reachable outside
  `cargo add`.
- The RUSTC stand-in was generated from the image's own `rustc -vV` (`apparatus/setup-standin.sh`)
  and was not used: C and D did not run. It is not declared as `[define] apparatus`; had it run,
  the report's apparatus line would have been empty, by the DESIGN §18 ruling that a stand-in
  belongs to setup.
- **Reported upstream as rust-lang/cargo#17481** (owner's call, 2026-09-16; the text as it stands is
  `report-cargo.md` — edited twice on the tracker after review, to say what cargo prints and to drop
  an unmeasured sentence about lost pins). Before filing, the window was reproduced without Sideeye
  (`transcripts/probes.txt`, parts 3 and 4, from `apparatus/probes.sh`): with 19 path dependencies
  (`Cargo.lock` 1212 bytes) and `sh -c 'ulimit -f 2; cargo add --offline --path ../dep20'`, `cargo add`
  dies of `SIGXFSZ` (exit 153) after the manifest is rewritten and while the lockfile is — `Cargo.lock`
  is 1024 bytes, cut inside a `[[package]]` entry — and `cargo metadata`, `cargo build` and `cargo tree`
  each exit 101 with `failed to parse lock file`. That is the *torn* half of cohort 3's question,
  answered; Sideeye's world is the *empty* half. Upstream `master` (`f325466`, 2026-09-16) carries the
  same `set_len(0)` / `write_all` block in `src/ops/lockfile.rs`, read before filing. The
  `class-exclusions.tsv` question is #598.

Raw output: `transcripts/` — `A.1.txt` `A.2.txt` `A.3.txt` and their `.json`, `B.1.txt` `B.2.txt`
`B.3.txt` and their `.json`, `preflight-twice.wrappers.txt`, `preflight-twice.syscalls.txt`,
`environment.txt`, `C.not-run.txt`, `D.not-run.txt`, `run.log` (the driver's own stdout: every
raw rc and the C/D decisions) and `probes.txt` (from `apparatus/probes.sh`: the `execve` trace,
the empty-lock reader, the torn lock under `ulimit -f 2`, and the three commands after it). The
driver is `apparatus/run.sh`. `report-cargo.md` is the upstream text as it stands after two edits.
