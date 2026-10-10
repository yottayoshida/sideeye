# Contributing

Sideeye judges itself by what happens when people outside this repository run it. A report from you is that judgement, so this page is mostly about what makes one useful.

## Reporting what Sideeye did on your tool

Open an issue and pick one of the two forms:

- **UNKNOWN or SETUP ERROR** — Sideeye would not judge your tool (exit 2), or could not run your define (exit 3). The `--json` report's `unknown_reason` or `setup_error_reason` is where we start; an UNKNOWN also prints it on its first line, a SETUP ERROR only a sentence.
- **A verdict** — Sideeye found a real bug in your tool, or you believe a PASS or a FAIL is wrong.

A useful report carries:

- the version, from `sideeye version`;
- the platform — OS and its version, CPU, and on Linux the libc — and whether it ran in WSL or in a container;
- how Sideeye was installed;
- the command you ran, with every flag, and the file `--json <path>` wrote; if none was written, the text output;
- for a verdict, the define and the check, so the run can be repeated.

The report carries your paths, the directory you ran in, your define's commands and `apparatus` values, and strings your tool wrote. Read it before you paste it.

**A FAIL that is right is a bug in the tool you tested, not in Sideeye.** Report it to that project — `sideeye evidence <case>` renders the saved case as Markdown for its tracker — and then tell us with the verdict form, linking your report. We would rather know than not. **A PASS you believe is wrong** is the worst failure this project can have; report it even if you are unsure.

A vulnerability in Sideeye itself goes through [SECURITY.md](SECURITY.md), privately, not through an issue.

## Reports written with a language model

Welcome, on three conditions: say that a language model wrote it (both forms ask; anywhere else, say so in the text), attach the report from a run you made yourself together with the version, and read every word before you file. A verdict comes from the report, not from the prose around it, so a claim the attached report does not show will be answered by asking for the report that does.

## Pull requests

- On every pull request CI builds and tests on Linux and macOS, and runs the acceptance suite on Linux. Locally, `zig build test` with the Zig release `build.zig.zon` names as `minimum_zig_version`; a newer release is not promised to build it.
- Anything a user would notice gets an entry in `CHANGELOG.md` under `[Unreleased]`.
- A decision that outlives the pull request is a new file in `docs/adr/`, written `Accepted`. [CLAUDE.md](CLAUDE.md) holds the rest of the conventions CI checks, including how ADRs are numbered.
- Everything committed is in English.
