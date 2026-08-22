# cargo (cohort 3, target 1) — run log and ruling

## Timeline (all 2026-08-22, each step's evidence committed where named)

1. **r1** — the define merged, then its explore refused:
   `UNKNOWN child_process_detected (clone3)`, reproduced on a second run
   (`../cargo/explore-r1-transcript.txt`,
   `../cargo/explore-r1-repro-transcript.txt`). The boundary is the
   probe's disclosed forecast: every `cargo add` vforks one `rustc -vV`
   child whose internal thread arrives through a raw `clone3` carrying
   `CLONE_THREAD` — refused for the subject's determinism.
2. **r2** — the owner-approved RUSTC stand-in (cargo's documented
   configuration; `proposals.md` here) removed that boundary — the
   report reads `single process` — and the explore then refused one
   layer deeper: `UNKNOWN oracle_missed_operation`
   (`explore-transcript.txt`, `report.json`), reproduced on a second
   run (rc 2, same reason). The oracle saw the manifest's atomic
   rename — `renameat(".../Cargo.tomlI2K6rq" → ".../Cargo.toml")` —
   and the shim, loaded and recording either side of it, had no such
   record.
3. **Diagnosis** (`raw-rename-diagnosis.txt`): cargo *imports* libc
   `rename@GLIBC_2.17`, so the import table alone decides nothing. A
   minimal LD_PRELOAD logger interposing `rename` and `renameat`, with
   a positive control (python's `os.rename`, libc-routed, fires the
   logger), stays **silent** through `cargo add` while strace sees the
   `renameat` reach the kernel: **the manifest rename is a raw
   syscall**, past every function an LD_PRELOAD shim can interpose.

## The ruling: a named wall, terminal for this cohort

The operation this define exists to crash — the manifest rewrite — is
performed through a raw syscall the shim structurally cannot observe.
The engine's two-witness design did exactly what it is for: the oracle
saw what the shim could not, and the run refused rather than judging
blind. No configuration or declared apparatus reaches this (the rename
lives inside cargo's vendored file-handling; the RUSTC stand-in lifted
the child-thread boundary and revealed this one). Observing raw
syscalls is a different observer — ptrace-grade — which is engine
architecture, the same after-1.0 family as static linking (#201) and
threads (#202). The measured binary is the current upstream stable
(1.98.0), so the recheck is inherent. cargo's slot closes; the cohort
order continues with black.

## Observations recorded, not reported (the standing gates are unchanged)

- cargo protects `Cargo.toml` with temp-file-plus-rename but rewrites
  `Cargo.lock` **in place** (probe strace, `../probes/cargo.txt` raw
  log; re-measured in the define work).
- A lockfile torn mid-entry fails every subsequent cargo command with
  `failed to parse lock file` and no recovery hint, while an absent
  lockfile is silently regenerated (engine-free container
  measurements, recorded in `../cargo/proposals.md` and drilled in
  both revisions' `checker-drills.txt`).
- Under the frozen torn-lock ruling these would have been the
  checker-red question; the engine cannot currently address kill
  points inside this target, so the question stays measured only at
  its edges — asked, not answered.
