# 0068 — The eval container's outputs arrive sealed, on the container's own stdout, and the judge reads nothing else

- **Status:** Accepted (2026-09-16)
- **Closes:** #597, the residual ADR 0066 named ("inside the container the agent-built `timew` runs
  under the sealed `sideeye` as the same uid, and `sideeye` writes its replay JSON into the directory
  that binary can write").
- **Scope:** `src/report.zig` (`writeJsonReport`, `jsonFailed`), `spike/container_seals.py` (new),
  `spike/loop-closure-timew/judge.sh` (`cmd_eval`, `selftest`, the header's trust list),
  `spike/loop-closure-timew/measure.py` (the digest lists), `docs/cli.md`, `CHANGELOG.md`.

## Context

`judge.sh eval` builds the agent's `repo/` in a `--network none` container and runs the sealed
`sideeye replay` over the binary it built. Since ADR 0066 the container mounts the stage read-only
and exactly one directory read-write, `<mode>-container-out/`, into which `sideeye` writes
`<mode>-replay.json` and the shell writes the rc, the functional gate's status and its export. The
judge's python read those files after the container exited and derived `replay.gate` and
`func.gate`, two of the three gates `loop_closed` is the conjunction of.

The agent-built `timew` runs beside them as the same uid (root), with that directory writable, and
nothing stopped it from outliving `sideeye`: a `timew` that forks a child, or one forked during the
functional gate, is alive until the container's shell exits. In that time it can rewrite
`run-replay.json` as `"verdict": "PASS"`, `run-replay-rc` as `0`, `run-func-status` as `ran` and the
export as a passing one — and it does not have to win a race to do it: a child in a loop that keeps
overwriting the file is the last writer whenever the reader arrives. Measured on the controls, not on
a hostile binary: the honest `timew` writes nothing there (#597).

Two reviews of the plan removed four designs before any code, and the four fall on one line —
every one of them let something the subject could reach stand between the writer and the reader:

- The shell taking a `sha256sum` of the report after `sideeye` exits, or after killing every other
  process first. Both certify the last writer's bytes; a loop is always the last writer, and
  shortening the window does not change who is last.
- The judge counting a token only at a line start. A subject that writes bytes with no newline
  ahead of the real token takes its line start away; if it then writes its own token from a fresh
  line, the anchored reader sees exactly one — the forgery — and a rewritten file matches it.
- `tee | sha256sum` to seal the export. Both binaries live on the container's writable root
  filesystem, on a `PATH` whose first entry the agent's `CMakeLists.txt` can populate during
  configure, as root. So does everything else there — which is the residual below.
- Two streams. Docker multiplexes a container's stdout and stderr as separate frames and the CLI
  writes both into the one file the judge reads; a write that straddles a frame boundary can have a
  frame of the other stream land inside it, and the subject can flood stderr to arrange that. A
  90-byte write is indivisible on the pipe, not on the far side of docker's shim.

## Decision

### 1. `sideeye` seals its own report, in one write, and always exactly once

When `--json` names a path, `writeJsonReport` computes the SHA-256 of the bytes it wrote — the
buffer, not a re-read of the file, which by then is in a directory somebody else may write — and
records `sideeye: json sha256=<64 hex>;\n` and `report.emitSeal()` writes it to stderr in a single
`write()` at the exit; `jsonFailed` records the `none` form the same way after its diagnostic.
**Recorded rather than printed on the spot, and that was found by running the suite**: the two
refusal paths write the JSON *before* their text, so printing in place made the token the first
line of a run's output, and `spike/acceptance.sh`'s CLI self-description check -- which reads the
first line of each flag probe -- went red. `emitSeal` is called immediately before each of the five
exits that can follow a report (`refuse.unknown`, `refuse.setupError`, and main's PASS, PASS and
FAIL), so the token is the last thing sideeye writes on every path and a reader of the first line
sees what it always saw. So a run that reached the report stage
produces exactly one token whether or not the file landed (`preflight` refuses `--json` before the
path is recorded, so that refusal carries none): "no token" cannot be arranged by making
the write fail (a directory planted at `<path>.tmp` does that on demand), and "one token" is never a
forgery standing alone. One write because a write of at most PIPE_BUF bytes is not interleaved with
another writer's on a pipe; the token is 87 bytes, pinned by the test, which also holds it under 512 -- the
smaller of Linux's and macOS's PIPE_BUF. The line is not part of the report schema, and stderr's prose is not a
frozen surface (docs/contract-freeze.md); `docs/cli.md` documents it beside `--json`. Under the MCP
server it reaches neither the server's stderr nor the tool's text block: `runChildCaptureMinimalEnv`
redirects the child's stderr into that call's capture file (`dup2(1, 2)`), and the text block is
built from the report. Said here because the first draft of this ADR claimed the opposite.

### 2. The container's shell puts every other value on the same stream, with builtins only

The container script begins with `exec 2>&1`: one stream, so docker's frames only ever concatenate
and sideeye's stderr — the seal — is on it. The rc and the functional gate's status are `printf`
tokens with a terminator (`judge: replay-rc=1;`); the export is received by the shell
(`fexport=$(... timew export)`) and printed between two markers, so the judge reads the bytes the
shell saw and not a file. Measured: dash emits that block in one `write` up to 8 KiB and in
three at 64 KiB, while PIPE_BUF here is 4096 — so only a block under 4 KiB is indivisible on the
pipe. A larger one can be interleaved, and what holds it then is that each marker must appear
exactly once and the body must parse as JSON, so an insertion refuses rather than being read as
the export. Every external binary the script needs (`mkdir`, `cp`, `cmake`, `git`)
runs before the subject does; after its first run the script uses builtins and the sealed `sideeye`
on the read-only stage. The host captures the container's stdout into `<mode>-container.log` and
its stderr — the docker CLI's own — into `<mode>-container.err`, so nothing but the container's one
stream is in the file the judge reads. The files beside the tokens are still written, for a person
reading the run; the judge does not open them.

### 3. The judge reads tokens by one rule: counted anywhere, exactly one

`spike/container_seals.py` — executed from its bytes like `replay_gate.py`, and listed in
`measure.py`'s `code_paths` so the launcher digests it before the step — counts each token's prefix
wherever it appears in the stream and refuses on 0 (`seal_missing`) or more than 1
(`seal_ambiguous`). Hiding the real token behind newline-less bytes leaves it at 1; adding a forgery
makes 2; killing `sideeye` leaves none; each ends in a refusal and none in the forgery being read.
The report file is opened `O_NONBLOCK | O_NOFOLLOW`, must be a regular file by `fstat`
(`not_a_regular_file` for a FIFO, a link, a directory — a FIFO planted at the name would otherwise
block the open with no writer to ever unblock it; `unreadable` when the open fails for a reason
that is not the kind of the thing at the name) under a 64 MiB cap (`too_large`), read once, and
the same bytes are hashed and parsed (`seal_mismatch` — which is also where a file that is simply
gone lands, since there are then no bytes to be the sealed ones — and `not_json`). The stream is
read the same way, under a cap of its own (512 MiB): it is the ground every token stands on, and
it is the side the subject can append to for as long as the container lives, so capping only the
file would have left the more exposed side uncapped (found in review). A channel that does not seal
lands in `run-verdict.json` as `replay.gate` / `func.gate` with its reason, and the replay gate and
the functional predicate never see a document for it. The functional gate's export is parsed only
when the status token says `ran`.

### 4. What the launcher holds

`run-container.log` joins `STEP_EXTRA["eval"]`, so `finalize` holds the ground the run verdict stood
on; the two controls' logs join `pre_run_inputs`, as their verdicts already did. The disk-read window
ADR 0066 named for `replay_gate.py` — the launcher digests the module when the step begins and the
judge reads it from disk after the container — is inherited by `container_seals.py` unchanged; what
this decision adds is the module to the list, not a closing of the window.

## Alternatives considered

- **Digest by the shell after `sideeye`, with or without killing every other process first.**
  Certifies the last writer (Context). Killed in R1; R1 itself withdrew the kill-first variant.
- **The subject under another uid** (the issue's second option). `sideeye` does not drop privileges
  for the operation, so the uid change would go into the operation string — which the sealed case
  records, so the case's meaning changes.
- **The judge reading the text report.** `--json` exists so that a machine does not branch on prose
  the freeze lets move between releases.
- **`tee | sha256sum`** for the export. The binaries are the agent's to replace (Context); builtins.
- **A second container for the measurement, `--read-only --tmpfs /tmp`.** The right direction for
  the root-filesystem residual below, and the reason it is not in this change: `--tmpfs /tmp` moves
  the observed directory (`/tmp/loop-state`) onto another filesystem, and `stage.sh` says of that
  directory that "its syscall semantics must not ride a virtiofs mount" — the filesystem is the
  measurement's ground, and moving it means re-measuring the two controls against the sealed case.
  That is its own promise and its own change.
- **`bytes=<n>` in the token.** Variable width for nothing the digest does not already cover.

## Consequences

- A functional gate whose export is empty now refuses the channel (`not_json`, naming the
  emptiness) where the file-reading form read it as an empty list and a plain functional `fail`.
  Both are non-pass, so `loop_closed` is unmoved; the sentence the reader gets changes.
- `judge.sh selftest` grows by six refusals to seventy (`seal-missing`, `seal-ambiguous` — the
  hidden-then-forged stream — `seal-mismatch`, `seal-fifo`, `seal-large`, `seal-notjson`) and one
  green to twenty-four (`seal-clean`); `WANT_CASES` is 94. Each refusal has a mutation of
  `spike/container_seals.py` in `seal-reds/MUTATIONS.md`, including `seal-anchored`, which puts the
  line-anchored count back and is killed by `seal-ambiguous` alone — the review's hole, held shut by
  a case. `container_seals.py --selftest` runs in `spike/acceptance.sh` beside `replay_gate.py`'s
  (check 11h, seen red once against a copy whose `not_json` branch returns `sealed`). Eight
  mutations of the module are recorded in `seal-reds/`; seven kill the case they name, and
  `seal-none-blind` kills none — the judge's selftest has no case for sideeye's `none` token,
  so that branch is held by check 11h alone, which is said here rather than left to be found and `measure.py --selftest` carries a stand-in for the module.
- A stage sealed before this change carries a `.harness/sideeye` that prints no token; its `eval`
  refuses every channel with `seal_missing`. Stage again.
- `<mode>-replay.txt` is now sideeye's stdout alone; its stderr is in `<mode>-container.log`, which
  is where a refusal's reason is read. `stage.sh`'s `explore.txt` still holds both.
- **Named residual, and a separate promise — the measurement's root filesystem.** The subject is
  uid 0 on a writable rootfs, and after it first runs everything the judge's tools load from there
  is its to replace: `/usr/bin/strace` (the oracle), the `sh` the checker runs under, `libc` — and
  with `libc`, every dynamically linked binary exec'd afterwards, the sealed `sideeye` included
  (the harness build targets `aarch64-linux-gnu`). The seal says the file the judge opens is the
  one `sideeye` wrote; it does not say `sideeye`, its oracle or the checker ran on a pristine image.
  Filed as its own issue; the read-only measurement container above is the candidate, gated on the
  two controls reproducing at `case_k` over whatever `/tmp` becomes.
- Also outside the set, said rather than implied: the secondary observation's container outputs
  (explore report, four upstream suites' rc and text — read from files the agent-built binaries can
  write; evidence, not a gate); the functional gate's export is the subject's own output, so a
  `timew export` that prints a lie passes the non-degeneracy gate with or without the seal; a child
  of `timew export` that holds the pipe the shell reads stalls the gate — a stall, not a verdict,
  and the same class as an operation that never exits; and the milliseconds between a step writing
  its output and the launcher hashing it (ADR 0066).
- **Measured before shipping:** see the PR body's Verified section — the two controls under the
  re-staged harness, the case's bytes across the re-stage, the two hostile `timew` toys, and the
  stream measurement under a stderr flood with and without `exec 2>&1`.
