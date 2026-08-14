# pass — assisted run log (#118)

## Timeline (UTC, measured)

| T | Time | Δ from T0 | Event |
|---|------|-----------|-------|
| T0 | 14:07:06 | 0 | scout start |
| T2 | 14:09:11 | 2m05s | proposals + define done (probes confirmed non-interactive keygen/insert, mv determinism, exact show anchor) |
| T3 | 14:09:12 | **2m06s** | exploration verdict: UNKNOWN |

## Result

**UNKNOWN `child_process_detected`** — pass is a shell script that execs
`mv`/`mkdir`/`rmdir`/`gpg` as child processes; the engine's crash-point
addresses do not survive an image change, so the run is honestly refused
(exit 2, "not a pass"). Atomicity pre-judged 5 files before the refusal.

Funnel stall point: explore. The define itself is sound (probes: same-id
`pass mv` over the same pre-state is tree-byte-identical; fixed secrets
round-trip through `insert -e`/`show` exactly).

## What this datum means for #118

An entire target class — shell-script CLIs driving coreutils (pass, and by
the same construction todo.txt-cli, nb, …) — is outside the engine's
current single-process crash model. The scout can produce a meaningful,
metadata-carrying question in two minutes; the judge cannot yet execute it
hostilely. That is a product-surface gap on the SIDEEYE side, found by the
assisted loop, and precisely the kind of thing this experiment exists to
surface.

P3 note (also engine-relevant): the richest window (cross-gpg-id move's
decrypt/re-encrypt temp dance) is refusal-shaped for a second reason —
randomized encryption defeats the byte-reproducible baseline.

## Human judgement (yotta, post-run)

- P1 meaningful question? ☐
- Multi-process support worth an engine issue? ☐
