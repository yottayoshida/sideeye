# Card — gdbmtool 1.24-2, storing three keys

**Operation.** A `gdbmtool` session stores three new keys (`k4`–`k6`) into a GDBM database that
already holds three (`k1`–`k3`).

**Documented contract** (the GDBM manual, "Crash Tolerance", "Recovery"; gdbmtool(1), `recover`):
a database left inconsistent by a crash is repaired before use with `gdbm_recover` —
`gdbmtool <db> recover` — which keeps what it can read. Without crash tolerance configured, GDBM
does not promise that the stores of an interrupted session are all or none.

**Legs, read after the recovery a user would run.**

- **(a) The database opens.** `gdbmtool` can open it and list its keys. *Broken alone:* a file at
  the database's path that is not a GDBM database.
- **(b) What was there survives.** `k1`–`k3` are present with their original values. *Broken
  alone:* the database opens, `k4`–`k6` are as stored, and `k2` is missing.
- **(c) A new key is whole or absent.** Each of `k4`–`k6` is absent or holds its new value.
  *Broken alone:* `k5` present with a value that is not the one stored.

**Admissible after a crash:** any subset of `k4`–`k6` stored, `k1`–`k3` intact, after recovery.
A recovery that reports keys it could not read is admissible only if (b) still holds.

**Not claimed:** that the three new keys are stored together; GDBM's crash-tolerance snapshot mode,
which the operation does not enable.
