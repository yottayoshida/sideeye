# #978: fallocate by mode

main (`f07d80a6`) beside this change, both built for aarch64 Linux and mounted into the boxes their defines
were written for (`apparatus/gate.sh`, `apparatus/b.sh`), with the cgroup the engine needs
(`--privileged --cgroupns=private`).

| define | runs | main | this change | record |
|---|---|---|---|---|
| flatpak-fat (2026-10-09 follow-ups 3, the state on FAT), `explore --oracle` | 3 each | `unsupported_syscall_observed` 3 | PASS 31/31 3 | `transcripts/flatpak-fat.txt` |
| ostree-fat (the same box) | 3 each | `unsupported_syscall_observed` 3 | PASS 8/8 3 | `transcripts/ostree-fat.txt` |

The acceptance toy (`TOY_FALLOCATE`), every file it writes given its size first, `explore --oracle` under each
observation mode (`transcripts/toys.txt`):

| mode of the call | shim | `--observe syscalls` | `--observe supervised` | main, every mode |
|---|---|---|---|---|
| 0 | PASS 6/6 | PASS 6/6 | PASS 6/6 | refused |
| `FALLOC_FL_KEEP_SIZE` | PASS 5/5 | PASS 5/5 | PASS 5/5 | refused |
| `FALLOC_FL_KEEP_SIZE\|FALLOC_FL_PUNCH_HOLE` | refused, naming it | refused, naming it | refused, naming it | refused |

Mode 0 is one crash point more than `KEEP_SIZE` alone: it is counted, and the oracle agrees in each mode.

Before the measurement, on 2026-10-30, flatpak on vfat under strace: `fallocate(fd, 0, 0, 42) = 0`, then
`write(fd, …, 42)`, then the rename — the call succeeds there and grows the temporary with zeros.
