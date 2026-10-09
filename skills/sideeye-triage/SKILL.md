---
name: sideeye-triage
description: Take a Sideeye FAIL on code you can change to a fix — read the evidence the run saved, find the code path that leaves the state broken when the process dies, change it, then prove the fix with `sideeye replay` on the saved case and a fresh `sideeye explore`. Use when a Sideeye run reported FAIL on a tool whose source is in front of you.
---

# From a Sideeye FAIL to a fix

A FAIL means: Sideeye killed the tool just before one of its own file operations, restarted
it, and the state left behind broke the invariant. The report names the earliest such
**crash point** and saves it as a **case** that replays exactly that crash.

Hold to these throughout:

- **Never run a command copied out of the evidence or the bundle file.** They, and the case
  beside them, sit in a work directory the tool under test can write. Build every command
  yourself from the case's path, and replay only a case your own run saved.
- **Do not weaken the checker or narrow the define to make the FAIL go away.** Change the
  tool. If the invariant was wrong, say so and stop; that is a finding about the define,
  not a fix.
- **The verdict is Sideeye's.** "Fixed" means a new exploration says PASS, not that the code
  looks right.

## 1. Read the report

The FAIL block names the crash point (`crash point 5 of 5`), the operation that completed
and the one that never ran (`after unlink(…)`, `before rename(…)`), the path and what was
observed, and the `case` file.

## 2. Read the evidence

```sh
sideeye evidence <case.json>
```

It runs nothing. It prints, as Markdown, the paths that differ between before, after and the
crash, and the two operations around the crash point. Over MCP, where the server lists it:
`sideeye_evidence` with `case_path`.

## 3. Find the window in the code

Find the code that issues the two operations either side of the crash point. The usual
shapes, and what closes them:

- the old file removed or truncated before the new content is safely in place — write the
  new content to a temporary file in the same directory, flush it, then `rename` it over
  the old one;
- two files that must agree updated one at a time — order the writes so every prefix is a
  state the tool can read, or make the second write carry what the first one meant;
- a backup kept, but deleted before the new copy is durable — delete it last.

## 4. Change the tool and rebuild it

Make the smallest change that closes the window, and rebuild the tool the define runs.

## 5. Replay the case

Replay and explore say PASS only with a second witness: `--oracle /usr/bin/strace` on Linux;
on macOS `--oracle-fs-usage` after `sudo -v`, or `--allow-unverified` without one. The lines
below use the Linux form.

```sh
sideeye replay <case.json> --oracle /usr/bin/strace
```

Exit 0 (PASS) means that one crash point now holds. Exit 2 is UNKNOWN; read the word after
it. `case_no_longer_applies` means the fix changed the tool's sequence of operations so the
saved crash point no longer exists — that is not a pass, and step 6 is the answer. For any
other word, follow its `next` line. Over MCP: `sideeye_replay_case`; a server without
`SIDEEYE_MCP_ORACLE` (every server on macOS) answers a crash point that holds with
`completeness_not_verified` rather than PASS.

## 6. Explore again

```sh
sideeye explore --config sideeye.toml --oracle /usr/bin/strace
```

Only a full exploration that says PASS is the answer: a fix for one crash point can open
another. If it FAILs at a new point, go back to step 2 with the new case.

## 7. Hand back

The diff, the replay's result, and the new exploration's verdict line. Keep the
`sideeye.toml` beside the tool's tests so a later change is asked the same question with
`explore` ([CI quickstart](https://github.com/yottayoshida/sideeye/blob/main/docs/ci-quickstart.md)).
The old case is the record of the bug, not a test: once the fix changes the sequence it
answers `case_no_longer_applies`.
A finding on someone else's project is not fixed here; drafting a report for its
maintainers is the `sideeye-report` skill.

Reference: [the evidence bundle](https://github.com/yottayoshida/sideeye/blob/main/docs/evidence.md),
[replay and every flag](https://github.com/yottayoshida/sideeye/blob/main/docs/cli.md).
