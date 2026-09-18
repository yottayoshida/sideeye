# giflib-tools — define (explored): gif2rgb

Debian description: "library for GIF images (utilities)"; `implemented-in::c`,
`use::converting`, `works-with::image:raster`. Installed 5.2.2-1+deb13u1 in
the trixie image. Freshness: no tracked file outside the selection names it
(`b2-author.sh`, 2026-09-18).

Six programs; the representative one is `gif2rgb` — man gif2rgb: "convert
images saved as GIF to 24-bit RGB triplets", SYNOPSIS `gif2rgb [-v] [-1] [-c
colors] [-s width height] [-o outfile] [-h] [gif-file]`; `-1` "Only one file
in the format of RGBRGB... triplets … is being read or written", `-o`
"specifies the name of the out file". The program names its output file, so
the operation is one static command line (`op.txt`): convert the seeded GIF
to `out.rgb` beside it. The seeded image is the well-known 43-byte 1×1
GIF89a (a black pixel with a transparent index), written by `setup.sh` from
its base64; a GIF assembled by hand from the format's description was refused
by the library as "Image is defective" — its LZW stream was wrong — and the
constant is the smallest input the library accepts.

Measured while authoring (container, 5.2.2): two runs wrote byte-identical
output (3 bytes), exit 0.

**Authoring run (2026-09-18, v1.5.0 in the trixie image):** `preflight --twice`
accepted — 2 state-changing operations observed, "two runs 2005 ms apart left
equal state under --state". No explore was run before the sweep.
