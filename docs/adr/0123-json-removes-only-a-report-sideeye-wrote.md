# 0123 — `--json` removes what is at its path only when it is a report Sideeye wrote

- **Status:** Accepted (2026-10-11)
- **Refs:** #818 (found by reading the source in the 2026-10-11 survey); `docs/cli.md`'s
  "`--json` removes the report at its path", which this makes literally true;
  `docs/report-schema.md`'s envelope paragraph, corrected here.
- **Scope:** `src/report.zig` (`reportSlot`, the temporary file `writeJsonDoc` moves into place),
  `src/cli.zig` (the `--json` branch of the argument loop), `src/mcp.zig` (`reportOfThisCall`),
  `docs/cli.md`, `docs/report-schema.md`.

## Context

`--json <path>` removed whatever was at its path as the arguments were parsed, so that a run
ending before any writer leaves no report rather than an earlier run's verdict. The removal was a
bare `unlink`, before `replay` read its case and before `--config` was read, and every refusal
then wrote its own report to the same name. Three things followed from one mistyped or
over-natural argument: `replay case.json --json case.json` deleted the case and left the refusal's
report in its place; `explore --config sideeye.toml --json sideeye.toml` did the same to the define;
and `--json /dev/stdout` run as root unlinked the device link and left a regular file at that
name, so later writes there on that host or container went into the file. The report itself
never reached standard output that way: as root it went into that file, as anyone else nowhere.

## Decision

What is at the path when the flag is read decides what the flag may do to it:

- nothing there — nothing to remove;
- a regular file that is empty, or that holds one JSON document and nothing after it, whose
  `schema` is `sideeye/report` or `sideeye/preflight`, however it is formatted (read whole, up to
  4 MiB; a report piped through `jq -c` or `jq -S` is still one) — removed, as before;
- anything else, a link, a directory, a FIFO, a device, a socket, a regular file that is neither,
  one that cannot be read, or a name whose kind cannot be read at all — refused as SETUP_ERROR
  `define_invalid`, naming the path and its kind. The refusal clears the report path first, so
  neither this path nor an earlier `--json` in the same command receives the refusal's report: it
  produces no document, and so no `json sha256=` line.

The document is written to a temporary file this run creates new beside the path
(`O_CREAT|O_EXCL|O_NOFOLLOW`, a random name of fixed length) and renamed into place. The rename
itself stays unconditional. The MCP server, which reads its child's report back from the work
directory, now reads it only when its verdict (or a preflight document's outcome), its `exit_code`
and the code the child exited with are the same value, as `docs/report-schema.md` promises they
are. Before this change the child removed whatever sat at the report path unconditionally; a
document planted between the server's own removal and the child's reading of the flag is now
refused by the child, which exits 3, and can be read by the server only if it says SETUP_ERROR.

`docs/report-schema.md` said a report at the path always describes this run. It never did for a
run refused before `--json` was read, and now also not for one that refused the path itself; the
paragraph names both and points to the `json sha256=` line, which neither prints.

## Alternatives considered

- **Compare `--json` with the case and the config after resolving all three** (the issue's
  first direction). It protects those two files and nothing else a typo can reach: a README, a
  source file, another run's case.
- **Remove the stale report just before the first write instead of while parsing** (the issue's
  fourth direction). The final `rename` replaces whatever is at the name, device or link
  included, so `/dev/stdout` is replaced all the same; and a run that dies before writing would
  leave the earlier run's verdict, which is what the early removal exists to prevent.
- **Accept `-` for standard output** (the issue's third direction). A new capability with a line
  of its own in the documentation; the data loss is gone without it.
- **Judge the path again just before the rename and leave anything that is not a report.** The
  MCP server reads the report its child wrote back from the work directory, which the judged
  program can write: a document planted there during the run would be left in place and read as
  the verdict. Refusing it in the server too would leave a command-line reader that ignores the
  `json sha256=` line reading the plant. What appears at the path during the run is replaced, as
  it always was.
- **Judge by the first member alone** (the first form of this change). A log of reports appended
  one per line (`jq -c . >> reports.jsonl`) starts the way a report does, and a mistyped `--json`
  would lose every report in it.
- **Refuse an empty file too.** It would keep an empty `__init__.py` or `.gitkeep` named by
  mistake, and refuse the path `mktemp` hands a script; the owner kept the empty file removable
  (2026-10-11).
- **Open the parent directory once and do every step through that descriptor.** Whoever can
  swap a directory on the path can already remove what is under it, judged or not; the check
  stops a mistyped path, not a process with write access to the directory, and the documentation
  says so.
- **Let a name whose kind cannot be read through, removing nothing.** On a kernel without
  `statx` every name reads that way, and the temporary file and the rename need no `statx`, so
  `replay case.json --json case.json` would still overwrite the case there. Refusing costs a run
  that names a path under a directory it cannot search, whose report could not have been written
  either.

## Consequences

- What used to run and now refuses: a `--json` naming a symbolic link (one to a report included —
  the link used to be replaced), a directory, a FIFO, a device (`/dev/stdout` and, for a user other
  than root, `/dev/null`, which used to run to its verdict's exit code with `sha256=none`), a
  non-empty file Sideeye did not write — a log of reports appended one per line among them — a
  report that cannot be read, and a path whose kind cannot be read. A CI step that gated on
  the exit code of a run whose `--json` named one of these now sees 3. The message names the path
  and says to name a new one or move that one away.
- When the refused thing is itself an old report — a link to one, or one that cannot be read — it
  stays at the path; the absent `json sha256=` line is what says it is not this run's. An old
  report in a directory the run cannot write was never removed, before this change or after; that
  run prints `json sha256=none`.
- A temporary file is left beside the path only if the engine dies between creating it and
  renaming it; the old fixed name was overwritten by the next run, a random one is not.
- Sending the report to standard output means writing it to a file and reading that.
