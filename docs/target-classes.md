# Which tools Sideeye can judge

The README's constraint list says what a target must do; this page says how real tools have fared against it — every row backed by a run recorded in this repository, with the artifact named. Nothing here is a projection: a class with no recorded run says so. This page is also where the v1.0 UNKNOWN-rate criterion gets its word "supported" (`PRD.md`): supported means a class listed here as reaching verdicts.

Two vocabulary notes. A **verdict** is PASS or FAIL; everything else is a named refusal (UNKNOWN), never a silent pass. And a FAIL is a crash-consistency counterexample — a state the tool itself can be left in — not automatically an upstream bug: one recorded FAIL below stands withdrawn as a bug claim because the store's own recovery contract covers it.

To be precise about "supported", since the v1.0 criterion hangs off it: **supported classes are exactly the rows of the first table below** (Measured, with verdicts). The refusal tables and the Rust narrative are not supported classes, whatever verdicts their stories contain. The UNKNOWN rate over supported-class targets — measured on a corpus frozen before it ran, with the threshold set from the data — is published in [docs/unknown-rate.md](unknown-rate.md).

*Backfill note (2026-08-22): the six cohort-2 and cohort-3 verdict rows below,
and the refusal rows beneath them, were added together after both cohorts
closed. `docs/unknown-rate.md`'s A-group sweep predates them — see the
as-of note there.*

## Measured, with verdicts

| Class | Tool | What happened | Recorded in |
|---|---|---|---|
| C/C++ CLI | timewarrior | **FAIL** — `timew undo` can destroy committed data across a crash window; reported upstream as GothenburgBitFactory/timewarrior#778, and the patched build passes 25/25 | recipe `spike/dogfood-timew.sh`, replay legs `spike/dogfood-timew-replay.sh` (run on every push to main and every pull request by the timew-regression job in `.github/workflows/ci.yml`), patch `spike/timew-undo-ordering.patch`, apparatus `spike/loop-closure-timew/`, the 25/25 patched-build measurement in `BUILDLOG.md` |
| C/C++ CLI | taskwarrior | **PASS** 12/12 explored worlds (11 crash points + the baseline), oracle agreed on 11 operations; the falsification probe rejected deliberately corrupted state | `BUILDLOG.md`, the taskwarrior entry (2026-08-13) |
| C CLI | calcurse | **FAIL** 1/11, replay-confirmed; reported upstream as lfos/calcurse#529 | `spike/assisted/RESULTS.md`, artifacts under `spike/assisted/calcurse/` |
| C++ CLI | devtodo | **FAIL** 6/8 once ownership/permission writes became recorded-only (v0.8.0); the finding is kept here, deliberately unreported upstream | `spike/assisted/REMEASURE.md`, artifacts under `spike/assisted/devtodo/`; the report-then-withdrawal record and its selection rule are in `spike/assisted/NOVELTY.md` and `spike/assisted/PROTOCOL.md` |
| C CLI | abook | **null** — three declared operations, zero violations in the declared window (blind campaign 2) | `spike/blind-hunt2/`, `BUILDLOG.md` |
| Python CLI | todoman | **PASS** 8/8 explored worlds (7 crash points + the baseline), oracle agreed on 7 operations — the first Python target with a full verdict | `spike/dogfood-todoman.sh`, `BUILDLOG.md` |
| Python CLI | topydo | 12 of 13 crash points yielded **counterexamples** (blind campaign 1); reported upstream as topydo/topydo#341 | `spike/README.md`, artifacts under `spike/blind-hunt/` |
| Python CLI | khal | **null** — 41 crash worlds + 3 baselines, all PASS (blind campaign 3) | `spike/blind-hunt3/analysis/` |
| Python + sqlite | buku | strict **FAIL** 2/22 under the built-in byte comparison — and withdrawn as a bug claim: a journaled database's mid-transaction byte state is exactly what its journal recovers from, and buku recovers in every measured world. The class lesson: judging a journaled store by file bytes is stricter than its contract — confirmed a second time on bogofilter-sqlite (the #84 sweep's fresh FAIL, triaged with the tool's own reader as checker: recovery held in every world, `spike/followup-144/`) | `spike/assisted/REMEASURE.md`, `spike/assisted/buku/RUNLOG.md` (Correction section) |
| Perl CLI | GNU Stow | **FAIL** 2/5 once symlinks became first-class kill points (v0.8.0); reported upstream as aspiers/stow#139 | `spike/assisted/REMEASURE.md`, artifacts under `spike/assisted/stow/` |

| DVCS with its own transaction engine | Mercurial | **FAIL** 73/107 worlds — and every violation L0-only, with hg's documented contract holding in all 107 (`hg recover` succeeded in all 62 worlds that needed it). A precision-limit observation under the cohort's frozen claim rule, claimed as nothing | `spike/cohort2/hg-r4/RUNLOG.md`, `spike/cohort2/RESULTS.md` |
| Deduplicating backup with a repository format | Borg | **FAIL** 3/119 — all three L0-only and all three in the relocated client cache's in-place rewrite, while Borg's transactional contract held in all 119 worlds. Measured under declared clock and entropy pins; a precision-limit observation, claimed as nothing | `spike/cohort2/borg-r3/RUNLOG.md`, `spike/cohort2/RESULTS.md` |
| Python in-place formatter | black | **FAIL** 1/3 worlds, crash point 2 — after the truncating `open`, before the single `write`: the empty file. `oracle_verified`, reproduced identically three times. Not novel: `psf/black#2479` reports the same surface (open since 2021, fix PR `psf/black#5207`), so no criterion-1 claim and nothing filed | `spike/cohort3/black/RUNLOG.md` |
| Rust in-place formatter | rustfmt | **FAIL** 1/3, crash point 2 — the same shape in a second language, combined invariant (rustc E0601 on the empty bin crate), `oracle_verified`, reproduced twice. Measured with the novelty gate already closed before the define existed (`rust-lang/rustfmt#6041`, open since 2024-01-24); no claim, nothing filed | `spike/cohort3/rustfmt/RUNLOG.md` |
| Python manifest + lock manager | poetry | **FAIL** 2/5, reproduced across three runs. Not a criterion-1 candidate: the earliest violating world is L0-only and the checker heals it, so the frozen claim rule refuses — while the checker-red world behind it (crash point 4 destroys a user-authored `pyproject.toml`) is real and was reported upstream as `python-poetry/poetry#11019`. A revision measuring the manifest-only operation reproduced the same wound under the FAIL-freeze rule, recorded and never claimed | `spike/cohort3/poetry/RUNLOG.md`, `spike/cohort3/poetry-r2/RUNLOG.md` |
| Python personal-library store | papis | **PASS** 2/2 (one crash point plus the baseline), `oracle_verified`, single process, reproduced twice. `papis add` builds the document outside the library and moves it in with one `renameat`, so the only crash world the engine can produce is the library before the move — the cohort's contrast case | `spike/cohort3/papis/RUNLOG.md` |

## Refusals that are the correct answer

| Class | Tool | The named wall | Recorded in |
|---|---|---|---|
| Nondeterministic writers | watson | `baseline_violates_invariant` — every run rewrites fresh uuids, so no invariant survives even a clean run; refusing is the honest verdict | `spike/dogfood-watson/`, `BUILDLOG.md` |
| Shell CLIs over helper processes | pass | `child_touched_state_dir` — the dangerous slice runs in fork+exec children; judging it needs the multi-process slice (#123, open) | `spike/assisted/pass/explore-v10-transcript.txt` |
| Tools with non-durable scratch files | git | the built-in atomicity form flags `COMMIT_EDITMSG`, a scratch file — a recorded precision limit (#35, open) | `BUILDLOG.md` |

| Statically linked release binaries | Jujutsu | `no_shim_marker` at recording — the v0.44.0 release binary is statically linked and cannot load an `LD_PRELOAD` shim. The measured binary is the latest stable, so the recheck is inherent (#201, after v1.0) | `spike/cohort2/jj/RUNLOG.md` |
| Multi-threaded runtimes | Bun | `multiple_threads_detected` at recording — the probe's six threads. Single-threaded exploration is a v0.1 contract property; the measured binary is the latest stable, 1.4.0 (#202, after v1.0) | `spike/cohort2/bun/RUNLOG.md` |
| Tools whose state writes bypass libc | cargo | two named walls in sequence: `child_process_detected` on the `rustc -vV` child's internal thread, and then — with an owner-approved stand-in lifting that boundary — `oracle_missed_operation`, because the manifest's atomic rename is a raw syscall past every function an `LD_PRELOAD` shim can interpose, measured with an interposing logger against a libc-routed positive control (#217, after v1.0) | `spike/cohort3/cargo-r2/RUNLOG.md`, `spike/cohort3/cargo-r2/raw-rename-diagnosis.txt` |

## Walls found before the engine ran

Not engine refusals: these targets never reached a define, because the
engine-free probe gate refused first. The distinction matters — nothing
below is a statement about what the judge would have said.

| Class | Tool | The probe's refusal | Recorded in |
|---|---|---|---|
| Encrypted, memory-locked stores | KeePassXC 2.7.10 | conditions 5 and 6 of the probe gate: two `keepassxc-cli add` runs two seconds apart produce different `db.kdbx` bytes, and 7 successful mutating calls could not be attributed to a path (fail-closed). Latest stable rechecked at 2.7.12 | `spike/cohort2/probes/keepassxc.txt`, `spike/cohort2/probes/recheck-keepassxc.txt` |

## Walls, measured on toys

- **State-changing raw syscalls** (writes bypassing libc): UNKNOWN `oracle_missed_operation` with an oracle, `state_changed_without_ops` without one — pinned by `spike/toys/toy_raw.c` in `spike/acceptance.sh`. Read-only raw opens are tolerated: they never join the crash-point numbering, which is what let a rustix-carrying Rust target through (next section).
- **Static binaries**: no shim can load — `no_shim_marker`, measured on a statically linked C toy (`spike/build-toys.sh`). Go's default static linking lands here; that is a statement about linking, not a measured Go run.
- **Threads**: a clone carrying CLONE_THREAD refuses (`multiple_threads_detected`) — there is no per-thread order the kill can address deterministically. Pinned on the threaded toy in `spike/acceptance.sh`.
- **macOS platform binaries**: on macOS the target must be a binary you built or installed yourself, never an Apple-shipped one — SIP strips the injected library from Apple platform binaries, and the platform identity travels with the code signature, so copying the binary elsewhere does not change it. The measured record is in `BUILDLOG.md`, and *how* the refusal arrives is OS-dependent (measured 2026-08-18): macOS 15 strips the insertion silently — the run completes and answers `no_shim_marker` — while macOS 26's dyld terminates the target over the arm64/arm64e mismatch and the run answers `recording_run_failed`; exit 2 either way, never a verdict (that copying cannot help follows from the signature mechanism, not from a committed measurement). Since 2026-08-18 the report's macOS build names an Apple-shipped platform binary as one possible cause on the `no_shim_marker` line — never the cause, the marker proves only that the shim never initialised — and the macOS CI job pins the refusal shape (#10, landed).

## The Rust story, in order

The first Rust target (omamori) surfaced three walls in sequence: `child_process_detected`, an unsupported `flock`, then `oracle_missed_operation` on a read-only `openat` issued by the rustix crate — the whole class looked UNKNOWN and was filed as #19. The fix scoped crash-point numbering to state-changing operations (`docs/adr/0003-what-counts-as-a-crash-point.md`); one wall remained — `baseline_violates_invariant` over the target's nondeterministic audit lines — until the L0 history form (#24, #25 — both closed) produced **PASS 143/143**. The 2026-08-12 record had its unguarded install/setup/init surfaces refusing at `symlinkat`/`fchmodat`; the 2026-08-16 re-measurement (#141, contract v10, omamori 1.0.4) shows those walls gone — all four unguarded writers explore fully and PASS, with the chmod writes observed and excluded per #121 (`spike/dogfood-omamori-surface.sh` pins the outcomes). A Rust tool whose *writes* bypass libc still refuses (the raw-syscall wall above).

Two real Rust targets followed in cohort 3, and they land on opposite
sides. **rustfmt** is the class's first clean Rust verdict — dynamically
linked, single-threaded, FAIL in three worlds and minutes. **cargo** is
the harder half: not a linkage or thread wall but a routing one, its
manifest rename issued as a raw syscall while the binary imports libc
`rename`, which is why an import table cannot decide the question and an
interposing logger can (#217).

## Not yet measured

- **Node/libuv tools**: still no recorded run — Bun, refused on threads in cohort 2, is not Node and does not use libuv, so it is a neighbour rather than an instance. The expected wall is the thread refusal (libuv starts a worker pool), which is measured on toys — but no real Node target run exists in this repository, so this row is a prediction, labeled as one.
- **libc functions that mutate state through internal calls** (the mkstemp family, mkdtemp, tmpfile, dprintf — #39): no recorded run for any of these members. The *mechanism* is not a projection — two class members are measured: stdio's internal writes (ADR 0005, probed on both platforms; the macOS probe showed dyld interposition equally blind to libSystem-internal calls) and remove(3), measured on Linux through the timewarrior work (PR #38). On Linux the class fails closed, in the same shape the raw-syscall wall pins above: the oracle sees the internal syscalls, the accounts diverge, the run refuses. On macOS there is no oracle, so for the unmeasured members the consequence is inferred from that mechanism, not measured: an internal mutation is invisible to the shim with nothing to catch it, and a macOS PASS carries only the weaker `--allow-unverified` claim the README spells out. The interpose-on-first-contact policy stands, and #39 stays open as the family's lookout post: a member gets reimplemented through the recorded wrappers when a real target first demonstrates it.

---

The artifacts this page names are load-bearing references: `spike/README.md` explains why the dogfood scripts stay in-tree, and the acceptance suite checks that every slashed backtick reference on this page still resolves in the repository (bare file names like the buildlog are outside that sweep).
