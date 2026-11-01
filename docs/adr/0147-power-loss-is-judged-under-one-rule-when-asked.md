# 0147 — Power loss is judged under one rule, when asked

- **Status:** Accepted (2026-11-01)
- **Refs:** #960; the owner's ruling on 2026-11-01, after reading #958's table, to take the rule up
  as a mode that is off by default; ADR 0110 (power loss is not the next crash model yet), whose
  first reopen condition #958 measured
  ([`RESULTS.md`](../../spike/dogfood/2026-11-01-power-loss-rules/RESULTS.md)); ADR 0144 (the
  `syncs` account line).
- **Scope:** `src/syncs.zig`, `src/oracle.zig`, `src/cli.zig`, `src/main.zig`, `src/report.zig`,
  `src/case.zig`, `src/evidence.zig`, `docs/cli.md`, `DESIGN.md`, `docs/report-schema.md`,
  `docs/contract-freeze.md`, `docs/faq.md`, `spike/acceptance.sh`, `spike/toys/toy_power_loss.py`.

## Context

ADR 0110 declined power loss as the next crash model for two reasons: no rule had been shown to
separate targets rather than fail nearly all of them, and the answer depends on the filesystem.
#958 re-recorded 46 supported-class PASS rows under strace and measured two rules. "Anything
unsynced is lost" sends nearly every row back whole to before the operation and fails almost
none. "A rename persists before its data" separates them: 19 of the 46 rename a file into their
state with no sync of it first, and 27 do not. The second reason stands — ext4's
`auto_da_alloc`, for one, flushes a file's data before a rename that replaces an existing file,
and does nothing for a rename onto a new name, and other filesystems answer differently again.

## Decision

- **One rule, off by default.** `sideeye explore --power-loss rename-before-data --oracle
  <strace>`, on Linux. Without the flag nothing is built and no verdict changes; the run's
  `crash_model` stays `"process-kill"`, which still names how every crash world was made.
- **The world.** At each crash point *k*, and after the operation, the engine takes the state the
  kill left and replaces the content of each candidate's new name with what the file held before
  the run: the source path's content in the initial state, when the run neither truncated it
  (an `O_TRUNC` open, read from strace, or a `truncate`), nor removed, renamed away, replaced or
  linked over it or a directory above it before the rename, and nothing otherwise. A world identical to the kill's own is not judged
  twice. The checker, L0 and — where the kill's world saw the marker — L1 judge it, with no
  re-run of the target.
- **The candidates.** A rename into the judged state (scratch excluded) of a file with a write
  recorded at its source path, with no `fsync` or `fdatasync` recorded for that path anywhere in
  the run, a source that is not a symbolic link, applied at crash point *k* when the rename is
  numbered below *k* and nothing — a write, truncate, sync, rename, link or removal of the new
  name, or a rename or removal of a directory above it — has touched the new name between the
  rename and *k*. Crash points are the trace's numbers, never positions in it.
- **What is not recorded is not judged around.** The candidates come from the shim's record of
  the syncs, so the flag needs strace as the witness (`--oracle`, or one found on `PATH`), and refuses `--no-oracle` and `--allow-unverified`. Under the flag strace
  also traces `sync`, `msync`, `io_submit`, `io_uring_setup` and `io_uring_enter`; a run in which
  strace saw any of those, `sync_file_range`, `syncfs`, an `O_SYNC` or `O_DSYNC` open that can write, a
  `pwritev2` with `RWF_DSYNC` or `RWF_SYNC`, or an `FS_IOC_FIEMAP` asking `FIEMAP_FLAG_SYNC`
  anywhere builds no power-loss world and names each call and its file in the report.
- **Whether an open truncated** is strace's to say, and is matched with the shim's record by
  position among that path's opens that can write. A file whose opens do not match, or a run with
  a truncating open strace names by no absolute path, leaves each candidate that would hold what
  it held before unjudged, and the report counts them: an unknown truncation is a world not
  built, never one guessed. A sync travels with its file through renames and ends at an unlink,
  so a second file under a synced temporary name is still a candidate.
- **A failing world is a FAIL that names the rule**: the headline counts the two kinds of world
  apart, `earliest` says the world was a power-loss one, the JSON's `earliest.crash_model` carries
  the rule, and its `reproduce` line is the replay. At one crash point the kill's own world comes
  first. `checker_earliest` is drawn from the kill's worlds only.
- **The case is version 8**, written only for such a FAIL: version 7's fields, every one spelled,
  and `crash_model`. Its crash point may be one past the last operation, for the world built after
  it. Replay rebuilds the candidates from its own recording, and needs strace as explore does;
  `--leave-crash-state` leaves the power-loss world.
- Refused beside it: macOS, where an `fsync` does not reach the device and `F_FULLFSYNC` is a
  separate call; `--recovery`, because what a recovery is held to after power loss is not
  decided; `replay`, which takes the rule from the case; and `preflight`, which judges no world.

## Alternatives considered

- **On by default.** Rejected: the answer depends on the filesystem, and a PASS that turns into a
  FAIL for a reason the user's filesystem does not have would leave them nothing to act on.
- **Each file back to its content at its last sync.** Rejected: a replay runs one world, not the
  ones before it, so it could not rebuild that content, and the content would come from a
  different run's bytes. Of the 19 candidates #958 measured, every one is a file the run never
  synced, so the narrower rule loses none of them.
- **"Anything unsynced is lost".** Rejected by #958: it fails nearly none.
- **Re-running the target in the composed world.** Rejected: the world is the state after the
  crash, the checker is what reads it, and a re-run would cost a world each for nothing judged.
- **A `--crash-model` flag with a default.** Rejected: it reads as though the process kill could
  be swapped out, which nothing here does.

## Consequences

- A tool that writes a temporary file and renames it over its state with no sync can now be shown
  failing, when asked, and the case reproduces it; #958's candidates python-dotenv, perl `-i` and
  ziptool FAIL under the flag, and juju and samtools, which sync, PASS.
- The rule is POSIX's minimum, not ext4's: on ext4 with `auto_da_alloc`, a rename that replaces a
  file is flushed first, and a FAIL found there is a world that filesystem does not leave. The
  FAIL names the rule so that the reader can weigh it.
- What the world does not model: a rename whose own directory entry is lost (the rename undone),
  torn writes, a file synced partway through the run and written after, hard links of the renamed
  file, and a file renamed on again, which is judged only until its second rename. Each leaves out
  a world power loss can leave; none adds one it cannot, under the rule.
- A replay without strace refuses: it could not tell a truncating open from another.
