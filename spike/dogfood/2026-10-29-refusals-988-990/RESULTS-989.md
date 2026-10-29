# #989 — readahead read as a read: RocksDB's `ldb` on main and on the change

One box (`apparatus/Dockerfile`, `sideeye-r1029`: Debian trixie, `rocksdb-tools` 9.10.0-1, strace 6.13,
linux/arm64) and two builds, `zig build -Dtarget=aarch64-linux-gnu` of main at `3a27be61` and of this
change, each mounted at `/se`. The define is the 2026-10-25 run's `ldb`
(`spike/dogfood/2026-10-25-shipped-v1160/apparatus/defines/ldb/`) unchanged — buffered reads, no
`use_direct_reads` — mounted at `/ap` and run by `apparatus/run.sh` from its own `seed.sh`, `--network none`.

| Build | Command | Answer | Transcript |
|---|---|---|---|
| main `3a27be61` | `preflight --twice --oracle` | UNKNOWN `unsupported_syscall_observed` naming `readahead` | `transcripts/ldb.base.preflight.txt` |
| this change | `preflight --twice --oracle` | recording accepted, 42 state-changing operations | `transcripts/ldb.989.preflight.txt` |
| this change | `explore --oracle` | **PASS** 43/43, the oracle agreeing on 42 operations | `transcripts/ldb.989.explore.txt` |

The 2026-10-25 run reached PASS 43/43 only with `use_direct_reads=true`, which keeps RocksDB from
prefetching (`spike/dogfood/2026-10-25-shipped-v1160/transcripts/explore/ldb-direct/`); the same count is
reached here with the buffered reads the define left on.
