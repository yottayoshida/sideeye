# 0109 — Restore carries permission bits

- **Status:** Accepted (2026-10-10; the owner ruled at implementation to amend ADR 0072's ruling on permissions)
- **Amends:** ADR 0072, decision 3 and the alternative "Restore crash-time timestamps and permissions", for
  permissions only; timestamps stay as that ruling left them. Dated notes on that page point here.
- **Refs:** #678; `spike/dogfood/2026-10-03-user-data/` (the run that met it), `spike/dogfood/2026-10-10-restore-modes-678/`
  (the re-measurement).
- **Scope:** `src/engine/snapshot.zig`, `src/engine/state_fs.zig`, `src/engine/read.zig`, `src/posix.zig`, `src/recovery.zig`,
  the sentences that described the old restore (`src/main.zig`'s `metadata` line, `src/contract.zig`'s
  `second_run_diverged`, `kill_not_landed` and `not_repeating`, `--help`, `src/evidence.zig`), `docs/cli.md`,
  `docs/report-schema.md`, `docs/evidence.md`, `spike/toys/toy.c`, `spike/acceptance.sh`.

## Context

A snapshot held names, kinds, bytes and link targets, and `restore` rebuilt every file 0644 and every directory
0755, through the umask. The recording run starts from the files the setup left; `preflight --twice`'s second run,
every crash world and a recovery's crash state start from the restore. A target whose behaviour depends on a mode
under `--state` therefore ran its recording from one mode and everything after from another. The 2026-10-03 run met
two (upx 5.2.1 needs its input executable, argocd 3.5.3 a 0600 config) and a probe with no target, all refused
`recording_run_failed` at `preflight --twice`; #710 then named the case in `second_run_diverged`, which left it
unmeasured.

ADR 0072 (#606) had ruled on the same mechanism from the recovery's side: "Restore crash-time timestamps and
permissions" was rejected by the owner, because "it widens what every snapshot carries and what every restore does,
for every world of every run, to serve the subset of recoveries that decide by time or mode". #678 is not that
subset. Its targets are not judged at all, in any mode, and every world is where they diverge.

## Decision

1. **A snapshot records the read, write and execute bits of each file and directory** (`Entry.mode`, null for a
   symlink and wherever nothing was read). A file's bits come from the descriptor whose bytes the walk read (statx
   granted `MODE`, or fstat); a directory's from the name, before the walk opens it. Null is the default so an entry
   built by hand is not restored 0000. The judgement does not read it: `diffSnapshotsExcept` compares kind and
   content, and `preflight --twice` compares what it compared.
2. **`restore` puts them back through descriptors.** A file's bits go on the descriptor that wrote it (`fchmod`,
   which the umask does not narrow); a directory's on a descriptor opened without following a link, with its owner's
   read, write and search bits added — this restore needs them to create the entries under it, and the next world's
   `deleteTreeAt` to empty it; giving `deleteTreeAt` a chmod by name instead would let a target that rearranges the
   tree redirect it (#446's shape). A refused `fchmod` is accepted when the object already carries the bits, and is
   otherwise a restore failure, as a short write is. The case this is for — a mount that fixes every mode, as FAT's
   `fmask` does, where the walk read that same mode — is reasoned, not measured on this build.
3. **Set-user-ID, set-group-ID and sticky bits, owners and timestamps are not carried.** The engine would create a
   set-user-ID file in every world; a set-group-ID bit for a group the user is not in is dropped or refused
   differently by the two platforms; neither was measured. Timestamps stay as ADR 0072 left them.
4. **The two probes carry the bits too.** `corruptState` removes a regular file and creates the probe with the
   recorded bits, since a user who is not root cannot write over a restored 0444 or 0400 file; a link where the
   snapshot holds a file is refused as before. `recovery.probeSnapshot` copies each entry's bits: the baseline it is
   compared with is rebuilt with them, and a probe without them would let a checker that reads only a mode reject
   the probe and accept the baseline without reading a byte.
5. **ADR 0072's ruling is amended for permissions.** Its cost — every world restores more — was measured: an explore
   over 2,000 state files and five worlds, on the engine before and after, three pairs alternated, took 0.49, 0.46 and
   0.45 s before and 0.46, 0.54 and 0.46 s after — no difference beyond the run-to-run spread
   (`spike/dogfood/2026-10-10-restore-modes-678/apparatus/cost.sh`, `transcripts/cost.txt`).

## Alternatives considered

- **Name the case in the next step and add a line to the README** (#678's cheaper direction). The next step was
  done by #710; the README is at its word limit; and the targets stay unmeasured.
- **Judge the bits too.** A different promise — finding a chmod out of order — and ADR 0072's and #121's exclusion of
  metadata writes from the judgement is not revisited here.
- **Restore a directory's bits exactly.** A directory its owner may not write stops the next world's delete, and
  making the delete change modes by name opens the race #446 closed. The usual directories a tool checks (`~/.ssh`,
  GnuPG's home, both 0700) keep their owner's bits anyway; none was measured here.
- **Keep ADR 0072's ruling for the recovery's crash state only.** Offered to the owner, not taken: the cost the ruling
  weighed is the per-world restore, which this changes either way, and a recovery then sees the crash's bits where
  the world it recovers from had them.

## Consequences

- `metadata`, `second_run_diverged`, `kill_not_landed`, `not_repeating`, `--help` on `--twice` and on `--recovery`, the
  report's `recovery` account, the evidence bundle's recovery caveat and `docs/cli.md`'s recovery limits say what the
  restore carries now. A setup that leaves a
  directory its owner cannot write still stops `deleteTreeAt` at the first rebuild, as before.
- A target that changes a mode during the operation is unaffected in what is judged: the chmod is still observed and
  excluded (#121). What changes is that each world starts from the recorded bits, as the recording did.
- The acceptance suite holds the probe's shape, a 0444 file meeting the checker's falsification as the suite's user
  (CI's is not root), a target that requires a 0600 key, and a recovery checker that reads only a mode.
