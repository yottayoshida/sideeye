# Invariant: a gdbmtool session storing three new keys

## The operation

One gdbmtool session, run non-interactively, that stores three new records into a GDBM
database already holding three:

    gdbmtool -N -q -m ../state/db.gdbm store k4 v4 ; store k5 v5 ; store k6 v6

`-N` skips any `.gdbmtoolrc`. `-m` (`--no-mmap`) is there because sideeye cannot see GDBM's
default memory-mapped writes: with them, preflight refuses the run
(`state_changed_without_ops`). So this is the session **without mmap**. gdbmtool 1.24-2
(Debian 13), aarch64.

## Valid before

`db.gdbm` holds exactly `k1=v1`, `k2=v2`, `k3=v3`, written by gdbmtool (`setup.sh`).

## Valid after

`db.gdbm` holds exactly `k1=v1` … `k6=v6`.

## Acceptable after a crash (after `recover.sh`)

The recovery: GDBM's documented repair for a damaged database is `gdbm_recover`. From the
shell it is gdbmtool's `recover` command. A user notices damage when a read fails. So
`recover.sh` reads the whole database once (`gdbmtool -r list`). If gdbmtool reports an
error on stderr, it runs `gdbmtool recover`. Otherwise it does nothing.

After that, a state is acceptable when all five legs hold (`check.sh`):

| leg | claim |
|---|---|
| a | `db.gdbm` exists and `gdbmtool -r list` reads it: exit 0 **and** empty stderr. gdbmtool exits 0 even when a command fails |
| b | `k1=v1`, `k2=v2`, `k3=v3` each appear exactly once, with those values |
| c | each of `k4`, `k5`, `k6` is either absent or appears exactly once with its own value |
| d | no key other than `k1`…`k6` |
| e | the new keys that are present form a prefix of `k4, k5, k6` (none; k4; k4+k5; all three) |

So valid states are the start, the end, and the two in-between states (`+k4`, `+k4,k5`),
whether or not they were reached through `recover`. If leg a fails, legs b–e print `-`
(not judged), because there is nothing to read.

Leg e comes from how gdbmtool runs: one command at a time, and each `gdbm_store` writes its
key, data and bucket before returning (strace shows this). GDBM does not promise this
against power loss. It is only a claim about a killed process.

## What the checker does not claim

- **Byte atomicity of `db.gdbm`.** GDBM rewrites the file in place by design, so a kill
  between a store's data write and its bucket write leaves bytes that match neither the old
  file nor the new one. The define marks `db.gdbm` as `scratch` so the built-in byte layer
  skips it, and the checker judges what gdbmtool reads. Without that line the run FAILs
  on L0 at crash point 3, while the checker passes in every world
  (`explore-2-noscratch.txt`, `replay-2-noscratch.txt`).
- **That `recover` keeps data in general.** `gdbmtool recover` says "Recovery succeeded"
  and exits 0 even when it drops every record (a damaged bucket header gives an empty
  database). The checker does not trust that message: it judges the records afterwards,
  so a recovery that loses k1–k3 fails leg b.
- **The mmap path** (gdbmtool without `-m`), which is the default a user gets.
- Power loss, torn writes, `fsync` ordering, concurrent writers, the crash-tolerance
  (snapshot / numsync) mode, and values with spaces or binary bytes. `list` output is
  parsed as one `KEY VALUE` per line.
- File mode, owner, timestamps, and the file's size or free-space layout.
- That an in-between state is "nice". Losing the tail of the session (k5, k6) is accepted.
  The user re-runs the missing stores.
