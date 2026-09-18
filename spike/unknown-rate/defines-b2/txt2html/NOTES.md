# txt2html — define (explored)

Debian description: "Text to HTML converter"; `implemented-in::perl`,
`use::converting`, `works-with::text`. Installed 1:3.0-1 in the trixie image.
Freshness: no tracked file outside the selection names it (`b2-author.sh`,
2026-09-18).

man txt2html: "txt2html converts plain text files to HTML … One can use
txt2html as a filter, outputting the result to STDOUT, or to a given file",
with `--infile filename` and `--outfile filename` in the SYNOPSIS. The program
names both files itself, so the operation is one static command line
(`op.txt`): convert the seeded `in.txt` to `out.html` beside it — the
documented primary function, one invocation, the first group's 2vcard
convention.

**Authoring run (2026-09-18, v1.5.0 in the trixie image):** `preflight --twice`
accepted — "two runs 2003 ms apart left equal state under --state". No
explore was run before the sweep.
