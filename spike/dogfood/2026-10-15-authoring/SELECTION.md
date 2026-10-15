# 2026-10-15 authoring — the selection (#873)

`screen.sh` ran `CANDIDATES.md`'s order twice: the first run (`screen-1.tsv`) failed on three faults
of the screen's own, recorded in `PROTOCOL.md`'s Amendments, and the second (`screen.tsv`) is the
one this selection reads. In each shape the first candidate whose fixture and operation both
exited 0 is the target; nothing was screened past it.

| shape | target | screened | not reached |
|---|---|---|---|
| 1 — related files whose records must agree | **quilt** `0.68-1` | quilt passed | rcs, etckeeper, aptly |
| 2 — a documented restart, recovery or undo path | **gdbmtool** `1.24-2` | gdbmtool passed | stgit, xapian-omega |
| 3 — a migration or multi-step change of logical state | **python3-yoyo** `9.0.0+dfsg1-3` | python3-yoyo passed | xapian-tools, slapd, python3-flask-migrate |

In the first run rcs passed in shape 1 because quilt's fixture failed; that result is the
screen's fault and is not a selection. A reader who wants rcs measured has its line in
`screen-1.tsv` and its legs in `CANDIDATES.md`.

What the subject is given — the target, its version, the operation and the shape sentence — is
`selection.tsv`. What the graders are given is `cards/<package>.md`, sealed with this page.

**The screen is a bias, stated here rather than hidden.** It keeps the targets whose operation
runs in a box with no network as an ordinary user, which favours small packaged tools with files
under the user's control. No candidate was screened by running Sideeye.
