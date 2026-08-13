# ADR 0013 — No descriptor number is exempt, and "could not tell" is not "not ours"

- **Status:** Proposed (flips to Accepted when the implementing PR merges)
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
