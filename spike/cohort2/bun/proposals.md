# Bun — scout proposals (cohort 2, #183)

Sources: the Bun lockfile docs (the selection scout's named source),
`bun add --help`, and the cohort-2 probe (`../probes/bun.txt`,
`../probes/bun-network-independence.txt`). Assisted; no exploration has
run and no failure of the target has been observed.

**Standing forecast, declared before the explore**: the probe measured 6
successful `CLONE_THREAD` creations during `bun add`, and the engine
refuses any thread the shim observes — a `multiple_threads_detected`
refusal at recording is the expected recorded outcome. The define exists
so that outcome is measured through the mini-seal rather than assumed.

## P1 — `bun add` of a local tarball (IMPLEMENTED)

- argv: `bun add --cwd /tmp/cohort2/bun/state /tmp/cohort2/bun/dep-1.0.0.tgz`
  (string form fits; the tarball path is absolute so no cwd plumbing —
  the probe's relative spelling was launcher convenience, not question)
- **why**: `bun add` mutates three things that must agree — package.json,
  the lockfile, and node_modules. The probe measured the whole update as
  byte-deterministic and offline-capable for a local tarball, so the
  crash question is purely about the consistency of that triple.
- **what property**: crash anywhere inside `bun add`, and the project is
  the old state or the new one at the contract level: package.json's
  dependency entry, the lockfile's presence, and node_modules' content
  never contradict each other in a way a re-run does not repair — the
  documented recovery for a package manager is re-running the install,
  and after it the new state holds exactly.
- **where from**: the lockfile docs (bun.lock as the install's record);
  the probe's conditions 3-5 (exact artifact set, content round-trip,
  determinism); `--network=none` transcript (no registry reachability in
  the property).

## P2 — `bun install` from a committed lockfile (recorded, not implemented)

- **why**: the reproduce-from-lockfile path. **what property**: an
  interrupted install leaves a state a re-run completes. **where from**:
  the lockfile docs. Deferred: P1's triple-consistency question is
  sharper and includes the lockfile write itself.

## P3 — `bun remove` (recorded, not implemented)

- **why**: the removal transaction over the same triple. Deferred: same
  machinery, less content at stake.

## Define shape (P1)

- State root: the project directory (`package.json`, lockfile,
  node_modules). The dependency tarball sits outside it, absolute-pathed;
  cache/HOME/TMPDIR are ambient, created by setup, pointed at by the
  launcher's environment.
- Checker: classify old/new from package.json's dependency entry, assert
  the triple agrees with the classification, assert installed bytes match
  the tarball's on the new side, then run the documented recovery
  (re-run `bun add`) and demand the exact new state.
