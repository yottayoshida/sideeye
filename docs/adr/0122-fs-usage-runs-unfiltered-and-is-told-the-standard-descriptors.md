# 0122 — fs_usage runs unfiltered, and the reader is told where the standard descriptors point

- **Status:** Accepted (2026-10-11)
- **Refs:** #796 (GNU `dd of=` under `--oracle-fs-usage` is UNKNOWN `oracle_saw_nothing`, met in
  the #697 platform probe, ADR 0105); ADR 0031 and ADR 0060 (the fs_usage oracle and its
  single-process claim); ADR 0005 (the default mode's stdio granularity).
- **Scope:** `src/main.zig` (the fs_usage launch, the overrun refusal), `src/fsusage.zig` (the
  descriptor table: the standard descriptors, `dup`, `dup2`, `accept`, `socket`; where fs_usage's
  stderr goes), `src/posix.zig` (`spawnSidecar`'s stderr, `pathOfFd`). macOS, under
  `--oracle-fs-usage` only.

## Context

`docs/cli.md` said a single-process run whose state writes come from one recorded thread is
explored and judged under `--oracle-fs-usage` as under `--oracle`. Measured on GitHub's macOS 26
runner before this change (run 38115178676), it was not, for any target that writes its standard
output: a toy that writes its state file and prints `done`, a toy that moves the state file onto
descriptor 1 with `dup2` the way GNU `dd` moves `of=`, its control moving an outside file there, and
`gdd` itself were all refused `oracle_saw_nothing` on their first `write F=1`.

Two causes, both read from the capture and from `fs_usage.c` (apple-oss-distributions/system_cmds
`e0c267e8`):

- `-f filesys` prints no `dup` or `dup2` — `check_filter_mode` tracks them for its own descriptor
  state and returns false — so a moved descriptor is, to the reader, a number nothing opened.
  Without a class filter fs_usage prints them as `dup2  F=<old>  F=<new>`, measured.
- The engine hands the subject its stdout capture and stderr with `dup2` in the child before the
  `exec`. Even unfiltered, those lines carry the pre-exec thread's id, and the subject's lines after
  the `exec` carry another (`launcher.19581` then `dup2_toy.19582`, measured): the reader keys a
  process's descriptors by the subject's thread, so nothing in the capture can tell it where 0, 1
  and 2 point.

## Decision

1. **The engine tells the reader.** Descriptor 0 is `/dev/null`; 1 is the recording's stdout
   capture; 2 is the engine's own stderr, inherited — a regular file is placed by `F_GETPATH`, and
   anything else (a terminal, a pipe) cannot be a state file. Each is entered in the subject's table
   as inside or outside the state, or left unknown when its path could not be read.
2. **fs_usage runs without a class filter**, and the reader follows `dup` and `dup2`: the new number
   takes the old one's scope, and becomes unknown when the old one is unknown, rather than keeping
   what it named before. `socket` and `accept` print the new descriptor, which is outside the state;
   without a filter a socket's `write` is printed too, and would otherwise be a write on an unknown
   number.
3. **fs_usage's stderr is kept**, beside the capture, and a run whose stderr reports a
   `buffer overrun` is refused `oracle_saw_nothing`: an event fs_usage dropped is an operation
   neither account holds.

1 and 2 ship together. With the standard descriptors known and `dup2` still invisible, a state file
moved onto descriptor 1 would be taken as the capture, and a write through it that the shim did not
record — macOS's stdio flushed at exit is one — would fall out of both accounts, where today it
refuses.

What the unfiltered capture costs was measured over the same window on the same runner: 161,992
lines against 144,852 with the filter (+12%), no overrun notice either way. The calls it adds are
`dup` and `dup2`, the network family, disk-I/O lines, and attribute writes; in the four explorations
run with it, no line failed the reader's grammar.

## Alternatives considered

- **Narrow `docs/cli.md` to say these runs are refused.** The owner chose to follow them
  (2026-10-11); the measurement showed the refusal reached every printing target, not only `dd`.
- **Recognise a dup from lines the shim would emit** (an `fcntl` pair around each `dup2`). A protocol
  between shim and reader built from lines any target can print, and `dup2` would have to be
  emulated non-atomically to produce it.
- **Infer descriptors 1 and 2 from the pre-exec `dup2` lines.** Their thread is not the subject's,
  measured; and the capture file they duplicate was opened by the engine's parent, before the fork.

## Consequences

- The four shapes above are judged on GitHub's macOS 26 runner: the printing toy, the `dup2` toy and
  the outside control PASS with `oracle_verified: true`, and the probe's `gdd` rewrite FAILs with a
  verified oracle (run 38116040180). The fs_usage acceptance suite holds the three toys (check 9).
- A descriptor the reader cannot place still refuses: a pipe or `socketpair` the target makes
  itself (fs_usage prints no number for either), a `dup2` from a number the capture never saw
  opened, and an absolute path the reader places by its text — it does not resolve `..` in one,
  so `state/../outside` reads as the state's and refuses.
- Calls the filter used to hide on a state file now reach the reader. Read from the reader, not
  measured on a target: an attribute write on one (`setxattr`, `removexattr`) refuses as an
  unmodelled call, as it does under strace (#684), where before fs_usage did not print it; the
  ownership, mode and timestamp calls are counted as metadata, as they were whenever printed.
