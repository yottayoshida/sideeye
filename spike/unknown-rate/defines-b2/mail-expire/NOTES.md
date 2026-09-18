# mail-expire — define (explored)

Debian description: "Utility to extract outdated messages from mail
folders"; `implemented-in::perl`, `use::organizing`, `works-with::mail`.
Installed 0.9.2+nmu1 in the trixie image. Freshness: no tracked file outside
the selection names it (`b2-author.sh`, 2026-09-18).

man mail-expire: "program to extract outdated messages from mbox files",
SYNOPSIS `mail-expire AGE-IN-DAYS FILES...`; "The old messages are
compressed with gzip or xz and stored in the file with the name following the
pattern MBOXNAME.MONTH_YEAR.gz"; `-t DIR` "Specifies a different target
directory for storing expired mailbox files. Default is the current
directory." Local-file state, documented non-interactive writer that both
rewrites the mailbox and creates the archive → define, one static command
line (`op.txt`): expire messages older than 30 days from the seeded `inbox`,
archiving into the state directory. `setup.sh` seeds a two-message mbox — one
dated 2020 (expired), one dated 2031 (fresh whenever this runs).

**The archive's name carries the run's month.** "The reference time for the
output filename is calculated from the current time minus number of days
specified" — `inbox.2026_08.gz` when authored — so the file the operation
creates is named differently in a later month. Within one run and within
`preflight --twice`'s two runs seconds apart the name is the same, and the
built-in invariant compares the state with itself, so this changes nothing a
verdict rests on; it is why the NOTES rather than the define name the file.

Measured while authoring (container, 0.9.2): the program does not start with
its Depends alone — "Can't locate Date/Parse.pm in @INC" — so `packages.txt`
names `libtimedate-perl`, which the sweep image installs. With it, "I: 1
fresh, 1 expired (to inbox.2026_08.gz)", exit 0, and two runs left
byte-identical `inbox` (158 bytes) and archive (125 bytes; the gzip stream
carries no timestamp that differed).

**Authoring run (2026-09-18, v1.5.0 in the trixie image), with `libtimedate-perl`:**
`preflight --twice` refused the first observed run **`child_touched_state_dir`**
— "a process other than the subject (pid 158) performed
open(…/state/inbox.2026_08.gz), and process 156 wrote in the judged directory
while it was still running": "I: using compressor: gzip -9" — the archive is
written by a `gzip` child the Perl script pipes into, the pacpl shape in this
group. The `next_step` does not name `--observe syscalls`, so under this
group's run contract the sweep records the first leg and runs no second.
Exit 2, no `first_accepted_recording`.
