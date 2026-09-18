# clzip — define (explored)

Debian description: "C, lossless data compressor based on the LZMA
algorithm"; `implemented-in::c`, `use::compressing`, `works-with::archive`.
Installed 1.15-3 in the trixie image. Freshness: no tracked file outside the
selection names it (`b2-author.sh`, 2026-09-18).

man clzip: "Lzip is a lossless data compressor with a user interface similar
to the one of gzip or bzip2", SYNOPSIS `clzip [options] [files]`; `-k,
--keep` "keep (don't delete) input files", `-o, --output=<file>` "write to
<file>, keep input files". The gzip-shaped default — compress `file` to
`file.lz` and remove `file` — is the documented primary operation and the
one this define spells (`op.txt`): the state holds one text file seeded by
`setup.sh`, and the operation replaces it with its `.lz`. The lzip format
carries no name or timestamp, so the output is byte-repeatable; the
contrast in this repository is xz (PASS 4/4 in the 2026-09-16 crossed-walls
run), which creates its output `O_EXCL` beside the input and unlinks the
input last.

Measured while authoring (container, 1.15): two runs wrote byte-identical
`.lz` output (131 bytes), exit 0, and removed the input each time.

**Authoring run (2026-09-18, v1.5.0 in the trixie image):** `preflight --twice`
accepted — 3 state-changing operations observed, "two runs 2001 ms apart left
equal state under --state". No explore was run before the sweep.
