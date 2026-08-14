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

## Human judgement (yotta, post-run)

- P1 meaningful question? ☐
- Finding worth pursuing (after the fchown fix)? ☐
