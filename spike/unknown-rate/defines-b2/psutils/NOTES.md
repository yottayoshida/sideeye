# psutils — define (explored): psnup

Debian description: "PostScript document handling utilities";
`implemented-in::c` (the package also carries Perl scripts),
`use::converting`, `works-with::text`. Installed 3.3.8-1 in the trixie image.
Freshness: no tracked file outside the selection names it (`b2-author.sh`,
2026-09-18).

Nineteen programs; the representative one is `psnup` — man psnup: "Put
multiple pages of a PostScript document on to one page", SYNOPSIS
`psnup [OPTION...] -NUMBER [INFILE [OUTFILE]]`, "OUTFILE `-' or no OUTFILE
argument means standard output". The program names its output file itself,
so the operation is one static command line (`op.txt`): two seeded pages
imposed two-up into `out.ps` beside `in.ps`. Paper sizes are given explicitly
(`-p a4 -P a4`) and the state seeds a two-page DSC-comment PostScript file.

Measured while authoring (container, 3.3.8): psutils calls the `paper`
command and refuses to run without it even when both paper sizes are given
on the command line — "psnup: could not run `paper' command", exit 1. The
`paper` command is `libpaper-utils`, a Recommends the slim image does not
pull in; `packages.txt` names it and the sweep image installs it. With it,
two runs wrote byte-identical output (2672 bytes).

**Authoring run (2026-09-18, v1.5.0 in the trixie image):** `preflight --twice`
accepted — 2 state-changing operations observed, "two runs 2006 ms apart left
equal state under --state". No explore was run before the sweep.
