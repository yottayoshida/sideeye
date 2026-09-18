# enscribe — define (explored)

Debian description: "convert images into sounds"; `implemented-in::c`,
`use::converting`, `works-with::image`/`works-with::audio`. Installed
0.1.0-5+b2 in the trixie image. Freshness: no tracked file outside the
selection names it (`b2-author.sh`, 2026-09-18).

man enscribe: "enscribe converts the scan-lines of the input image into
frequency components and then using an inverse Fast Fourier Transform,
converts them into sound", SYNOPSIS `enscribe [options] [input image]
[output sound]`; the manual defers the options to `--help`, which says
"Usage: enscribe [switches] input_image output_audio. Valid image formats:
Jpeg, Png, WBMP, Xbm, GD, GD2". The program names its output file, so the
operation is one static command line (`op.txt`): convert the seeded image to
`out.wav` beside it. The seeded image is an XBM — a text format, written by
`setup.sh` as a 16×8 bitmap — because it is the one documented input format a
heredoc can produce without an image library.

Measured while authoring (container, 0.1.0): two runs wrote byte-identical
output (1,048,620 bytes), exit 0.

**Authoring run (2026-09-18, v1.5.0 in the trixie image):** `preflight --twice`
accepted — 260 state-changing operations observed (the WAV is written in
many pieces), "two runs 2005 ms apart left equal state under --state". No
explore was run before the sweep.
