# Results — 2026-10-22, two calls that change nothing, on #945 and #946's build

Two targets stopped at the gate on calls that change nothing on disk: DuckDB 1.5.6 on
`unlinkat(AT_FDCWD, "", 0) = -1 ENOENT` at its checkpoint (2026-10-12 shipped-v1120, #945) and dpkg
1.22.22's upgrade on `sync_file_range` (2026-10-14 mechanisms, #946). Both were refused
`unsupported_syscall_observed` by the strace oracle; the recording witnesses record neither call. The
change passes over a call in the oracle's path table given the empty path, unless the call takes
`AT_EMPTY_PATH` for that path and its flags hold it or cannot be read, and reads `sync_file_range` and
`syncfs` as reads.

Each target and the acceptance toy were run on two engines built the same way from the same base — `main`
and the change — so a wall that moved did so between those two builds and not between two boxes
(`transcripts/build.txt`: the base commit, the diff's sha256 and each binary's). The defines are the
ones those runs committed, read from their own `apparatus/` directories, unchanged; both targets ran in
the 2026-10-12 box, which holds DuckDB 1.5.6, dpkg 1.22.22 and libfaketime (the 2026-10-14 box was not
on this machine). Every gate run is `preflight --twice --oracle /usr/bin/strace` under each of the three
observation modes; the scripts are in `apparatus/`.

| target | mode | `main` | the change |
|---|---|---|---|
| the toy's calls that change nothing (`TOY_ANONFD`, acceptance) | wrappers, syscalls, supervised | UNKNOWN `unsupported_syscall_observed` (`unlinkat`) in all three | **PASS** 5/5 in all three |
| DuckDB 1.5.6 `UPDATE` | wrappers, syscalls, supervised | UNKNOWN `unsupported_syscall_observed` (`unlinkat`) in all three | **recording accepted**, 12 operations, in all three |
| dpkg 1.22.22 `dpkg -i` (an upgrade) | wrappers | UNKNOWN `unsupported_syscall_observed` (`sync_file_range`) | UNKNOWN `oracle_missed_operation` |
| | syscalls | `recording_run_failed` (dpkg exits 1) | `recording_run_failed` (dpkg exits 1) |
| | supervised | UNKNOWN `unsupported_syscall_observed` (`sync_file_range`) | **recording accepted**, 169 operations |

Each oracle capture of the change holds the call it no longer refuses on: the empty `unlinkat` (twice
per run under `--observe syscalls`, the trapped first line ending in the register's value `4294967196`
rather than an errno), and `sync_file_range` four times per run in dpkg's wrappers and supervised runs.

**DuckDB** goes on to a verdict under the default mode and `--observe syscalls`: FAIL 3/13 on the
built-in atomicity of `shop.duckdb`, earliest at crash point 8 of 12, between two writes to the database
file. DuckDB rewrites that file in place at checkpoint with its WAL left beside it, and the define's
checker accepted the earliest of those worlds (`transcripts/duckdb-evidence-wrappers.md`): this is not a
finding, and the define would declare the file before a run read anything from it.

**dpkg** goes on to a verdict under `--observe supervised`: FAIL 16/170 by the define's checker, earliest
at crash point 24 of 169, after `rename(updates/tmp.i)` and before the directory's `fsync`
(`transcripts/dpkg-explore-supervised.txt`). In that world dpkg's status reads `install reinstreq
half-configured 1.0`, `--configure -a` answers that the package must be reinstalled, and the checker
does not try the reinstall — it runs `dpkg -i` again only for a half-installed, not-installed or unpacked
package. Whether the reinstall dpkg asks for restores the package was not measured, so this is not yet a
finding either. Under the default mode dpkg meets the next wall: strace shows two writes to its `tmp.i`
update file (4096 and 512 bytes), and the shim's record holds one; which call the shim missed was not
read. Under `--observe syscalls` dpkg exits 1 on both engines, as easy-rsa did under the syscall trap with
the clock pinned (2026-10-07 user-data-3); not read further either.
