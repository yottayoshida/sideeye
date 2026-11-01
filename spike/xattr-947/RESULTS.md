# Extended-attribute writes set aside as metadata (#947, ADR 0142)

Measured 2026-10-31 in the box `apparatus/` builds (Debian trixie from the 2026-10-14 snapshot:
`transcripts/versions.txt` — vim 2:9.1.1230-2 and logrotate 3.22.0-1+b2, the versions the walls
were recorded on), linux/arm64 under Docker Desktop, with each target's state on a named volume:
`stat -f` reads `ext2/ext3` there, the magic ext4 shares (`transcripts/*/*/fs.txt`). Each target ran
once, in the default mode with `--oracle /usr/bin/strace`, with the define, seed and checker of the
campaign that recorded its wall: vim from `spike/dogfood/2026-10-06-read-only-684/`, logrotate from
`spike/dogfood/2026-10-14-mechanisms/`.

    sh apparatus/host.sh transcripts <engine-dir> <label>

"This change" is the build before review added `#947` to the `metadata_writes` sentence; the
verdicts and the calls named do not depend on that wording.

| target | engine | verdict | crash points | `metadata_writes` names |
|---|---|---|---|---|
| vim | `origin/main` `651ad406` | UNKNOWN `unsupported_syscall_observed` (`setxattr`) | — | `fchmodat`, `fchmod` |
| vim | this change | **FAIL 1 of 12**, oracle verified | 11 | `fchmodat`, `fchmod`, **`setxattr`** |
| logrotate | `origin/main` `651ad406` | UNKNOWN `unsupported_syscall_observed` (`fsetxattr`) | — | `fchmod` ×3 |
| logrotate | this change | **FAIL 3 of 12**, oracle verified | 11 | `fchmod` ×3, **`fsetxattr`** |

vim's FAIL is the one the FAT run found (`spike/dogfood/2026-10-09-followups-3/`): with the define's
`nowritebackup`, `a.txt` is truncated before it is written, and world 10 leaves it empty — the
user's choice of no backup, not a finding.

logrotate's FAIL is the rotation itself: the built-in layer finds `app.log.2` gone between two of the
renames, and the checker's leg b finds `app.log` gone in one world, which the next unforced run
(leg c, the recovery) accepts. Not filed: the window between moving a log aside and creating its
successor is logrotate's design, and the recovery passes.

Not measured: `--observe syscalls` and `supervised` (the oracle reads the same calls there; the
change is in the oracle's reader), macOS (check 16 of `spike/fsusage/acceptance-local.sh` runs a
`setxattr` and an `fsetxattr` under a real `fs_usage` in CI).
