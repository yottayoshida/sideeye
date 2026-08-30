# 0023. Scope is read from the descriptor a syscall writes, not from its first argument

Date: 2026-08-26
Status: Accepted (implementing PR merged as `36a5b73`, 2026-08-26)

## Context

ADR 0006 decides scope by type: a path syscall resolves its real path
arguments, an fd syscall reads the annotation of its descriptor, and
anything else falls to a conservative whole-line net that can only
route to `unsupported`. The fd branch was implemented as
`syscallArg(line, 0)` and documented as a fact about the category:

> Every fd syscall carries its descriptor as argument 0.

That was true of every fd syscall the contract had. `write`, `fsync`,
`close`, `ftruncate`, `pwritev` and the metadata pair all put the
descriptor first.

`copy_file_range(fd_in, off_in, fd_out, off_out, len, flags)` does not.
Its first argument is the SOURCE. The destination — the descriptor
whose file changes — is argument 2. `#244` asked for the shim to
interpose the kernel copy primitives; classifying them in the oracle
without noticing the argument order would have been wrong in both
directions at once:

- a copy OUT of the state directory (source inside, destination
  elsewhere) would count as a mutation, though the state only gets
  read — a fabricated operation, and with it a fabricated crash point;
- a copy INTO the state directory from elsewhere would be scoped out
  and missed entirely — a real mutation nobody counts, which on a
  platform with no oracle is a PASS hole.

The existing test that pinned `copy_file_range` as `unsupported`
carried the evidence in its own fixture — `copy_file_range(3</tmp/s/a>,
NULL, 4</tmp/s/b>, …)`, with the annotations on arguments 0 and 2 —
and nothing read it that way until the interposition was designed.

## Decision

Scope for an fd syscall is read from the descriptor the syscall
**writes**, and which argument that is comes from a declared table
(`fd_write_args` in `src/oracle.zig`). The default is argument 0, so
every syscall absent from the table behaves exactly as before; the
table currently holds one entry, `copy_file_range → 2`.

`sendfile(out_fd, in_fd, …)` deliberately gets no entry: its
destination is already first. That is pinned by a unit test rather
than left as a comment, so a later "simplification" that drops the
default cannot pass quietly.

The shim carries the same fact on its side —
`ops.copy_file_range` records `noteFd(.write, fd_out)` — and the two
must agree or the copy is counted by one observer only, which is the
divergence the contract exists to make loud.

## Alternatives considered

- **Give copies their own `OpClass`.** Rejected. `link` and `symlink`
  earned classes because they create directory entries, an effect the
  restore model reproduces differently. A copy's effect on the
  destination is a write: the bytes change and nothing else does, and
  L0 compares bytes. A separate class would add a name the judgement
  never branches on.
- **Read scope from any annotated descriptor on the line.** Rejected
  for the same reason ADR 0006 rejected whole-line scanning: it makes
  "the state directory appears somewhere in this line" the test again,
  and a copy that only reads the state would scope in.
- **Leave `copy_file_range` unsupported.** That is the status quo and
  it is honest — on Linux. It is also why `spike/cohort4/himalaya-r2`
  exists: a whole revision built to route a real target around a wall
  that was ours, not the target's. The wall is worth removing.

## Consequences

- Trace contract v11: the countable operation set widens, so saved
  cases from v10 refuse with `case_no_longer_applies` (the freeze's
  promised behaviour, surface 4 — an earlier revision of this line named
  `contract_version_mismatch`, which is the shim/engine pairing refusal,
  not the saved-case one). `spike/cohort4/himalaya-r2` and the
  PRD paragraph that cites its replay are annotated as measurements
  taken under v10 rather than silently left in the present tense.
- `spike/cohort4/himalaya-r2`'s apparatus (`no-accel-copy.so`) is
  superseded and now collides with the shim: LD_PRELOAD wins over
  `/etc/ld.so.preload` (measured), so the shim would record a copy that
  the stub then answers without a syscall, leaving the oracle with
  nothing to match — a phantom. The define is kept as history with the
  collision named; deleting the stub is refused because run2's
  committed transcript contains its preload lines.
- The invariant that made this gap invisible for ten contract
  versions — nothing compared the oracle's classification table with
  the shim's export list — is now checked in CI
  (`spike/check-shim-coverage.py`), as "every classified syscall is
  interposed or explained", not as set equality: measured before the
  check was written, 28 exported symbols had no `known` entry and 4
  `known` entries had no export, so equality would have started red on
  32 differences, 29 of them legitimate, and been answered with an
  exclusion list.
  Its limits are stated in the script: it reads the Linux export list
  only, and the oracle's metadata tables are outside `known` and
  outside the comparison.
