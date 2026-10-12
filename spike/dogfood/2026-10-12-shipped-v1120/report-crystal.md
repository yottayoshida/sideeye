<!-- Draft for crystal-lang/crystal, 2026-10-12. Filed 2026-10-12 as crystal-lang/crystal#17620, this text approved verbatim by the owner (this comment
excluded).
Contribution policy read: CONTRIBUTING.md and CODE_OF_CONDUCT.md, 2026-10-12 — no rule on
LLM-written text. Title: `crystal tool format` leaves the file empty if it is killed mid-write -->

**`crystal tool format` truncates the file it formats before it writes the result, so a formatter killed between the two leaves the source file empty, with its previous contents nowhere on disk.**

## What happens

`Crystal::Command::FormatCommand#format_source` (`src/compiler/crystal/command/format.cr`, line 146 on `master` as of 2026-10-12) writes the result with `File.write filename, result`. That opens the file with `O_TRUNC` and then writes the formatted text in place. Between the `open` and the `write` the old text is already gone and the new text is not there yet. Nothing else holds a copy: the source was read into memory and the process is the only place it exists.

An error raised while formatting is handled — the file is not touched unless formatting succeeded. A process that is killed (a timeout in an editor's format-on-save, a CI job cancelled, an OOM kill, the machine shutting down) reaches no handler.

## Measured

- Crystal 1.21.1 [73ea5c2b1], the `crystal-1.21.1-1-linux-aarch64-bundled.tar.gz` release, Debian trixie, aarch64.
- The write path, as `strace` printed it:

  ```
  openat(AT_FDCWD, "./src/inventory.cr", O_RDONLY|O_LARGEFILE|O_CLOEXEC) = 8
  close(8)
  openat(AT_FDCWD, "./src/inventory.cr", O_WRONLY|O_CREAT|O_TRUNC|O_LARGEFILE|O_CLOEXEC, 0644) = 8
  write(8, "# Inventory of a small shop, kep"..., 879) = 879
  close(8)
  ```

- Killed after the second `openat` and before the `write` (crash point 2 of 2): `src/inventory.cr` is 0 bytes. Before the command it was 830 bytes; a completed run leaves 879.
- Recovery: none from the tool. The 830 bytes exist nowhere on disk; if the file was committed, version control has the committed copy and nothing newer.
- 1 of the 3 states explored (the two points between file operations, plus an uninterrupted run) showed it; the same state was reproduced twice more by replaying the saved case. A second observer (`strace`) agreed on both operations.

## Why this one may be worth more than the usual in-place-write report

A formatter is most often run on work that is not committed yet: format-on-save in an editor, a pre-commit hook, `crystal tool format` over a tree before the first `git add`. That is exactly the text version control cannot give back.

Two ways to close it, in increasing order of cost, and I have no stake in which:

1. Write the result to a temporary file in the same directory and `File.rename` it over the original. The original stays whole until the rename, and the rename is atomic on POSIX filesystems.
2. The same, with the temporary file flushed to disk (`fsync`) before the rename, which also covers a power loss rather than only a killed process. This makes formatting a large tree slower and may well not be worth it.

## Disclosure

This was found with Sideeye (https://github.com/yottayoshida/sideeye), a tool that runs a command, kills it between each pair of its file operations, and checks what is left on disk. It is a personal open-source project with no commercial interest. The measurement and this text were prepared with an AI assistant (Claude) and checked by me; if you would rather not have tool-generated reports on this tracker, say so and I will stop.

The invariant checked is that after an interruption each file holds either its old contents or its new contents.

## Not claimed

Power loss, torn writes and concurrent processes were not measured: this says what happens when the process dies between two system calls, and nothing about what the filesystem does with data that was not yet flushed. Only `crystal tool format <file>` on one file was measured; the directory form and `--check` were not.
