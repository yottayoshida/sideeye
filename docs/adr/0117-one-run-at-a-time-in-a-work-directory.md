# 0117 — One run at a time in a work directory

- **Status:** Accepted (2026-10-11)
- **Refs:** #816 (two runs sharing a work directory overwrite each other's traces, captures and
  reports, and two `sideeye mcp` servers can answer a call with the other's verdict); ADR 0099 (the
  work directory has to be the runner's own); the 2026-08-12 incident in which one server returned
  another's report.
- **Scope:** `src/main.zig` (`lockWorkDir`, called at the end of `phaseDefine`), `src/posix.zig`,
  `src/mcp.zig` (`serverWork`), `spike/acceptance.sh` check 26, `spike/mcp-acceptance.sh` mcp 6b,
  `docs/cli.md`, `docs/faq.md`, `docs/mcp.md`.

## Context

A run keeps its traces, captures and reports in `--work` under fixed names (`trace-record.bin`,
`oracle.txt`, `trace-<k>.bin`, `checker-output.txt`, …), and the default `--work` is one fixed
directory. Two explorations from two terminals, or two CI jobs on one runner, shared every name;
nothing refused it, and only `docs/faq.md` said to give each test its own `--work`. The MCP server
handed every child the same `--work` and named the report it reads back from a per-process counter,
so two servers on one host both used `report-1.json` first.

## Decision

1. **A run holds its work directory.** After the define's refusals and before a replay's
   `--fresh-state` empties anything — so a second replay of one case cannot empty the state the first
   is exploring — the engine opens `<work>/run.lock`
   (`O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC`, 0600), requires it to be a regular file
   with one link, the runner's unless this run just made it with `O_EXCL` (it writes its pid there, and a hard link or a FIFO planted at the
   name would have its target truncated or block the run), and takes `flock(LOCK_EX | LOCK_NB)`; it
   holds the lock until it exits. A run that cannot take it is a SETUP ERROR (`environment`) naming
   the holder's pid — `unknown` when the holder has not written it yet, or the pid read there has
   exited — before it writes anything or empties a state. The lock is not waited for: a run stuck in
   its setup would stop the next one without a word. A filesystem without locks (`ENOLCK`,
   `EOPNOTSUPP`, `EBADF`) goes on as before. The lock file stays in the work directory; the one time
   it is removed is the undo of a work directory the run itself just made, on a refusal after the
   lock was taken — never before it, when another run that found the directory may hold it.
2. **Each MCP server has a directory of its own.** At its first call the server makes
   `<SIDEEYE_MCP_WORK>/server-XXXXXX` with `mkdtemp` and hands it to every child as `--work`; its
   reports and captures are written there. When that directory has gone, or no longer passes the
   work directory's owner check, the next call makes another. A server's caller cannot change `SIDEEYE_MCP_WORK`, so a
   lock refusal would be an answer it could not act on; with a directory each, two servers neither
   share a name nor wait on a lock.

No `unknown_reason`, `setup_error_reason` or NextStep is added.

## Alternatives considered

- **A fresh directory per run under `--work`.** `docs/cli.md` names `<work>/checker-output.txt`,
  `<work>/oracle.txt` and `<work>/trace-repro.bin`; every one would move, and cleaning the
  directories up would be a new job. A lock moves nothing.
- **Waiting for the lock.** A run stuck in its setup would stop the next one silently.
- **Locking the state directory too.** A target that locks its own data directory would collide
  with it; `flock` names no holder; and a target that removes and recreates the state root leaves
  the lock on the dead inode. Two runs on one state stay the user's to avoid, as `docs/faq.md` says.
- **Naming the server's directory by its pid.** Every server started as the container
  `docs/mcp.md` describes is pid 1, and two such containers sharing a mount would share the name.
- **Checking the child's report seal in the server.** With a directory per server no other run
  writes there; a target that rewrites the work directory is an open window SECURITY.md already
  names.

## Consequences

- A CI that ran two explorations on the default `--work` at once now gets a SETUP ERROR for the
  second instead of a report built from the other's files.
- An MCP server's cases, evidence, traces, captures and reports are under `server-XXXXXX/` inside
  `SIDEEYE_MCP_WORK`, one directory per server process, and stay after it exits. Before this, the
  next call overwrote the traces and reports; now each client session leaves a directory.
