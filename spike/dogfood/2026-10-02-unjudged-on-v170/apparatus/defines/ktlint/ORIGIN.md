# ktlint — origin

Copied byte-for-byte from `spike/dogfood/2026-09-22-shipped-v160/apparatus/defines/ktlint/`
— its `seed.sh` and `sideeye.toml`, which are the **second** define (`Main.kt`), the one that
cleared the gate. That directory's `seed.r1.sh` / `sideeye.r1.toml` hold the first define
(`a.kt`) and were not copied. Already in this run's format. Not measured here.

## Which form is which

`SELECTION.md` ("ktlint's first define ran `ktlint -F a.kt`; ktlint exits 1 on a violation
it cannot auto-correct, and `a.kt` breaks its own `standard:filename` rule … the fixture was
renamed `Main.kt`, and `sideeye.r1.toml` keeps the first") and `RESULTS.md` ("ktlint's
`-F a.kt` exited 1 on its own `standard:filename` rule"). The first define's gate answer is
`transcripts/entry/ktlint-define1.preflight.txt` (`UNKNOWN recording_run_failed`, exit 1
where 0 was expected; the hand run is in `transcripts/checkers-ktlint-interpreters.txt`).
The copied `seed.sh` writes `Main.kt` and the copied `sideeye.toml` runs
`/opt/ktlint -F Main.kt`, matching the `next` line of `transcripts/entry/ktlint.preflight.txt`.

## Tool and engine at the time

ktlint 1.8.0, the release asset installed at `/opt/ktlint` (the operation names that absolute
path), `2026-09-22-shipped-v160/apparatus/Dockerfile` line 36, on Debian trixie's
`openjdk-21-jre-headless` (line 18):

```
RUN curl -fsSL -o /opt/ktlint https://github.com/pinterest/ktlint/releases/download/1.8.0/ktlint && chmod 755 /opt/ktlint
```

`/opt/ktlint` is a `#!/bin/sh` script that goes on to run `java`
(`transcripts/checkers-ktlint-interpreters.txt`).

Engine: the released Sideeye v1.6.0 (`trace contract v18`), installed by the page's installer
at `/opt/se/sideeye-v1.6.0-aarch64-linux/sideeye` (`transcripts/entry/engine.txt`). Box run
with `--network none --cap-add SYS_PTRACE` (`transcripts/commands.txt`).

## Why it was not explored

The second define cleared the entry gate: `sideeye preflight --twice --oracle
/usr/bin/strace`, default observation mode, "recording accepted — 2 state-changing
operation(s)", the oracle agreeing on 2, 21 other processes observed and none touching the
state, two runs 2004 ms apart leaving equal state, one writing thread
(`transcripts/entry/ktlint.preflight.txt`, `ktlint.threads.txt`; row in
`transcripts/entry-candidates.txt`, `gate=0`). Left out of the slate by that campaign's
choice (`RESULTS.md`, `SELECTION.md`). No refusal and no `unknown_reason` exist for the
second define.

## Changed from the original

nothing. (`2026-09-28-shipped-v170/apparatus/run.sh` reads a define the same way
`2026-09-22-shipped-v160/apparatus/run.sh` does; see `../eslint/ORIGIN.md` for what differs
between the two scripts.)
