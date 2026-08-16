# hnb — define (explored)

Debian description: "hierarchical notebook"; implemented-in::c,
interface::text-mode (ncurses). man hnb: "hnb uses a simple ascii file for
storing your notes. This file can be specified on the command line" and
`-e  Run commands in noninteractive mode (start hnb with the cli ui and
type 'help' to get more information)`.

Measured while authoring (container, hnb 1.9.18): the `-e` vocabulary
includes `add <string>` and `save`; commands are positional after `-e`
(`hnb <file> -ui cli -e "add hello"`), and on exit hnb writes the notes
file ("hnb export, wrote data to ..."). It also creates `$HOME/.hnbrc` on
first run — a bystander write outside the state directory, which is why
the launcher's scratch HOME matters.

Local-file state, documented non-interactive mode → define. Setup creates
the notes file with one seeded node; the operation adds a second node and
exits, which rewrites the file.
