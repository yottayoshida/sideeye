# zh-autoconvert — define (explored): autogb

Debian description: "Chinese HZ/GB/BIG5/UTF-16/UTF-7/UTF-8 encodings
auto-converter"; `implemented-in::c`, `use::converting`, `works-with::text`.
Installed 0.3.16-10+b2 in the trixie image. Freshness: no tracked file outside
the selection names it (`b2-author.sh`, 2026-09-18).

No manual page; the documentation is the usage text: "Usage: /usr/bin/autogb
[-OPTION] < input > output … -i encoding, --input encoding: Set the input
encoding; -o encoding, --output encoding: Set the output encoding. The
encoding should be gb, big5, hz, uni, utf7 or utf8." The documented invocation
is the shell's redirects, as roffit's is in this group, so the define is
`op.sh` (program by absolute path, `< in.txt > out.txt` inside the state):
convert the seeded UTF-8 text to GB. What a verdict is about is the same as
roffit's note: the shell's truncating open and the program's writes are the
crash points; a FAIL is the documented invocation's window, not a defect in
the converter's own code.

Measured while authoring (container, 0.3.16): two runs wrote byte-identical
output (9 bytes of GB2312), exit 0.

**Authoring run (2026-09-18, v1.5.0 in the trixie image):** `preflight --twice`
accepted — 2 state-changing operations observed, "two runs 2001 ms apart left
equal state under --state". No explore was run before the sweep.
