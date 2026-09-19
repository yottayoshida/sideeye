# Contract card — `synthetic-target.sh` (rehearsal only)

Not one of the four. Written for the rehearsal, with the same structure and the same backings a
real card uses, and with one line deliberately left `unspecified`.

## What the tool does

`synthetic-target.sh <dir> <text>` appends one line to `<dir>/notes.txt` and writes a line count
to `<dir>/.index`.

## Claims

| # | claim | backing | evidence |
|---|---|---|---|
| 1 | `notes.txt` is durable: its contents after a crash are the contract | `documented` | the script's own header: "the durable record. Appended to, and the tool's contract is about its contents." |
| 2 | `notes.txt` is replaced by `mv` from a temporary in the same directory, so a crash leaves the old contents or the new ones, never a partial line | `measured` | with the target's own tools: `sh synthetic-target.sh /tmp/d one; cp /tmp/d/notes.txt /tmp/before; sh synthetic-target.sh /tmp/d two; diff /tmp/before /tmp/d/notes.txt` shows the file gains exactly one line, and `ls -a /tmp/d` shows `.notes.tmp` gone — the write is a rename, not an in-place append |
| 3 | `.index` is scratch: it is derived from `notes.txt` and rewritten on every run | `documented` | the script's own header: "the derived index, rebuilt on demand" |
| 4 | whether `.index` must match `notes.txt` **at rest** — that is, whether a crash between the rename and the index write is a defect | `unspecified` | the script says the index is rebuilt on demand but never says a stale index is acceptable; nothing here settles it |

## What a checker should assert

That `notes.txt` holds whole lines and no partial one, and that its line count is either the
count before the operation or that count plus one. **Not** that `.index` agrees with it —
claim 4 is unspecified, so a define that turns on it is `unresolved by card`, and a define that
treats `.index` as durable contradicts claim 3.
