# Cohort 2 — probe outcomes (2026-08-21)

Engine-free probes per PROTOCOL.md's frozen plans, run in cohort order
inside the `sideeye-cohort2` image (versions in each transcript). The
positive control ran first and split, so the harness is known to flag
nondeterminism (`probes/positive-control.txt`). Raw transcripts are the
record; this page is the index and the ruling.

## Outcomes

| # | Target | Probe verdict | Transcript |
|---|--------|---------------|------------|
| 1 | BorgBackup 1.4.0 | **named wall: determinism** — conditions 1–4 pass; two pinned `borg create` runs 2s apart differ in `data/*` segments, `index.5`, `integrity.5` | `probes/borg.txt` |
| 2 | Mercurial 7.2.4 | **pass, all seven** — whole-`.hg` root byte-identical across runs; closure clean (every persistent write inside `.hg`); commit-path thread removed by documented config (control shown) | `probes/hg.txt` |
| 3 | Jujutsu 0.44.0 | **pass, all seven, after two measured corrections** — v1: frozen `.jj` root failed closure (colocated `./.git` writes); v2: repo-wide root split on the reflog's wall-clock line; final: `core.logAllRefUpdates=false` pre-state, byte-identical repo | `probes/jj-v1.txt`, `probes/jj-v2.txt`, `probes/jj.txt` |
| 4 | KeePassXC 2.7.10 | **named wall: determinism (pre-declared)** — conditions 1–4 pass; two `keepassxc-cli add` runs produce different `db.kdbx` bytes | `probes/keepassxc.txt` |
| 5 | Bun 1.4.0 | **pass, all seven** — local-tarball `bun add` byte-identical across runs; succeeds under `--network=none` (the observed DNS/443 contact is optional) | `probes/bun.txt`, `probes/bun-network-independence.txt` |

## Wall rechecks (latest upstream stable, per PROTOCOL "Versions")

- **Borg**: the wall's mechanism — `time_end = timestamp + monotonic
  duration`, stored in archive metadata — is present verbatim in the
  latest stable's source (1.4.5, released 2026-07-18,
  `src/borg/archive.py`; read in both `1.4-maint` and the `1.4.5` tag).
  The wall is a property of the current release, not of trixie's 1.4.0
  package. Terminal.
- **KeePassXC**: the mechanism is the product — every KDBX save is
  encrypted with fresh randomness; no deterministic-save mode exists in
  any version by design (latest stable 2.7.12, released 2026-03-10). A
  run-level recheck cannot change a property the format guarantees.
  Terminal.

## Engine order (fixed here, before any define or explore)

Walls yield their slots; survivors keep the cohort order:

**Mercurial → Jujutsu → Bun.**

## Shim-visibility forecasts carried into the define phase

These are strace observations, not verdicts; the engine's own refusals
decide at explore time.

- **Mercurial**: one C-level thread on the commit path (around the mmap-ed
  rev-branch-cache; invisible to Python threading hooks;
  `worker.*` configs do not remove it). `storage.revbranchcache.mmap=no`
  removes it — measured with a same-transcript control — so the define's
  launcher pins that config. Expected: records cleanly.
- **Jujutsu**: the aarch64 release binary is **statically linked** ("not a
  dynamic executable") — `LD_PRELOAD` interposition cannot load into it at
  all, so the engine is expected to refuse at recording
  (`no_shim_marker`-class). When jj's slot arrives the choice is between
  recording that wall and building a dynamically-linked jj as apparatus;
  neither choice is made here.
- **Bun**: dynamically linked, but the strace pass shows 6 threads
  (`CLONE_THREAD`) during `bun add` — the shim notes any `pthread_create`
  and the engine refuses (`multiple_threads_detected`). Expected wall at
  recording unless a single-threaded mode exists; to be measured at its
  slot. Runs offline (`--network=none` transcript), so the network contact
  is not the blocker.

## What this phase deliberately did not do

No define exists yet; no engine explore has run; no failure of any target
has been observed. The first define (Mercurial) follows the sharpened
mini-seal: define PR to main first, explore after.
