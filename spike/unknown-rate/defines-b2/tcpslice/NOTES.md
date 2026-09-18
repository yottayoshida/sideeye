# tcpslice — define (explored)

Debian description: "extract pieces of and/or glue together tcpdump files";
`implemented-in::c`, `use::editing`/`use::filtering`, `works-with::file`.
Installed 1.8-1 in the trixie image. Freshness: no tracked file outside the
selection names it (`b2-author.sh`, 2026-09-18).

man tcpslice: "Tcpslice is a program for extracting portions of .pcap … files
produced using tcpdump(1)'s -w flag … The basic operation of tcpslice is to
copy to stdout all packets from its input file(s) whose timestamps fall
within a given range", SYNOPSIS `tcpslice [ -DdlhRrtv ] [ -w output-file ]
… file ...`. With `-w` the program writes the output file itself, so the
operation is one static command line (`op.txt`): copy the seeded capture,
whole (no time range, so "the command tcpslice trace-file simply copies
trace-file"), to `out.pcap` beside it. The seeded `in.pcap` is written by
`setup.sh` with python3's `struct` — a version 2.4 pcap header and three
packets — since a capture must exist before there is anything to slice.

Measured while authoring (container, 1.8): two runs wrote byte-identical
output (174 bytes, the input copied), exit 0.

**Authoring run (2026-09-18, v1.5.0 in the trixie image):** `preflight --twice`
accepted — 2 state-changing operations observed, "two runs 2002 ms apart left
equal state under --state". No explore was run before the sweep.
