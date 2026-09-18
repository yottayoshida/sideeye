# icnsutils — define (explored): png2icns

Debian description: "utilities for manipulating Mac OS icns files";
`implemented-in::c`, `use::converting`, `works-with::image:raster`. Installed
0.8.1.83.g921f972-0.1+b2 in the trixie image. Freshness: no tracked file
outside the selection names it (`b2-author.sh`, 2026-09-18).

Four programs; the representative writer is `png2icns` — man png2icns:
"convert png images to Mac OS icns files", `png2icns file.icns file1.png
[file2.png ...]`, each PNG one of the sizes an icns holds (16, 32, 48, 128,
256, 512, 1024). The program names its output file, so the operation is one
static command line (`op.txt`): build `out.icns` from the seeded 32×32 RGBA
PNG, which `setup.sh` writes with python3's `zlib` and `struct`.

Measured while authoring (container, 0.8.1): "Using icns type 'il32', mask
'l8mk'", two runs wrote byte-identical output (2160 bytes), exit 0.

**Authoring run (2026-09-18, v1.5.0 in the trixie image):** `preflight --twice`
accepted — 2 state-changing operations observed, "two runs 2002 ms apart left
equal state under --state". No explore was run before the sweep.
