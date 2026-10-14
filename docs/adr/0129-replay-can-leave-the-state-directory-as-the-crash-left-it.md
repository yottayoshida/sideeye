# 0129 — Replay can leave the state directory as the crash left it

- **Status:** Accepted (2026-10-14)
- **Refs:** the 2026-10-14 mechanisms run (#861, `spike/dogfood/2026-10-14-mechanisms/`), whose
  three counted FAILs were each read by rebuilding the crashed state by hand from the evidence
  table (`transcripts/lab-1.txt`); ADR 0072 (`[recovery]`, the precedent for restoring a kept crash
  snapshot after the worlds); ADR 0006 (what a snapshot cannot carry).
- **Scope:** `src/cli.zig` (the flag), `src/main.zig` (keeping the case world's snapshot,
  rewriting the state after the worlds), `src/report.zig` (the `crash state` line and two optional
  JSON fields), `src/evidence.zig` (one line under "Reproducing it"), `docs/cli.md`,
  `docs/report-schema.md`, `docs/contract-freeze.md`, `docs/mcp.md`.

## Context

A replay explores the case's world and the baseline, and the state directory it leaves is the
baseline's with the checker's work on top. The crash state itself — what a reader needs to see why
a world failed, and what a checker author needs before writing the next checker — exists only as a
snapshot the world takes after the kill and before the checker runs, and it is freed when the
world ends. The evidence bundle describes it (each path's kind and size before, completed and
crashed), but does not hold it. The mechanisms run rebuilt it by hand three times, and a
hand-rebuilt state is one more place for a mistake.

## Decision

`sideeye replay <case> --leave-crash-state` keeps the snapshot of the case's crash world — the
world `only_k` names, never the baseline — once that world has passed every refusal it can raise,
and after the worlds and after any recovery, `engine.restore` rewrites the state directory to it.

- **The state directory, and nowhere else.** The replay already empties and rebuilds it every
  world; it has been vetted (`--state-under`, the case-file check, the mount refusal inside
  `restore`). No new directory becomes one the engine empties.
- **After every refusal of that world.** Kept earlier, a world later refused for a FIFO, a
  still-running writer or a boundary the oracle did not confirm would leave a state the run never
  judged.
- **After the recovery.** The recovery rebuilds crash states of its own in the same directory and
  runs a command over them; written before it, the directory left would be the recovery's.
- **Whatever the verdict.** A replay whose FAIL does not reproduce still reached the crash point,
  and the state there is still worth reading. The report says so in the same sentence.
- **Never in place of the verdict.** A rewrite that fails is recorded (`crash_state_left: false`,
  the error in `crash_state_note`) beside the FAIL or PASS; it never goes through
  `refuse.restoreFailure`, which would turn a FAIL into an UNKNOWN over an attachment.
- **Reported from the start.** With the flag, the report says `not left: the run ended before a
  verdict` until the rewrite succeeds, so a refusal inside the worlds reports the truth without a
  path of its own; a refusal after the worlds (an unverified run's completeness) comes after the
  rewrite and reports `left`.
- **Replay only.** Explore, preflight and demo refuse the flag; `--json` inside the state is
  refused with it, and so is a `--json` whose directory cannot be resolved yet — the report is
  written after the rewrite, into a directory the crash state may hold. The MCP server does not
  pass it.

## Alternatives considered

- **Write the crash state to a new directory the caller names (`--keep-crash-state <dir>`).**
  The first draft. A check that the directory does not exist, made before setup, does not hold at
  the rewrite: setup, the operation, `--work` or a second replay can create it in between, and
  `restore` empties whatever it finds. Making it safe needs an exclusive create at the moment of
  writing, path normalisation against the state, the work directory, the report and the case, and
  a mode for a directory holding a copy of the user's state. Rejected on review as a new
  destruction surface for a convenience the state directory already gives.
- **Write every saved exhibit's crash state into the work directory on every explore.** No extra
  step, but every run of every user would keep copies of their state in the work directory and pay
  for writing them. A replay costs one world.
- **An explore flag.** The snapshots would be held for the whole exploration; a replay of the
  saved case reaches the same world.
- **A checker that copies the state out.** Every define would need it, and a checker that runs
  the tool's recovery first — the form the mechanisms run used — would copy the recovered state.

## Consequences

- A reader replays a case once with the flag and reads the state directory, instead of rebuilding
  it from the evidence table.
- What `restore` cannot carry is not carried: timestamps and ownership are the rewrite's, two names
  of one file become two files (ADR 0006), the state directory's own mode is not recorded, a
  directory the engine cannot read is snapshotted empty, and an absolute symlink still points
  where it did.
- A process the replay could not contain (a `setsid` child on macOS) that writes after the rewrite
  changes the state left without the report knowing — the same limit `[recovery]` states.
- The report gains two optional fields, present only with the flag, under the additive allowance
  (`docs/contract-freeze.md`); no exit code and no case format changes.
