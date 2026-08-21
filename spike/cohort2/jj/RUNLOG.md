# Jujutsu (cohort 2, target 2) — run log and ruling

One explore (2026-08-21), from main, through the committed launcher.
Outcome: **named wall, exactly the pre-declared forecast** —
`UNKNOWN no_shim_marker`: "the shim never initialised: statically linked,
hardened, or not injected at all" (`explore-transcript.txt`,
`report.json`). The probe had measured the mechanism in advance: the
v0.44.0 release binary answers `ldd` with "not a dynamic executable", and
an `LD_PRELOAD` shim cannot load into a static binary.

**Latest-stable recheck (PROTOCOL "Versions")**: the measured binary IS
the latest upstream stable — v0.44.0, the release current at selection
and at this run — so the wall is a property of the current release by
construction.

**Terminal for this cohort.** The deferred alternative — building a
dynamically-linked jj from source as apparatus — remains open as a
possible future slot, but it is a new apparatus decision, not a
continuation of this define. No target behavior was judged; no failure of
jj was observed (the transcript's divergent-commit lines are jj's normal
output while the engine's worlds ran unshimmed setups).

The define, its checker (drilled per leg), and this wall are the cohort's
complete record for jj.
