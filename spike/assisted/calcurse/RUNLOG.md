# calcurse — assisted run log (#118)

## Timeline (UTC, measured)

| T | Time | Δ from T0 | Event |
|---|------|-----------|-------|
| T0 | 14:09:47 | 0 | scout start (--help; no external service needed) |
| T2 | 14:11:12 | 1m25s | proposals + define done (probe: purge byte-deterministic over the same pre-state; exact apts/query anchors) |
| T3 | 14:11:12 | 1m25s | exploration verdict: FAIL, strict oracle agreed |
| T4 | 14:11:36 | **1m49s** | saved case replay-confirmed |

## Result (oracle agreed on all 10 operations — scope caveat below)

**FAIL 1 of 11 crash worlds, violating both the engine's built-in atomicity
AND the declared checker**: `-P --purge` ("Read items and write them back",
the help text's own words) truncates `apts` in place — the crash between
`open(apts)` and `write(apts)` leaves the file holding neither the old nor
the new content, and the bystander event GraceStandup is gone (checker: 0
anchored lines) even though the purge targeted only AdaMeeting. Case
`cases/000001.json`, replay-confirmed (same crash point 10, same
violation). Single process; 164 syscall lines examined, 45 touching the
state directory.

This is the topydo class from campaign 1 — an in-place rewrite whose
interruption destroys data the operation never named — found here by the
assisted loop in under two minutes, with the strict oracle on.

## Funnel notes

- Scout was --help + empirical probes only; no repo-understanding service
  was needed for this target (the help text itself names the window:
  "Read items and write them back").
- `-D`/`-C` flags meant no environment plumbing at all (the buku lesson did
  not recur).
- **Scope caveat (R1 finding 6)**: the config dir is ambient (outside the
  state root) and the target writes there too — the oracle's account and
  any "verified" wording cover the declared data subtree, not every byte
  the process touches. The declared property concerns the data files by
  design; the caveat is about how far "verified" reaches.

## Human judgement (yotta, post-run)

- P1 meaningful question? ☐
- Upstream-worthy finding? (novelty unchecked — no tracker search yet) ☐
