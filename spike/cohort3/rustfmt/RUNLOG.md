# rustfmt (cohort 3, target 3) — run log and ruling

## Timeline (all 2026-08-22)

1. The define merged (main `9faf204`) with its novelty gate **already
   closed before it existed**: rust-lang/rustfmt#6041 (open,
   2024-01-24) names the in-place erasure surface, the recorded
   pre-define search sits in `proposals.md`, and the owner decided the
   target would be measured anyway — for the ledger's completeness and
   as black's cross-language companion.
2. **The explore returned FAIL** — 1 of 3 worlds, single process,
   `oracle_verified: true` — and a second run reproduced it
   identically (same verdict, same crash point, same invariant). The
   committed `explore-transcript.txt`, `report.json` and
   `cases/000001.json` are run 1's consistent set.

## The verdict

**FAIL, 1 of 3 worlds; the earliest (and only) violating world is
crash point 2 of 2 — after the truncating `open(probe.rs)`, before the
single `write(probe.rs)`: the empty file, exactly the declared
engine-reachable tear.** The violated invariant is the combined
**"built-in atomicity, and the checker"**: L0 sees a file holding
neither the old nor the new content, and the checker's leg V sees a
bin crate rustc rejects — E0601, no `fn main` in an empty file — the
`V-red-empty-file` drill's rehearsed world. In user terms: kill
`rustfmt file.rs` between its truncating open and its write, and the
source file is destroyed.

## The reading (fixed before the define existed)

A candidate shape by the frozen claim rule — and **closed at the
novelty gate that was checked before the define was written**: the
phenomenon is public on the target's own tracker (#6041, the disk-full
trigger of the same non-atomic write), and psf/black#2479's thread
lists rustfmt among the formatters that write directly. No criterion-1
claim; nothing filed upstream; the standing per-report owner gate is
untouched.

## What the verdict adds

The cross-language proof point the owner asked for: **the same defect
class, found by the same frozen discipline, in a Rust target — three
worlds, minutes** — beside black's identical verdict in Python. Two
formatters, two languages, one non-atomic in-place write, one engine
finding both at their current stables. The formatter half of the
cohort's matrix is now fully measured; the criterion-1 search
continues with poetry and papis, whose pre-scans found no named
crash-destruction surface on their trackers.
