# otf2bdf — define (explored)

Debian description: "generate BDF bitmap fonts from OpenType outline fonts";
`implemented-in::c`, `use::converting`, `works-with::font`. Installed
3.1-4.1+b1 in the trixie image (the program reports itself as 3.0 in the BDF
comment). Freshness: no tracked file outside the selection names it
(`b2-author.sh`, 2026-09-18).

man otf2bdf: "otf2bdf will convert an OpenType font to a BDF font using the
Freetype2 renderer", SYNOPSIS `otf2bdf [options] font.{ttf,otf}`, `-o outfile`
"sets the output filename (default output is to stdout)". The program names
its output file, so the operation is one static command line (`op.txt`):
convert the seeded TrueType font at 12 points to `out.bdf` beside it. The
seeded font is DejaVu Sans copied by `setup.sh` from `fonts-dejavu-core`,
which `packages.txt` names and the sweep image installs.

**Exit convention, measured rather than documented.** The manual says nothing
about exit status. Measured while authoring (container, two fonts, two runs
each): otf2bdf writes the complete BDF (709,030 bytes for DejaVu Sans, byte-
identical across runs) and exits **8**, for both DejaVu Sans and DejaVu Sans
Mono, with or without `-v`. `expect-status.txt` therefore says 8. The
uniform protocol's `0` would refuse the recording on the exit status, the
way cookietool was refused in the first group — a define-budget miss the
page already names, so the measured convention is declared here and this
paragraph is the record that it was measured, not read.

**Authoring run (2026-09-18, v1.5.0 in the trixie image):** `preflight --twice`
refused the first observed run **`oracle_missed_operation`** — "the oracle saw
a state-directory operation the shim did not record; divergence at operation
3: … `write(3</tmp/…/state/out.bdf>, "H 840 0\nDWIDTH 14 0\nBBX 10 9 2 1"...,
4096) = 4096`; the shim's account ends after 2": a 4096-byte write from
inside stdio, ADR 0005's far side (the class metaflac and fontforge are in).
Its `next_step` names `--observe syscalls`, so under this group's run
contract the sweep runs the second leg. No `first_accepted_recording` under
the default mode; exit 2.
