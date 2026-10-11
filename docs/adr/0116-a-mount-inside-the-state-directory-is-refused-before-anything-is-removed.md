# 0116 — A mount inside the state directory is refused before anything is removed

- **Status:** Accepted (2026-10-11)
- **Refs:** #817 (measured on 2026-10-11: a directory bind-mounted at `state/sub` had every file
  beneath it deleted by the first restore, which then failed `EBUSY` and reported
  `state_rewrite_failed` with "the define itself is unchanged"); ADR 0024 and ADR 0037 (the root the
  walk deletes, and the windows those leave); SECURITY.md (the protections and what they leave open).
- **Scope:** `src/engine/state_fs.zig` (`firstMountInside`, the snapshot walk, `deleteTreeAt`, the
  three removing entry points `restore`, `freshDir` and `corruptState`), `src/refuse.zig`,
  `src/report.zig`, `spike/acceptance.sh` check 25, the macOS job in `.github/workflows/ci.yml`.

## Context

Every world empties the state directory and rebuilds it from the snapshot. `deleteTreeAt` descends
into every directory entry with `openat(O_DIRECTORY | O_NOFOLLOW)`, which refuses a symlink and does
not stop at a mount point, so a bind mount, a container volume or a disk image mounted inside the
state was emptied: everything it held was removed, the mount point's own `rmdir` failed `EBUSY`, and
the run was reported as an environment fault. The snapshot walk descended there too, so a mounted
tree was also read into memory as if it were state.

## Decision

1. **The mount table, on Linux.** `firstMountInside` reads `/proc/self/mountinfo`, undoes the kernel's
   octal escapes, and returns the first mount point strictly below the state root. The root itself
   being a mount point is fine. A table that cannot be read, or a line whose fifth field cannot be
   read, answers `unlisted`, which refuses like a mount: the one unread line could be the one inside
   the state. A line longer than the reader's buffer is read by its head — the mount point is the
   fifth field, ahead of the options an overlay's layer list makes long — and the rest is read past;
   failing on it would refuse every run on such a host.
2. **A walk by device, on both.** When the table names nothing — and on macOS, which has no table
   and no bind mounts — `firstMountInside` walks the state's directories before anything is removed
   and returns the first whose device differs from the root's. On Linux this names a btrfs subvolume,
   which the table does not list, and a mount on another device whose line a long table's reads
   missed. A directory it cannot open or identify is passed over, as the snapshot records it.
3. **Device numbers in the snapshot and the removal, on both.** The snapshot walk refuses a directory
   whose device differs from the root's, and `deleteTreeAt` refuses to descend into one: a mount that
   appears after the first check is still not removed through when it is another device. Measured
   once on macOS with the walk of item 2 disabled: a replay's `--fresh-state` over an attached disk
   image stopped at it with the image's file intact; with this check also removed, the file was
   deleted. A directory the snapshot cannot identify is not refused for it — one that vanished under a
   still-running writer is `state_not_quiescent`'s to name, and one under a parent without search
   permission was always recorded as an empty directory.
4. **Where it is asked, and how often.** Before every snapshot walk, so a mounted tree is neither
   read nor reached; and after the root's vet in each of the three entry points that remove or write
   inside the state, so a replay's `--fresh-state` (which runs before setup and before any snapshot)
   and a mount made during the run are refused there. On Linux a descriptor on the table is opened
   before the first reading and kept, and the table is read again only when `poll` reports a change
   on it (`POLLPRI`); a root cleared earlier is answered from the last reading otherwise. Measured in
   a container with 2,014 mounts (a 119 KB table), an exploration of 25 worlds: 128 ms before the
   change, 342 ms reading the table at every snapshot and restore, 131 ms with the watch. With the
   `poll` disabled, a checker that bind-mounted a directory inside the state during its falsification
   had the mounted tree emptied by the next restore; with it, the restore refused naming it. The snapshot answers `MountInside`, a SETUP ERROR before
   the recording and `unsupported_state_entry` after it; the entry points answer
   `RestoreError.MountInside`, which `restoreFailure` turns into the same sentence, naming the mount
   point from a fresh scan when it finds one. No `unknown_reason`, `setup_error_reason` or NextStep is added.

## Alternatives considered

- **`statx`'s `STATX_ATTR_MOUNT_ROOT` or `STATX_MNT_ID` on each entry.** Linux 5.8 and later only;
  the supported range starts at 4.18 (`docs/cli.md`'s platform table), and RHEL 8 would miss a bind
  mount of the same filesystem.
- **Device numbers alone.** A bind mount of the same filesystem keeps its device: both sides read
  `dev=62` in the measurement that found #817.
- **`openat2(RESOLVE_NO_XDEV)` in the walk.** Linux 5.6 and later, and absent on macOS.
- **`getmntinfo` on macOS.** Its mount-on names can come back in the firmlinked spelling
  (`/System/Volumes/Data/…`), which a realpath'd root does not share; device numbers need no names.
- **Narrowing the documents instead of walking on macOS.** A replay's `--fresh-state` would have
  removed what it reached inside the state, and named nothing, before the removal met the device
  change; the walk makes "before anything is removed" true there too.

## Consequences

- What stays open is in SECURITY.md: a mount made in the moment between a check and the removal or
  rebuild after it is not seen — the removal still stops at one on another device, but on Linux a
  bind mount of the same filesystem made then is not, and the rebuild and the checker's corruption
  write by name; a long mount table is read in more than one read, and the line for a bind mount of
  the same filesystem can be missed if other mounts change between them; a btrfs subvolume inside the
  state is refused although it is not a mount.
- On Linux a run reads the mount table and walks the state's directories once, and again only after
  the table changes; macOS walks them at every snapshot and restore, bounded by the state. A refusal
  reads them again to name the mount. Each directory the snapshot or the removal enters is identified
  once more.
