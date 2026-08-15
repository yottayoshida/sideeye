# buku — assisted run log (#118)

## Timeline (UTC, measured)

| T | Time | Δ from T0 | Event |
|---|------|-----------|-------|
| T0 | 13:54:03 | 0 | scout start (first repo/docs contact) |
| T1 | 13:57:55 | 3m52s | 3 proposals written, metadata attached |
| T2 | 13:59:05 | 5m02s | define done (toml + setup + checker) |
| — | 14:04:29 | 10m26s | final exploration (after 2 checker narrowings) |
| T4 | 14:05:32 | **11m29s** | saved case replay-confirmed in a fresh container |

## Funnel

- Scout: `--help`, DeepWiki Q&A, behavior probes. **DeepWiki was wrong about
  the pinned version** (described `BUKU_DEFAULT_DBDIR`; the pinned 4.7
  ignores it and honors `XDG_DATA_HOME` — measured). External
  repo-understanding answers must be re-measured against the pinned build.
- Proposals: 3 (P1 add — implemented; P2 delete — deferred; P3 lock/unlock
  — the richest cross-file window, EXCLUDED: interactive-only passphrase
  channel in the pinned build).
- Define iterations, all caught by the engine or the discipline:
  1. zero-op PASS — the operation child never saw `XDG_DATA_HOME` (setup
     exported it privately); the engine's zero-op message caught the
     exact "arbitrary command, trivial PASS" trap the metadata bar warns
     about. Fix: export in the engine's environment.
  2. strict run → **UNKNOWN `unsupported_syscall_observed: fchown`** —
     sqlite's journal-creation fchown (running as root) is outside the
     trace contract. Engine coverage gap, filed for follow-up: any
     sqlite-backed target explored as root will hit it.
  3. `--allow-unverified` run → FAIL 15/22, but the dominant failing leg
     was my own journal-hygiene assertion; narrowed once (empty journals),
     then DROPPED (a file-level check cannot distinguish a hot journal
     from a documented-cold invalid-header one). Claim discipline, not
     checker-weakening: the declared property was conservation, and the
     journal legs never represented it.

## Result (assisted; oracle NOT VERIFIED — the strict run is UNKNOWN/fchown)

**FAIL 2 of 22 crash worlds, violating the engine's BUILT-IN atomicity
invariant (L0), not the hand-written checker**: a crash between two
`write(bookmarks.db)` calls leaves the db holding neither the old nor the
new content, and in at least one world buku's own recovery-open reports
`initdb(): file is not a database` (committed: `target-error-line.txt`).
Case `cases/000001.json` — re-run from the committed ops dir after R1
found the first case embedding gitignored paths — **replay-confirmed in a
fresh container** (same crash point 18, same L0 violation, no target
build; transcript committed as `replay-transcript.txt`; the strict UNKNOWN
as `report-strict.json`). Claim strength: weaker by construction —
`--allow-unverified` means nothing checked the shim's completeness; a
verified version of this finding needs the engine's fchown gap closed
first.

Observation, recorded not asserted: in ~12 further worlds a non-empty
journal file survives buku's own recovery-open while the data stays intact.

## Human judgement (scored by the owner, 2026-08-15)

- P1 meaningful question? **Yes** (contract-grade: existing bookmarks
  surviving an add is what a bookmark keeper is for).
- Finding worth pursuing? **Judgment suspended** — harsher than "yes after
  the fchown fix": the strict run's fchown refusal means the shim's record
  may be incomplete in exactly the way that could FABRICATE this torn-db
  world. After fchown support, re-pose the question; do not treat the
  unverified FAIL as a finding awaiting confirmation.

## Correction (2026-08-15): the initdb() line was the falsification gate's, and buku recovers in every world

The Result section above claims "in at least one world buku's own
recovery-open reports `initdb(): file is not a database`". **That claim is
withdrawn.** The line is real and committed (`target-error-line.txt`), but
it was harvested from the wrong speaker: it is the **falsification gate's
output** — the pre-run step that deliberately corrupts the state and
requires the checker to go red — not any crash world's. Three measurements
close it:

1. **The transcripts themselves.** `checker(buku-add):` appears exactly
   once in `explore-remeasure-transcript.txt`, at the falsification-gate
   position: line 7, directly after the recording run's `url: /x` network
   line (line 6); the 21 `url: /x` lines that follow (lines 14–74) are
   the worlds', and none is accompanied by a checker failure. Both replay
   transcripts show the same shape: one gate line, no world-checker
   failure. The report field beside
   every one of these lines already said it plainly: "falsified before the
   run (corrupted state -> check failed)".
2. **The case's `violation: hybrid` is an L0 kind** (engine.zig `judgeL0`:
   content "holding neither the old nor the new content"), not a statement
   that the hand-written checker fired. Reading it as "L0 and the checker
   both failed" was the misreading that let the gate line stand as world
   evidence.
3. **An instrumented re-run** (`inspection/`, 2026-08-15): the committed
   define re-run with a checker that first dumps each visited world's file
   list, db header bytes, journal bytes and buku's raw answer to a log
   outside the state root, then applies the committed checker's logic
   verbatim. Engine 0.8.0/v9, same verdict (`FAIL`, earliest crash point
   18 of 21, 2 violations). The dump (`inspection/worlds.log`) shows: in
   **both** L0-violating worlds the torn `bookmarks.db` sits beside a
   fully-synced hot journal (magic `d9 d5 05 f9 20 a1 63 d7`), buku's own
   recovery-open answers the bystander query with rc=0, the bystander line
   is intact, and the journal is cleaned up — **the checker passed in all
   22 worlds**. `inspection/syscall-sequence.txt` (plain strace of the same
   add over the same pre-state) shows why this is structural, not lucky:
   sqlite's only neither-old-nor-new windows lie between the three db page
   writes, and every one of them is bracketed by the journal it just
   fdatasync'd. Harness: `inspection/inv.toml` + `inspection/check.sh`,
   run in the cohort image with this directory mounted at `/inv` and the
   repo at `/work`.

What remains of this target's result: the L0 hybrid in 2/22 worlds is a
correct byte-level observation, and it is exactly the state sqlite's
journal contract exists to recover — recovery now measured inside the
engine's own worlds, not only under plain `strace` kills (38/38 recoveries,
recorded in the upstream round). **buku yields no finding**: not "held
pending reproduction" but withdrawn, because the one leg it rested on was
never measured. The suspended judgment above resolves accordingly.

The mechanism that produced the error deserves naming: the falsification
gate's target output is interleaved unlabeled with world output in the
transcript, and a later reader harvested it as world evidence
(`target-error-line.txt` is that harvest). The claim then inflated
downstream — "at least one world" here became "2/22 worlds" in NOVELTY.md
and RESULTS.md by merging with L0's count.
