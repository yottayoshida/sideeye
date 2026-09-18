# pacpl — define (explored)

Debian description: "multi-purpose audio converter/ripper/tagger script";
`implemented-in::perl`, `use::converting`, `works-with::audio`. Installed
6.1.3-1 in the trixie image. Freshness: no tracked file outside the selection
names it (`b2-author.sh`, 2026-09-18).

man pacpl: "Perl Audio Converter. A Linux CLI tool for converting multiple
audio types from one format to another", SYNOPSIS `pacpl --to <format>
<options> [file(s)/directory(s)]`; `-t, --to format` "set encode format for
the input file(s)". The converted file is written beside the input with the
new extension, so the operation is one static command line (`op.txt`):
convert the seeded WAV to FLAC. The seeded WAV is one second of a 440 Hz tone
written by `setup.sh` with python3's `wave` module.

Measured while authoring (container, 6.1.3): pacpl drives external encoders,
and with only its Depends installed `--to flac` reports "Total files
converted: 0, failed: 1" while exiting 0 — nothing written, nothing to judge.
With the `flac` package (`packages.txt`; the sweep image installs it) two
runs wrote byte-identical `a.flac` (17,015 bytes), exit 0. The CD-ripping
function the description also names is not the operation here.

**Authoring run (2026-09-18, v1.5.0 in the trixie image):** `preflight --twice`
refused the first observed run **`child_touched_state_dir`** — "a process
other than the subject (pid 973) performed open(…/state/a.flac), and process
979 wrote in the judged directory while it was still running — nothing had
collected": pacpl is a Perl script that runs the encoder as a child, and the
child is the writer. Its `next_step` says to invoke the wrapped command as
the operation instead — which would make the target `flac`, not pacpl — and
does not name `--observe syscalls`, so under this group's run contract the
sweep records the first leg and runs no second. The define stands: the
operation is the one the manual documents. Exit 2, no
`first_accepted_recording`.
