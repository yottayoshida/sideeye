# pngcrush — define (explored)

Debian description: "optimizes PNG (Portable Network Graphics) files";
`implemented-in::c`, `use::compressing`, `works-with::image:raster`.
Installed 1.8.13-1+b2 in the trixie image. Freshness: no tracked file outside
the selection names it (`b2-author.sh`, 2026-09-18).

man pngcrush: "Pngcrush is an optimizer for PNG (Portable Network Graphics)
files. Its main purpose is to reduce the size of the PNG IDAT data stream";
USAGE lists `pngcrush [options] infile.png outfile.png` and `pngcrush -ow
[other options] file.png [tempfile.png]`, with `-ow (Overwrite)`. Both are
documented; this define takes the in-place form, because the file the tool's
name promises to optimise is the one the user keeps, and what a crash can
cost is that file — the same reason the dogfood runs measured oxipng and
codespell in place. One static command line (`op.txt`): `pngcrush -q -ow` on
the seeded PNG, a 16×16 RGB image `setup.sh` writes with python3's `zlib` and
`struct` (the format is a header and three chunks), with the documented
`[tempfile.png]` argument naming the temporary inside the state directory.
`-q` quiets the progress lines only.

**The temporary's location is the define's first lesson.** Without the
argument `-ow` writes `pngout.png` in the current directory; the engine's is
the read-only repository mount, so the first `preflight --twice` was refused
`recording_run_failed` ("the operation exited 1 during the recording run
where 0 was expected") — the tool could not create its temporary, not a
property of the crash window. Naming the temporary is the usage line's own
optional argument, so the define stays inside the documentation.

**Authoring run (2026-09-18, v1.5.0 in the trixie image), with the temporary
named:** `preflight --twice` accepted — 3 state-changing operations observed,
"two runs 2004 ms apart left equal state under --state". No explore was run
before the sweep.

Measured while authoring (container, 1.8.13): two `-ow` runs on identical
inputs left byte-identical 73-byte files (from 126), exit 0; the
`infile outfile` form produced the same 73 bytes.
