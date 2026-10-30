# 0140 — fallocate in mode 0 is a truncate crash point; KEEP_SIZE alone is a read; other modes refuse

- **Status:** Accepted (2026-10-30)
- **Refs:** #978; `spike/dogfood/2026-10-30-fallocate/` (the measurement), `spike/dogfood/2026-10-22-walls-v1150/` (flatpak-fat, ostree-fat),
  `spike/dogfood/2026-10-09-followups-4/transcripts/sources.txt` (libglnx's `glnx_try_fallocate`).
- **Scope:** the shim's Linux wrappers, the `--observe syscalls` trap and handler, the supervising filter and handler,
  the oracle's reading of strace, `docs/report-schema.md`.

## Context

libglnx (flatpak, ostree) calls `fallocate(fd, 0, 0, size)` for every non-empty file it writes through a named
temporary, and glib's `g_file_set_contents` does the same. On a FAT state (no `O_TMPFILE`) both targets are refused
`unsupported_syscall_observed` naming `fallocate`: no recording witness counts it, and the oracle files an
unrecognised state-changing call as unsupported. Measured on 2026-10-30 in the 2026-10-09 follow-ups 3 box, on vfat:
`fallocate(fd, 0, 0, 42) = 0`, then `write(fd, …, 42)`. A kill between the two leaves a file of zero bytes at that size,
a crashed state that has to be explored.

## Decision

By the owner's ruling (2026-10-30), by mode:

1. **Mode 0** is a `truncate` kill point on the descriptor's file, in the shim (`fallocate`, `fallocate64`,
   `posix_fallocate`, `posix_fallocate64`), under `--observe syscalls`, under `--observe supervised` and in the oracle.
2. **`FALLOC_FL_KEEP_SIZE` alone** changes neither the size nor the bytes: no witness counts it, as `readahead` and
   `sync_file_range`. Matched exactly — the kernel takes hole punching only with `KEEP_SIZE`, so "contains `KEEP_SIZE`"
   would pass `KEEP_SIZE|PUNCH_HOLE` as a read. strace's symbolic and numeric spellings are both read.
3. **Any other mode** is not counted by the shim or the supervising engine and is refused by the oracle, naming the
   mode, as `renameat2`'s flags are.
4. The trap and the supervising filter catch `fallocate` unconditionally and decide in the handler: their flag test
   can only catch a call with a bit set, and mode 0 has none.

**No new record class and no contract version** (owner's ruling). Not ADR 0059's precedent, which widened only the
opt-in mode: ADR 0089 item 7 names the countable set of an unchanged target moving as v14's reason to bump, and this
moves it under the default mode. What makes the bump unnecessary is the replay check: a saved case re-records, and a
count that differs refuses `case_no_longer_applies`; every case of a target that calls `fallocate` in mode 0 differs.
A bump would refuse every saved case, including those of targets that never call it.

## Consequences

- Measured with 2026-10-09 follow-ups 3's defines on FAT (`spike/dogfood/2026-10-30-fallocate/`): flatpak-fat
  and ostree-fat, refused `unsupported_syscall_observed` in 3 runs of 3 on main, reached PASS 31/31 and 8/8 in 3
  of 3. The acceptance toy, every file given its size before it is written, under the shim, `--observe syscalls`
  and `--observe supervised`: mode 0 PASS 6/6, `KEEP_SIZE` alone PASS 5/5 (one crash point fewer: not counted),
  `KEEP_SIZE|PUNCH_HOLE` refused naming the mode, the oracle agreeing in each; main refused all nine.
- When the filesystem refuses `fallocate`, glibc's `posix_fallocate` writes the zeros itself through `pwrite`: the
  default mode counts one operation and `--observe syscalls` counts `fallocate` and the writes. Under an oracle the
  counts disagree and the run refuses. Not met by the FAT targets, which accept the call.
- Without an oracle, a call in another mode passes unseen, as `renameat2`'s flags do; a run without an oracle makes
  the weaker claim.
- macOS has no `fallocate`; `F_PREALLOCATE` through `fcntl` is not touched.
