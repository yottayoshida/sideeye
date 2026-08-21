# BorgBackup (cohort 2 follow-up, #200) — run log and ruling

## Timeline (all 2026-08-21, each step's evidence committed where named)

1. **Probe stage** (#203): the original wall (two pinned creates split)
   fell to a three-piece declared apparatus — libfaketime at speed x0 for
   realtime, a sitecustomize pinning `time.monotonic` and `os.urandom`
   (owner-approved: an integrity tag's salt at encryption=none, not
   encryption). Three leaks, each found by measurement: the monotonic
   duration in `time_end`, the manifest's utcnow, the TAM salt. The
   harness itself was corrected en route (borg embeds argv in archive
   metadata — runs now restore in place at one canonical path, the
   engine's own semantics). Frozen probe: six-for-six green, with pinned
   (splits) and control (splits) beside it.
2. **r1** — `kill_did_not_land` (`../borg/explore-r1-transcript.txt`):
   the client cache lived outside the state root, so every world's borg
   met a cache newer than its rolled-back repository and refused before
   any op the kill could land on. Same class as hg's wcache.
3. **r2** — cache moved inside the state root; checker gained leg R0
   (a suspect cache's documented handling is deletion-and-rebuild).
   Explore refused `unsupported_syscall_observed: sendfile`
   (`../borg-r2/explore-r2-transcript.txt`) — CPython's shutil fast-copy,
   hg-r3's exact refusal.
4. **r3** — the sitecustomize gains hg-r3's line
   (`shutil._USE_CP_SENDFILE = False`). The explore reaches a verdict
   (`explore-transcript.txt`, `report.json`, `cases/000001.json`), and a
   second run reproduces it identically (FAIL 3/119, oracle_verified
   true, both runs).

## The verdict, read under the protocol's frozen claim rule

**FAIL, 3 of 119 explored worlds; every violation is L0-only, and all
three sit in the client cache the apparatus itself relocated.**

- **Borg's documented transactional contract held in all 119 worlds.**
  The checker — stale-lock removal exactly when a lock existed (14
  worlds, all succeeded), `borg check`, byte-identical conservation of
  the pre-existing `base` archive, old-or-new listing, new-side content —
  ran everywhere and failed nowhere.
- **The three L0 violations are `ambient/.cache/borg/<repo-id>/chunks`**:
  the client cache's in-place rewrite, caught mid-write. That file is (a)
  not repository state, (b) explicitly rebuildable — deletion is Borg's
  own documented handling, the checker's leg R0 exercises it every world
  — and (c) inside the judged root only because r2 moved it there so
  worlds could run at all. The multi-write shape, #35's class, tinted
  further by our own apparatus.
- **Criterion-1 candidate: none.** The saved case's violated invariant is
  L0, not the declared checker. Recorded as a precision-limit
  observation, per the reading frozen before any cohort explore ran.

## Apparatus notes

- The measured borg runs on pinned clocks, a pinned entropy source
  (`os.urandom` — visible in the transcript as the all-`5a` repo id), and
  the sendfile fallback. **Any finding must reproduce against stock borg
  (strace fault injection) before it is claimed or reported**; none is
  being made.
- The report's metadata line shows #190 working: `fchmodat x3` observed
  and excluded. `oracle agreed on 118 operations`, single process.
