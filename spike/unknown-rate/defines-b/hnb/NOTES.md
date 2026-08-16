# hnb — define (explored)

Debian description: "hierarchical notebook"; implemented-in::c,
interface::text-mode (ncurses). man hnb: "hnb uses a simple ascii file for
storing your notes. This file can be specified on the command line" and
`-e  Run commands in noninteractive mode (start hnb with the cli ui and
type 'help' to get more information)`.

Measured while authoring (container, hnb 1.9.18): the `-e` vocabulary
includes `add <string>` and `save`; commands are positional after `-e`
(`hnb <file> -ui cli -e "add hello" save`), and the write happens when the
`save` command runs — an `-e` run that only adds exits rc=0 **without**
writing the file (measured; an earlier draft of this note wrongly credited
export-on-exit). The resulting file is timestamp-free XML, so the write is
byte-reproducible. hnb also creates `$HOME/.hnbrc` on first run — a
bystander write outside the state directory, which is why the launcher's
scratch HOME matters.

Local-file state, documented non-interactive mode → define. Setup creates
the notes file with one seeded node; the operation adds a second node and
exits, which rewrites the file.

**Operation spelling (measured 2026-08-16):** hnb's `-e` commands are single
positional strings ("add second" is one argument carrying a space), which the
engine's space-split operation contract cannot spell — ADR 0007 sends such
invocations to a script file, so this define keeps `op.sh`. A script wrapper
that performs no state-changing operation before its `exec` is an image
change the v10 observation rules refuse structurally (measured on 2vcard
while authoring, then reproduced as the reason to prefer `op.txt`
elsewhere). If this trial refuses on that rule, the refusal is the recorded
verdict: the define budget could not spell this target inside the contract.
