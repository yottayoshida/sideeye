Title: `move` leaves notes that link to the moved note empty if their rewrite fails or the process is killed

**Describe the bug**
`notesmd-cli move` rewrites every note that links to the moved note with `os.WriteFile` (`Note.UpdateLinks` in `pkg/obsidian/note.go`, line 181 at `0b6f10f`). `os.WriteFile` truncates the file and then writes it. If that write fails (a full disk, a quota) or the process is killed in between, the linking note is left at 0 bytes and its text is gone. The moved note itself is fine; the damage is to the other notes.

**To Reproduce**
1. A vault with `projects/alpha.md`, and `daily/2026-10-01.md` containing `Worked on [[alpha]] today.` (51 bytes).
2. `(ulimit -f 0; notesmd-cli move projects/alpha projects/alpha-2026 --vault vault)` exits 1.
3. `daily/2026-10-01.md` is now 0 bytes; `projects/alpha-2026.md` exists.
4. notesmd-cli 0.3.7 (the linux arm64 release), Debian 13 in a container.

`ulimit -f 0` stands in for a write that fails after the truncation. Killing the process between the truncating open and the write leaves the same empty note (that is how it was found).

**Expected behaviour**
A note whose rewrite fails keeps its previous text (or holds the updated one), and the error is reported.

**Additional context**
One possible direction, not tried: write the updated content to a temporary file in the same directory and rename it over the note. Not tested: a real full disk, power loss, macOS or Windows.

Disclosure: I found this with [sideeye](https://github.com/yottayoshida/sideeye), a crash-consistency checker I maintain as a personal open-source project, and wrote this report with the help of an AI assistant (Claude), checking it against the runs. If you would rather not have tool-assisted reports here, say so and I will stop.
