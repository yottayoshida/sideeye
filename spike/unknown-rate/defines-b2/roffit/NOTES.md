# roffit — define (explored)

Debian description: "convert nroff manual pages into HTML";
`implemented-in::perl`, `use::converting`, `works-with::text`. Installed
0.16-1 in the trixie image (the manual's footer says 0.13). Freshness: no
tracked file outside the selection names it (`b2-author.sh`, 2026-09-18).

man roffit: SYNOPSIS `roffit [options] < inputfile > outputfile` —
"roffit converts the inputfile to outputfile. The inputfile must be an nroff
formatted man page, and the outputfile will be an HTML document." The program
has no option naming an output file; `--help` adds an optional `[infile]`
positional. The documented invocation is therefore the shell's redirects, and
that is what this define spells: `op.sh` (the ADR 0007 fallback, naming the
program by absolute path) with `< in.1 > out.html` inside the state directory —
the same reason lbdb's define in the first group carries its stdin redirect.

**What a verdict here is about, stated before the run.** The shim follows the
wrapper's `exec` (ADR 0018's amendment), so the shell's truncating open of
`out.html` and roffit's writes to it are the crash points. A FAIL is a window
in the documented invocation — a partial or empty `out.html` — and not a
defect in roffit's own code, which never opens the file; a PASS says the
redirect's writes were judged atomic over this input. The state holds one
nroff page seeded by `setup.sh`; no `out.html` exists before the operation, so
nothing pre-existing is at risk (the first group's 2vcard convention: the
output is created beside the input).

**Authoring run (2026-09-18, v1.5.0 in the trixie image):** `preflight --twice`
accepted — "two runs 2004 ms apart left equal state under --state". No
explore was run before the sweep.
