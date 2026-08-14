# stow — assisted run log (#118)

## Timeline (UTC, measured)

| T | Time | Δ from T0 | Event |
|---|------|-----------|-------|
| T0 | 14:12:35 | 0 | scout start (--help + fold/unfold probes) |
| T2 | 14:14:04 | 1m29s | define done (fold scenario measured; whole-tree determinism confirmed after a first false NO from a subtree-only diff). **The proposal ARTIFACT was formalized after the verdict — R1 finding 2; metadata lived in toml/checker comments at define time** |
| T3 | 14:14:05 | **1m30s** | exploration verdict: UNKNOWN |

## Result

**UNKNOWN `unsupported_syscall_observed: symlinkat`** — stow (perl) creates
its links through symlinkat, which is outside the engine's trace contract;
the run is honestly refused. The second engine coverage gap this experiment
has surfaced (fchown at buku, symlinkat here): symlink-farm managers are
currently out of the engine's reach as a class.

The define is written but UNMEASURED — the run went UNKNOWN before the
falsification gate, so the checker's red side has never been exercised
(R1). The fold/unfold scenario (target
`sub` folded onto package A; stowing B forces delete-symlink → mkdir →
re-point A → add B) with a pure file-inspection checker — the target never
even runs in the checker, because the filesystem IS the state.

## Human judgement (scored by the owner, 2026-08-15)

- P1 meaningful question? **Yes** — and on the second axis, high drivable
  value once the engine can reach it: the unfold is genuinely multi-step
  (delete link, mkdir, N re-links), not an atomic rename.
- symlinkat support worth an engine issue? **Yes**.
