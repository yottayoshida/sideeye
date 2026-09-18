# conv-tools — define (explored): dirconv

Debian description: "convert 8 bit character encoding in file names and text
content to UTF-8"; `implemented-in::c`, `use::converting`,
`works-with::file`. Installed 20160905-5+b1 in the trixie image. Freshness:
no tracked file outside the selection names it (`b2-author.sh`, 2026-09-18).

Two programs; the one that changes state is `dirconv` — man dirconv:
"locate and transcode mixed-encoding file names … recursively scans the
specified path(s) and classifies files and directories according to whether
their names are pure 7-bit ASCII, non-ASCII but valid UTF-8, double-UTF-8
(WTF-8), or neither. Names in the latter category are assumed to be Latin-1";
`-r` "Attempt to convert the selected names to UTF-8 and rename the files and
directories". Local-file state, documented non-interactive writer → define,
one static command line (`op.txt`): `dirconv -r` over the state directory,
which `setup.sh` seeds with one file whose name carries a Latin-1 byte
(`caf\xe9.txt`, written by python3 — a shell `printf` in the image leaves
`\xe9` as four characters). The operation is a rename, the one kind of write
this engine treats as atomic by construction, so the expected shape is a
short exploration.

Measured while authoring (container, 20160905): "/tmp/dc/caf?.txt ->
/tmp/dc/café.txt", exit 0; the name afterwards is the UTF-8 bytes
`c a f 303 251`.

**Authoring run (2026-09-18, v1.5.0 in the trixie image):** `preflight --twice`
accepted — 1 state-changing operation observed (the rename), "two runs 2001
ms apart left equal state under --state". No explore was run before the
sweep.
