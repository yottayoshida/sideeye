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
`initdb(): file is not a database` (committed: `target-error-line.txt`)
*(withdrawn 2026-08-15 — that line was the falsification gate's; see the
Correction section below)*.
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
it belongs to the **falsification gate** — the pre-run step that
deliberately corrupts the state and requires the checker to go red — not
to any crash world. The proof rests on the committed remeasure transcript
alone; an instrumented re-run corroborates it.

1. **The committed transcript allows exactly one checker failure, and it
   must be the gate's.** `ops/check.sh` prints through exactly one path —
   `fail()` — so every checker failure emits one `checker(buku-add):`
   line. `explore-remeasure-transcript.txt` contains exactly one, at
   line 7. The gate must fail or the run ends UNKNOWN
   `checker_not_falsified` (src/main.zig), and the report's "checker ...
   ran in 22 world(s)" counts exploration-phase runs only — so the one
   failure is the gate's, and zero of the 22 world checkers failed in the
   very run the finding cites. Position agrees: line 7 sits directly
   after the recording run's `url: /x` network line (line 6) and before
   the worlds'. Both replay transcripts have the same shape: one gate
   line, no world-checker failure. World accounting, for a reader
   checking "explored 22 worlds" against the 21 post-gate `url: /x`
   lines (14–74): world k=1 is killed at the db `openat`, which precedes
   buku's title fetch, so its run emits no network line — it is the
   unpaired DeprecationWarning at lines 10–11.
2. **The case's `violation: hybrid` is an L0 kind** (engine.zig `judgeL0`:
   content "holding neither the old nor the new content"), not a statement
   that the hand-written checker fired. Reading it as "L0 and the checker
   both failed" was the misreading that let the gate line stand as world
   evidence.
3. **An instrumented re-run corroborates** (`inspection/`; launcher
   `inspection/run.sh`, environment as `ops/explore.sh`): the committed
   define with a checker carrying the committed verdict legs in the
   committed order plus two read-only additions (a world dump and a
   query-answer log). Engine `sideeye 0.8.0 (trace contract v9)` — the
   same v9 code as the remeasure, whose artifacts predate the same-day
   version-bump commit and therefore carry the 0.7.0 banner. Same
   verdict, committed: `inspection/explore-transcript.txt` (FAIL,
   earliest crash point 18 of 21, 2 violations; the engine prints its
   report to stdout, so the transcript is the report —
   `workdir-listing.txt` records that no report file exists to harvest)
   and `inspection/case-000001.json` (k=18, `violation: hybrid`, v9).
   The re-run passes no `--oracle`, so its report reads "oracle not
   run" where the remeasure's read "agreed on 21 operations" — the
   recording's completeness was the remeasure's question, already
   verified there, not this run's. The bridge between the two runs is
   mechanical, not just the matching summary: the saved case's
   `prefix_hash` is byte-identical to `cases-remeasure/000001.json`'s
   (`f463071719a47e91`), the same recorded trace prefix (R2's
   observation).
   The dump (`inspection/worlds.log`): visit 1 is the gate over the
   engine's 25-byte corruption probe — a positive control producing
   exactly the disputed line — and visits 2–23 are 22 consecutive
   PASSes. Visit mapping, derived rather than assumed (the engine passes
   the checker no world number): visit = k+1 with the baseline last,
   pinned by the journal-size progression (0, 512, 516, 4612, …, 12824)
   matching the pwrite offsets in `syscall-sequence.txt`, the journal
   magic turning hot (`d9 d5 05 f9 20 a1 63 d7`) at visit 17, and the db
   change counter flipping 2→3 at visit 19. Both L0-violating worlds
   (crash points 18 and 19 = visits 19 and 20) hold that fully-synced
   hot journal beside the torn db, and buku's own recovery-open answers
   the bystander query with rc=0 and cleans the journal up.
   `inspection/syscall-sequence.txt` (plain strace of the same add over
   the same pre-state) shows why this is structural, not lucky: sqlite's
   only neither-old-nor-new windows lie between the three db page
   writes, and every one of them is bracketed by the journal it just
   fdatasync'd.

What remains of this target's result: the L0 hybrid in 2/22 worlds is a
correct byte-level observation, and it is exactly the state sqlite's
journal contract exists to recover — recovery now measured inside the
engine's own worlds, not only under plain `strace` kills (38/38
recoveries, recorded in the upstream round). **buku yields no finding**:
not "held pending reproduction" but withdrawn, because the one leg it
rested on was never measured. The suspended judgment above resolves
accordingly.

On the harvest itself: the first cohort's explore transcript was never
committed (only the remeasure's and the replays'), so "the line was the
gate's" is, for that first run, an inference rather than a line read off
a page — grounded in the gate being the engine's only corrupt-state
site, the one-printer argument applying to the same checker, and the
instrumented gate reproducing the identical line as a positive control.
The claim then inflated downstream: "at least one world" here became
"2/22 worlds" in NOVELTY.md and RESULTS.md by merging with L0's
violation count. The mechanism deserves naming: the falsification gate's
target output is interleaved unlabeled with world output in the
transcript, and a later reader harvested it as world evidence
(`target-error-line.txt` is that harvest).
