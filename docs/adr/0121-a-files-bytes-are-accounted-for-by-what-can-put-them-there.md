# 0121 — A file's bytes are accounted for only by an operation that can have put them there

- **Status:** Accepted (2026-10-11)
- **Refs:** #814 (met in the 2026-10-11 survey: GNU `cp` 9.1 onto an existing file on btrfs and
  XFS, and an io_uring write, PASS 4/4 with `oracle_verified: true`); #405 and ADR 0032 (the
  per-path reconciliation, `state_changed_unaccounted`), whose §2 this narrows.
- **Scope:** `src/engine/snapshot.zig` (`reconcile`), `src/refuse.zig` (`reconcileOrRefuse`, the
  refusal's sentence), `src/main.zig` (the scratch declaration passed in) — both platforms, every
  observation mode, since the reconciliation reads the recorded account whatever recorded it; and
  `src/oracle.zig` (the clone refusal), Linux under `--oracle`.

## Context

The reconciliation asks, for every way the judged state differs between the recording's two
snapshots, whether a recorded operation names the path. ADR 0032 §2 let `open` count: a file
created by `open` and never written is a change its own record explains, and refusing it would be
a false refusal.

`open` explains a creation and a truncation. It does not explain bytes. GNU `cp` onto an existing
file opens it with `O_TRUNC` — recorded — and on btrfs and XFS fills it with `ioctl(FICLONE)`,
which the shim does not interpose and the oracle's syscall table reads as read-only. A write
submitted through io_uring reaches neither witness at all. In both, the file's new bytes arrive
through no recorded write, the `open` names the path, and the run is accounted for; the crash
points sit in front of the `open` and elsewhere, so no world holds the truncated file. Measured at
`e814b84d` and again at `f391d895` in `debian:bookworm-slim` (aarch64, coreutils 9.1, strace 6.1,
liburing 2.3): btrfs and XFS `cp`, the io_uring toy, a new file filled by a clone, and
`ftruncate(fd, 0)` followed by an io_uring write — each PASS with `oracle_verified: true`. The same
`cp` on overlayfs falls back to `copy_file_range`, which is recorded, and FAILs at the window
between the `open` and the write.

## Decision

A difference that leaves a regular file holding at least one byte is accounted for only by a
record that can have put those bytes there:

- a `write` (the shim records `copy_file_range`, `sendfile` and macOS's clone family as writes);
- the **destination** of a `rename`, never its source — moving `cfg` aside and putting new bytes at
  `cfg` through an unrecorded call would otherwise be accounted for by the move;
- the destination of a `link`, and its source only when a recorded write after the link names the
  other end — a write through the alias changes this name's bytes, and that write is what accounts
  for them; a write to that name before the link reached a different file.
  Unconditionally, the source would reopen the hole one `ln` earlier: `ln cfg cfg.orig` and new bytes
  at `cfg` from a reflink;
- a `truncate`, only when the file's final bytes are a prefix of its initial bytes followed by
  zeros, which is everything a truncate can leave. `ftruncate(fd, 0)` followed by bytes from an
  unrecorded call is not — unless those bytes are themselves a prefix of the old ones, which the two
  snapshots cannot tell from a truncate that cut the file there (Consequences).

Every other difference — a file left empty, a path removed, a directory, a symlink, a path the
define declares `scratch` — is accounted for by any record that names it, as before. Scratch stops
the built-in layers and nothing else (ADR 0043): a checker can still read a scratch path, so this
exception is a choice, not a proof. A define declares scratch the paths nothing depends on — a
cache, an editor's message file — and those are what a tool most often leaves for `exit` to flush;
holding them to the rule would refuse the run over a file no judgment reads. The owner chose the
exception (2026-10-11); what it leaves is listed under Consequences. So ADR 0032 §2 holds for what it was written for: a
file `open` created and never wrote is empty, and the `open` still explains it. The rename-in
umbrella (ADR 0032 §4) is untouched.

The refusal keeps its reason, `state_changed_unaccounted`; the closed set does not move. What moves
is which runs reach it: some that were PASS are now UNKNOWN, the fail-closed direction. The sentence
says "accounts for" where it said "names", since an `open` can now name a path and not account for
it, and says how many of the listed paths were named only by records that cannot write.

### The oracle refuses a reflink clone; it does not refuse io_uring

The reconciliation is per path, so a clone into a file a recorded write also names — the first
half written with `pwrite`, the second cloned in with `FICLONERANGE` — is accounted for, and the
world holding the torn file is never explored. Measured in the same container on btrfs: PASS with
`oracle_verified: true` from the subject, and with `oracle_verified_subject_only` when a shell runs
the tool as a child. The oracle sees the clone — `ioctl(4</…/key.bin>, BTRFS_IOC_CLONE_RANGE or
FICLONERANGE, …)` — and read it as read-only because `ioctl` is on that list. It now refuses
`FICLONE` and `FICLONERANGE` on a state descriptor as `unsupported_syscall_observed`
(`ioctl(FICLONE)`), before the read-only list and in the child branch as well (`#689`'s shared
mapping is the precedent: a tool a shell runs is a child). The request is matched by name, by
strace's `_IOC(…, 0x94, …)` fallback, and by number, and the destination is read from the first
argument alone: a clone out of a state file into one outside is a read. A whole-file clone that
failed with an errno raised before anything is remapped is not refused — GNU `cp` on overlayfs gets
`EOPNOTSUPP`, falls back to `copy_file_range`, and FAILs as it should — but any other failed clone
is, since btrfs can fail a whole-file clone, and XFS a range, after remapping part of it. A call strace split across two lines is judged on the
half that carries the result (a parent's `epoll_pwait` between them is enough to split it), and an
`ioctl` on a state file whose request cannot be read is refused rather than read as a read.

io_uring is the other call neither witness counts, and refusing a successful `io_uring_setup` was
the plan. Measured before doing it, outside Docker's default seccomp (which answers
`io_uring_setup` with `EPERM`): Node 20.19.2 sets up no ring, and Node 22.23.3 sets up three at start
— under `node -e 0`, and with `UV_USE_IO_URING=0` — while an asynchronous `fs.promises.writeFile`
still reaches the kernel as a plain `write`. Refusing the ring would refuse every Node 22 target on
a host that allows io_uring, for writes both witnesses see; the owner chose not to (2026-10-11). A
write through a ring stays a gap: refused by the reconciliation where nothing able to write names
the file, and by nothing otherwise.

## Alternatives considered

- **Stop counting `open` at all.** Refuses the file a target creates and never writes, the false
  refusal ADR 0032 §2 measured.
- **A table of every class against every kind of difference** (removal, kind change). Tightens
  cases nothing has been measured to slip through, at the price of false refusals nothing has been
  measured to avoid either.
- **Count `truncate` unconditionally.** Leaves `ftruncate(fd, 0)` followed by a clone, an io_uring
  write or a store through a mapping accounted for — the same hole one call later.
- **Refuse any successful `io_uring_setup` under the oracle.** Refuses every Node 22 target on a host
  that allows io_uring, measured above, for rings that carry no file write.
- **Make `ioctl` an allow-list of read-only requests.** Nothing has measured which requests real
  targets issue on state files; a named deny-list of the requests that put bytes there is what is
  known.
- **Record `FICLONE` as a write in the shim and judge it** (the macOS shim already does this for
  `clonefile`). Turns the btrfs `cp` into the FAIL it is, but interposes `ioctl`, which every
  process calls; the owner chose refusal (2026-10-11). It would not reach io_uring either way.

## Consequences

- The btrfs and XFS `cp`, the io_uring toy, the clone into a new file and both `ftruncate(0)`
  shapes are refused `state_changed_unaccounted` — except that under `--oracle` a run holding a
  reflink clone is refused before the reconciliation, as `unsupported_syscall_observed`; overlayfs `cp` and a libc write still FAIL, and a
  file created empty, truncated to empty, or cut short is still judged.
- A run whose bytes reached a file through a write the default mode deliberately leaves unrecorded
  — a stream left for `exit` to flush, an `fwrite` past the buffer (ADR 0005), on either platform —
  or through a store into a shared mapping without an oracle, and that only an `open` named, was
  judged on an incomplete account and is now refused. Read from the rule, not measured on a target.
  On Linux `--observe syscalls` counts those writes, and the refusal's sentence says so there; macOS
  has no such mode, and its sentence names the stdio flush and a raw syscall instead of a reflink
  and io_uring, which it records and does not have.
- The net is per path and reads only the two snapshots. It does not reach a call neither witness
  records on a file another accounting record also names — a recorded write beside it, the
  destination of a rename or a link before it, or a truncate whose result the final bytes happen to
  match (`ftruncate(fd, 0)` and then the old bytes' first part through io_uring, the shape of
  dropping a file's last line) — nor on a scratch path a checker reads. Those files are accounted
  for, and the window in front of the unrecorded call is not explored.
- A saved FAIL case whose recording now reaches this refusal no longer replays: replay records again
  and reconciles before it compares the case (`docs/contract-freeze.md`, surface 4).
