# ADR 0013 — No descriptor number is exempt, and "could not tell" is not "not ours"

- **Status:** Accepted (2026-08-13; the implementing pull request merged as contract v8)
- **Supersedes:** the fd-number exemptions that shipped with v0.1's shim (`fd <= 2`
  and the trace-fd comparison in `noteFd`); tightens ADR 0003's fd-addressed
  observation
- **Scope:** `shim/src/common.zig` (fd resolution), trace contract v7 → v8, a
  `--work`-inside-state refusal in `src/main.zig`

## Context

The shim's fd-addressed wrappers (`write`, `fsync`, `ftruncate`, `close`, the stdio
flush family) resolved a descriptor to its path on every operation — `/proc/self/fd`
on Linux, `F_GETPATH` on macOS — and judged scope by location. But two early returns
sat in front of that resolution, both keyed on the descriptor's *number*:

1. `fd <= 2` — "stdin/stdout/stderr are not state". A target can `dup2` a state
   file onto any standard descriptor; every write through it was invisible.
   Measured on the pre-fix binary with the `TOY_DUP2` toy (writes through fd 1,
   fd 2, fd 0, plus a stdio leg on rebound stdout): **without an oracle,
   `--allow-unverified` reported PASS 9/9 while four state files were written
   invisibly** — a false PASS, the failure direction this tool exists to prevent.
   With the oracle, the run refused as `oracle_missed_operation` — the second
   witness held, so the wrong verdict lived only on the oracle-less path (macOS,
   `--allow-unverified`).
2. `fd == trace_fd` — "never observe the trace we are writing". The trace fd is
   stored as an integer, and a target that closes it and re-uses the number for a
   state file inherited the exemption. The check never protected the trace itself —
   the shim's own trace writes go through the real `write` directly and never pass
   these wrappers — but removing it exposed the deeper problem review named: the
   *number* is the channel's identity, and nothing defended the channel. Measured
   with a daemonize-style `close(3..255)` sweep on the unguarded build: the target's
   own state file ended up with the shim's binary trace records spliced between its
   bytes — the harness corrupting the very data it judges — and the run refused only
   by the accident of a structural detector (`state_changed_without_ops`).

Review found a third, quieter conflation: `fdPath` returning null meant *both* "this
descriptor provably names no file (a socket, a pipe)" *and* "the path query failed
on a real file". The first is evidence the operation is elsewhere; the second is a
measurement that did not happen — and it was being silently treated as innocence.
On macOS, `F_GETPATH` has no "(deleted)" spelling, so an open-but-unlinked state
file — bytes with no snapshot address — was undetectable there, a gap the code
commented but could not close.

## Decision

1. **The only descriptor-keyed early return is `fd < 0`.** Everything else is
   decided by asking the kernel where the descriptor points, on every operation.
   Ordinary stdout/stderr (a tty, a pipe, the engine's stdout-capture file under
   `--work`) resolve outside the state directory and stay unrecorded — by location,
   not by number.
2. **Fd resolution is three-valued.** `fstat` (Darwin libc; the raw `statx`
   syscall on Linux, where std.c deliberately exports no fstat) speaks first:
   - a **proven** socket, pipe, or device is out of scope — nothing to record.
     Type bits of zero join this class: they are the kernel's anon-inode spelling
     (eventfd, epoll, timerfd, io_uring), nothing that can live in a state
     directory stats that way, and before this classification one `close()` of an
     eventfd sent the whole run to `unresolvable_path` (measured) — every
     epoll-based target was unjudgeable. So does `S_IFLNK` (an `O_PATH` symlink
     descriptor cannot carry a write, truncate, or sync). kqueue on macOS reports
     a FIFO (measured) and was never affected;
   - a regular file or directory goes on to name its path; if the path query
     fails, the operation is recorded as `unresolved` and the engine refuses
     (`unresolvable_path`) — a failed measurement never passes as a clean one.
     The same three-way split applies to the *base* descriptor of the `*at()`
     family in `resolveAt`, where the identical conflation was found by the
     same-class scan;
   - `st_nlink == 0` marks an open-but-unlinked file on both platforms, closing
     the macOS gap: such writes record as `unresolved` when the file was inside
     the state directory.
3. **`--work` must not be the state directory or inside it** (refused as a setup
   error before anything runs, for every caller — the MCP server reaches this
   check through its self-exec). With the exemptions gone, the engine's own
   capture files — which ride the target's fd 1 — would otherwise be observed as
   the target's state operations, poisoning snapshots, counts, and saved-case
   addresses. The other nesting (state inside work) stays legal: captures land at
   the work root, outside the state subtree. Review then held the check itself to
   its own standard: it now runs *before* `--fresh-state`'s deletion (the first
   version emptied the state directory and only then noticed the setup was
   invalid), removes the one directory its own resolution had to create, and uses
   `isInsideDir` — the hand-rolled prefix test it replaced answered "outside" for
   a state directory of `/`, because the character after `/` in `/tmp` is `t`.
4. **The trace channel defends its own identity.** Its descriptor is relocated at
   init (`F_DUPFD` to ≥ 900, falling back to ≥ 200 under a 256-descriptor rlimit
   — the macOS default) so daemonize-style hygiene sweeps of `close(3..255)` pass
   under it, and every wrapper that retires a descriptor — `close`, `fclose`,
   `freopen` — treats closing the trace fd as the channel dying: one final
   `unresolved` record while the descriptor still works, then silence, so the
   engine refuses (`unresolvable_path`) and not a byte is ever written through a
   number the target has re-bound. The refusal is honest, not free: a target that
   deliberately closes every descriptor to 1023 becomes unjudgeable, which is the
   correct price for a tool that cannot otherwise tell what it missed.
5. **Trace contract v7 → v8.** The countable operation set changed for affected
   targets — the same bump class as v5 (stdio flush granularity) and v7
   (`remove(3)`). Saved v7 cases refuse honestly via the existing
   contract-mismatch path.

Post-fix measurement, same toy: the four descriptor-borne writes are counted
(crash points 8 → 12), the oracle **agrees on all 12 operations** (the shim's own
per-operation `statx`/readlink resolution syscalls are absorbed by the oracle's
read-only classification — measured, not assumed), and the plain toys' operation
sequences are unchanged.

## Alternatives considered

- **Interpose `dup2`/`dup3`/`fcntl(F_DUPFD*)` and keep a descriptor table.** A
  stateful ledger must catch every duplication path or silently reopen the hole,
  and it duplicates an authority that already exists — the kernel answers the
  question per operation. Rejected.
- **Keep the skips and document the limitation.** Rejected upstream of this ADR:
  a wrong PASS in the supported class touches the product's reason to exist
  (issue #86's ruling, independently reached by external review).
- **Pretend the trace fd's close succeeded (intercept and refuse it).** Rejected:
  it lies to the target about its own descriptor table, and it still leaves
  `dup2` onto the number as a theft the close wrapper never sees. Announcing the
  death and refusing is honest in both directions. What remains outside the
  guard: a raw `close_range(2)` or direct syscall never crosses the libc
  wrappers — the same blindness LD_PRELOAD interposition has for every raw
  syscall, already documented as the approach's boundary — and a deliberate
  `dup2` onto the relocated number (≥ 900), which no descriptor-hygiene idiom
  reaches by accident.
- **Cache fd → path resolutions for speed.** Reintroduces the staleness hole that
  `dup2` creates; rejected. The cost is real — descriptor-addressed operations on
  fd 1/2 now pay a stat plus a path query each — and it is the price of soundness;
  the fstat-first order actually *cheapens* tty and pipe writes, which now skip
  the path query entirely.

## Consequences

- A target writing state through any descriptor, however obtained, is observed —
  or the run refuses. The claim "stdout is not state" is now decided by where
  stdout points.
- macOS loses a PASS-side gap it could not previously detect (unlinked files).
- Daemonize-style targets — `close(3..255)` at startup — become judgeable: the
  relocated trace fd sits above the sweep. A sweep that does reach the channel
  refuses with the channel named, and the target's state files hold exactly what
  the target wrote (both pinned in acceptance and macOS CI).
- Targets built on eventfd/epoll (every async runtime) and kqueue are judgeable;
  their anon descriptors neither refuse the run nor add counted operations.
- Saved cases recorded under v7 must be re-recorded; the CI-resident regression
  case planned in #82 should be captured only after this lands.
- Chatty targets pay a per-write resolution cost on standard descriptors.
- **Amended 2026-10-17 (#900): a sweep through libc's `closefrom` or `close_range` no longer
  ends observation.** Both are libc entry points the shim can interpose, as it does `close`, and
  CPython's subprocess calls `close_range(3, ~0U, 0)` in every child before its exec — refusing
  on it, as `close` does, would have refused every target that starts a Python subprocess, and a
  `vfork` child that wrote the shared `trace_fd` would have silenced its parent. The shim now
  lets the call run, then asks whether its own descriptors (the trace, `cgroup.kill`, the
  step-aside) were closed; for each that was, it opens the same file again from the name kept at
  `init` and puts it back on the **old** number with `dup3`. A process that shares this memory
  without owning the slot table — a `vfork` child — never writes these numbers, whatever happens:
  its parent's descriptors were not swept, and a -1 written by the child would silence them. The
  trace is opened without `O_CREAT` and must be the same inode `init` opened; when it is not, when
  the trace sits below the relocation floors (a number the target's next open may take), when its
  number is open again on another file (the target's now, never overwritten), when the `dup3`
  fails (the target lowered `RLIMIT_NOFILE`'s soft value below the number), or when the reopen
  fails, the channel is given up as before, the death written through the reopened file whenever
  it is the trace. The death goes through a buffer of its own, never the thread's record buffer,
  so a sweep from a signal handler is handled like any other. A process with another live thread
  writes the death after reopening, since what that thread lost while the channel was gone cannot
  be told from what it never did; a thread that has exited holds its slot still and is not
  counted. A reopen that fails leaves no death, as a closed trace did before. Two windows stay
  open without a lock the shim cannot take: another thread that takes the number between the
  check and the `dup3` has its descriptor replaced by the trace (its process is refused, since
  that thread is alive); and a `vfork` child whose number now holds another file leaves the
  shared number alone, so its own records until its exec land in that file (its run is refused
  by the death it wrote). `cgroup.kill` and the step-aside descriptor are put back the same way,
  never below the relocation floors. The reopen is a second open of the trace by name, the
  exposure the comment in `init` describes — the same one every exec'd image already takes.
  `close(2)` of the relocated number still refuses as decided above, and a raw `close_range(2)`
  syscall is still outside the guard. The fortified opens glibc substitutes for `open` and
  `openat` under `_FORTIFY_SOURCE` (`__open_2`, `__open64_2`, `__openat_2`, `__openat64_2`) are
  interposed in the same change.
- **Amended 2026-11-01 (#933): a record the shim cannot write because the trace was closed is not
  dropped.** A raw `close` or `close_range` system call never passes a wrapper, so the shim learned
  of it only by its next record failing, and a failed write left nothing behind: an account cut
  short read as one that ended, and without an oracle a run could PASS over operations nobody
  counted. Now a failed write to the trace, while its descriptor is closed or no longer names the
  trace file, goes through the second half of the sweep above: the trace is opened again by name,
  the death is written there when it is the same file, and an owner gives the channel up. The first
  access after the close is usually the numbering's `lseek`, not a write, and it ends in a write
  too, so one place catches it. The channel is not put back on its number here, as it is after a
  sweep: the record that failed would have to be sent again, and one cut part-way continued after
  another process's, where the engine stops reading. So the run refuses `unresolvable_path` (trace-closed-by-target)
  rather than being judged. A write refused while the descriptor still names the trace (`ENOSPC`,
  `EIO`, `EFBIG`, a target's own seccomp filter) writes no death: the death says the target closed
  the channel, and its refusal would send the reader to `--observe supervised`, which would not
  help. Linux only, as the sweep is. Three things stay open: a trace that cannot be opened again
  (removed, `EACCES`), or one whose identity was never read at `init`, leaves no death; a refused
  write as above is still lost; and a number the target took for a file of its own after the close takes the
  shim's next records without an error, which the relocation floors keep from happening by
  accident. A process that does not own the slot table writes a death at each failed record until
  it execs, since it cannot give up its parent's channel; the first one refuses the run.
- **Amended 2026-11-01 (#941): one rule for a lost descriptor of the shim's, and one liveness probe.**
  On Linux a `close` or `fclose` of the trace, `cgroup.kill` or the step-aside descriptor is now
  decided after the call by the function that decides a sweep: the trace goes back on its number when
  it is the same file and the number is still free, and otherwise the death is written and an owner
  gives the channel up. `close(2)` of the relocated number no longer refuses the run by itself, so a
  target that closes every descriptor up to 1023 one at a time is judged. Three losses still refuse:
  a `freopen` of the trace, since glibc puts the new file on the same number, so the number holds
  another file when the shim looks; a write that finds the trace gone (#933's rule, which does not put
  it back); and a loss while another thread of the process is alive, where the trace goes back and
  the death is written too. The three numbers are taken back at most eight times between them per
  process, counted by pid so that a `vfork` child sharing the memory does not spend its parent's — a
  loop that closes until nothing is left to close would otherwise meet them on every pass — and with `F_DUPFD`
  from that number, used only when it returns that number, where `dup3` replaced whatever held it.
  A process that does not own the slot table writes the shared numbers on no path; on macOS, where
  nothing is put back, a close of the trace writes the death and only an owner sets the number to -1.
  What the target can tell: after `close(900)` the number answers `fcntl` again, as after a sweep. The
  price is the case decision 4 named: a target that closes the trace number and then puts a file of
  its own on it with `dup2` takes the shim's later records into that file, and under an oracle that
  run is refused (`oracle_missed_operation`: strace sees the writes the shim's account lacks); without
  one, the run already makes only the weaker claim. The races the sweep had now come with every close
  of the trace: another thread that duplicates onto the number the reopen briefly holds, or a second
  thread closing the trace at the same moment, ends in a refusal or in a descriptor of the target's
  closed under it. Whether a process or thread is alive is asked one way, by `contract.probeSaysGone`:
  a failed signal-0 probe means it is gone on `ESRCH` alone, in the shim's slot reclaim, its thread
  check and the engine's work-directory lock alike.
