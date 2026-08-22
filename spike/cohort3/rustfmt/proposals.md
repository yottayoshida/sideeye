# Cohort-3 define: rustfmt (target 3)

Target: rustfmt 1.9.0-stable (the 1.98.0 toolchain's component, the
image's pinned current stable). Probe: conditions 1–6 machine-green
with condition 7's ambient evidence printed, `../probes/rustfmt.txt` —
byte-deterministic, closure clean, **zero threads, zero children** (the
committed raw log: no clone/fork/vfork, and the rewrite is one
`openat(O_WRONLY|O_CREAT|O_TRUNC)` plus one 97-byte `write`,
`../probes/raw/rustfmt.strace` lines 51-52). Scout sources: the probe
transcript and rust-lang/rustfmt's tracker. Assisted provenance.

## Why this define exists, said before anything runs

**The expected find is already public on the target's own tracker.**
rust-lang/rustfmt#6041 ("Gracefully handle full disk instead of
erasing file contents", open) names the same destruction surface —
the in-place write erasing the file — under the disk-full trigger; and
psf/black#2479's thread (2026-07-01 comment) publicly lists rustfmt
among the formatters that "just write directly with no fallback". The
recorded pre-define search (2026-08-22, `gh api search/issues`,
positive control "comment" = 1094 hits): "atomic" 12 / "corrupt" 14 /
"data loss" 1 / "truncated" 1 — none about crash destruction — and the
targeted "disk full" search surfaced #6041. **A FAIL here cannot serve
criterion 1**, and no upstream filing will come of it. The define
exists by owner decision (2026-08-22) for the cohort ledger's
completeness and as the cross-language companion to black's verdict:
the same defect class, found the same way, in a Rust target.

## The property (P1)

**Kill `rustfmt probe.rs` anywhere; the source must survive as a
program.** After the crash:

- **guard**: `probe.rs` exists;
- **leg V**: the file still compiles as the program it is — `rustc
  --edition 2021 --crate-type bin --emit=metadata` accepts it (the
  language's own front end as the survival oracle; bin because the
  fixture is a `fn main` program);
- **leg E**: the bytes are exactly the frozen pre-operation source or
  exactly the formatted output the probe measured — the two known-good
  states, both committed before this define existed
  (`../probes/rustfmt.txt`, "the formatted bytes, as measured").

## The torn-file reading, declared before the explore

The write shape (one truncating open, one write) makes the reachable
tear the **empty file** — and unlike black's case, an empty file fails
**leg V** here: a bin crate without `fn main` does not compile (E0601).
The full prefix sweep (R1, all 97 strict prefixes through the exact
leg-V invocation): every prefix below 96 bytes fails leg V — the sole
`{` at byte 10 closes only at the final `}`, so partial writes are
unclosed-delimiter or missing-body — and **exactly one strict prefix
compiles: the 96-byte one, the full content minus its final newline**,
which fails **leg E** (neither anchor) while being the same program one
newline short. That sole shape is a red stricter than the property's
plain-language form — named here so a future world landing on it is
read against a declaration that predicted it, not excused after the
fact. It is also engine-unreachable for this fixture (the write is one
97-byte syscall; the engine kills between syscalls). Checker-red in
every torn shape; the expected earliest case is the combined "built-in
atomicity, and the checker" form at the kill point between the open
and the write. No recovery leg: rustfmt documents no crash recovery and the
source is the primary data (the cargo ruling's principle; no self-heal
exists).

## Rejected shapes

- *AST-equivalence for leg E* (black's form) — Rust has no stdlib
  parser to compare ASTs cheaply; the two-anchor byte form is stricter,
  simpler, and both anchors are committed measurements.
- *`rustfmt --check` as the oracle* — the old bytes legitimately fail
  it (they are unformatted); survival, not formattedness, is the
  property.

## Stock reproduction

Unchanged cohort rule — though with the novelty gate already closed,
no claim or report path exists for this target at all.
