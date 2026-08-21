# Bun (cohort 2, target 3) — run log and ruling

One explore (2026-08-21), from main, through the committed launcher.
Outcome: **named wall, exactly the pre-declared forecast** —
`UNKNOWN multiple_threads_detected`: "the target created a thread;
operation order would not be deterministic" (`explore-transcript.txt`,
`report.json`). The probe had measured the mechanism in advance: six
successful `CLONE_THREAD` creations during `bun add`, and the engine
refuses any thread the shim observes — single-threaded exploration is a
v0.1 contract property, not a tunable.

**Latest-stable recheck (PROTOCOL "Versions")**: the measured binary IS
the latest upstream stable — 1.4.0, released 2026-08-20 — so the wall is
a property of the current release by construction. No documented
single-thread switch for `bun add` surfaced in the probe or this run;
absent one, the wall stands.

**Terminal for this cohort.** No target behavior was judged; no failure
of bun was observed (the recording's own `bun add` completed normally —
"Saved lockfile" — before the thread refusal was ruled).

The define, its checker (drilled per leg, including the poisoned-cache
byte drill), and this wall are the cohort's complete record for bun.
