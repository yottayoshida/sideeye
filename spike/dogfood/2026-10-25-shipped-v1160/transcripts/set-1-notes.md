# Set 1 — databases and storage (notes for RESULTS.md)

Field: transcripts/scout-1.txt (ten kept). First five taken: etcd (`etcdutl defrag`), Dolt, Turso
(`tursodb`), diesel_cli, Grafana (`grafana cli`). Reserves in scout order: vmrestore, Flyway,
sqlx-cli, RocksDB `ldb`, Chroma. Boxes: `sideeye-sv1025-s1` (sets/1), `-s1b` (sets/1b: vmutils,
Flyway, rocksdb-tools), `-s1c` (sets/1c: sqlx-cli). Sideeye v1.16.0 from the base box.

Every define was first run plainly (seed, operation, checker before and after:
transcripts/lab-s1.txt, lab-s1b.txt, lab-s1b-ldb.txt) and every checker was seen to reject a broken
state (transcripts/lab-s1-checker-red.txt).

## Verdicts

| Target | Version | Operation → state | Gate | Explore | What a crash leaves |
|---|---|---|---|---|---|
| Turso `tursodb` | 0.8.3 | one UPDATE over 500 of 1,000 rows → `shop.db` + `shop.db-wal` | accepted, 14 ops | **PASS** 15/15 with the WAL declared scratch and the checker (tursodb's own open, then SQLite's integrity_check) judging | nothing lost |
| diesel_cli | 2.3.14 | `diesel migration run` → `app.db` + `src/schema.rs` | accepted, 52 ops, after the clock was pinned | **FAIL** 15/53; checker red at crash point 52 of 52; both cases replayed twice | `src/schema.rs` 0 bytes after the migration committed (open with truncate, killed before the write); the next `diesel migration run` writes it again |
| RocksDB `ldb` | 9.10.0 (Debian; upstream 11.8.1) | `ldb put k1 changed` → the DB directory | accepted, 42 ops, with `allow_fallocate=false` and `use_direct_reads=true` | **PASS** 43/43 | nothing lost |
| Flyway | 13.11.1 (JRE 21) | `migrate` with one migration pending → `app.db` | accepted under `--observe supervised`, 52 ops | **PASS** 53/53 under supervised, app.db scratch, the checker judging every world | nothing lost |

## Walls, each after the next steps were tried

| Target | Version | Wall | Tried |
|---|---|---|---|
| etcd `etcdutl defrag` | 3.7.3 (static Go) | `multiple_threads_detected` under supervised | `GOMAXPROCS=1` (declared): still two writers. `strace -f -y` (transcripts/lab-s1-writers.txt): one sequence of pwrites to `db.tmp.*` moves from tid 2799 to tid 2803 midway and the rename follows on 2803 — one goroutine handed between OS threads by the Go runtime after a blocking call, not two writers at once. No switch pins it. |
| Dolt `dolt gc` | 2.6.0 (static Go) | the same | `GOMAXPROCS=1`; a second operation, `dolt sql -q UPDATE` (define `dolt-sql`), the same wall; strace: the main manifest's write/fsync/rename on one tid, the stats database's and oldgen's on another, in sequence |
| Grafana `grafana cli admin reset-admin-password` | 13.2.4 (static Go) | gate: wrapper `/usr/sbin/grafana` → `child_process_detected`; with the binary named, `--twice` split on one byte (the user row's timestamp; static, so libfaketime cannot reach it) → grafana.db scratch + checker → **gate accepted** (17 ops, one writer thread); **explore**: `multiple_threads_detected` under supervised, 3 of 3 explores, with and without `GOMAXPROCS=1` (tid 69 opens grafana.db, tid 66 the journal) |
| vmrestore | 1.154.1 (static Go) | `multiple_threads_detected` under supervised | `-concurrency=1 -skipFilePreallocation`, `GOMAXPROCS=1` |
| sqlx-cli `sqlx migrate run` | 0.9.0 (built from crates.io) | `multiple_threads_detected` in the default mode | the database opens in WAL mode and two threads fsync `app.db-wal`: the main thread and sqlx's own per-connection worker thread (detached), which is not tokio's worker pool, so no runtime switch reaches it |
| Chroma `chroma vacuum` | 1.5.9 (PyPI) | `multiple_threads_detected` in the default mode | `TOKIO_WORKER_THREADS=1` (define `chroma-1w`): still one thread makes the directory and another opens chroma.sqlite3 |

The four static Go walls are one shape: the Go runtime moves a goroutine to another OS thread around a
blocking system call, so a single sequential writer reads as two threads under supervised, which
records no ordering. `GOMAXPROCS=1` (docs/apparatus.md's switch for Go) does not stop the handoff.

Set 1 ends at **four judged** (Turso, diesel, RocksDB, Flyway): the first five lost etcd, Dolt and
Grafana to the threads wall, and all five reserves were tried in order — RocksDB and Flyway reached
verdicts, vmrestore, sqlx-cli and Chroma met the same wall. scout-1's list is spent.

## Things Sideeye did that a reader should know

1. **Grafana: preflight accepted, explore refused.** Two `preflight --twice` runs saw one writing
   thread; three explore recordings saw two. Whether the Go runtime hands the goroutine over is a race,
   so an accepted preflight does not predict the explore's thread answer for a static Go target.
2. **Flyway's refusal sends the user nowhere, and supervised judged it.** In the default mode the JVM
   runs `uname -o` through `jspawnhelper` (and, with `-Djdk.lang.Process.launchMechanism=FORK` or
   `VFORK`, through a forked child), which closes every descriptor before exec, the shim's trace among
   them: `unresolvable_path` (trace-closed-by-target), whose next step says "refused by design".
   `--observe supervised`, which keeps no descriptor in the target, accepted it and explored it to PASS.
   The refusal could name supervised the way `no_shim_marker` does.
3. **`readahead(2)` is refused as an unsupported call.** RocksDB's buffered reads prefetch with it
   (define `ldb`: `unsupported_syscall_observed readahead`). It changes nothing on disk, like the
   `sync_file_range` and `syncfs` v1.16.0 now passes over (#970); `use_direct_reads=true` routes around
   it here, but a tool with no such option stops.
4. **A WAL judged byte for byte fails by design.** Turso's first explore (transcripts/explore/
   tursodb-wal-judged/) was a FAIL 8/15 on `shop.db-wal` "holding neither the old nor the new
   content", with the checker accepting the same world. A write-ahead log is meant to hold the frames
   in between; declaring it scratch is the define's job, and the record keeps both runs.
5. **Dolt's default mode**: refused `oracle_missed_operation` with the static-parent sentence ("The file
   the operation names was read before the run as a statically linked image …") — dolt starts a child
   that carried the shim.

## Known upstream?

- diesel: `diesel_cli/src/main.rs:324` `std::fs::write(path, schema.as_bytes())` in
  `regenerate_schema_if_file_specified` (read 2026-10-25 through the contents API). Issue search in
  diesel-rs/diesel for "schema.rs empty", "schema.rs truncated", "print_schema atomic",
  "schema.rs write atomically", "schema.rs interrupted": no hits. The file is generated and the next
  `diesel migration run` (or `diesel print-schema`) writes it back (transcripts/explore/diesel/
  case2-recovery.txt), so nothing the user cannot regenerate is lost; a hand-patched schema
  (`patch_file`) is re-applied by the same path.

## Where the rest is

Work directories (state snapshots, traces) were moved out of the tree with `keep-cases.sh` to
`~/.cctmp/set1-rkcHle/work/` (swept after seven days); the case files a replay reads stay as
`transcripts/explore/<t>/case-*.json` (diesel keeps both of its cases, `case-explore-000001.json` and
`-000002.json`; `case-explore.json` is the second).

## The fifth target (set 1 had four after scout 1's ten; set 2's unused reserves, in order)

Box `sideeye-sv1025-s1e` (`apparatus/sets/1e/Dockerfile`, `transcripts/build-set1e.txt`): Node 24.22.1,
Lerna 10.1.1, Prisma 7.10.1, knex 3.3.0 + better-sqlite3 13.0.3. **Prisma's npm `latest` tag points at
8.0.0-rc.27, a release candidate; GitHub's latest release is 7.10.1, and that is what was measured.**
The repository is `prisma/orm` now (`prisma/prisma` redirects).

| Target | Command → state | Gate | Explore | What a crash leaves | Known upstream |
|---|---|---|---|---|---|
| Lerna 10.1.1 | `lerna version 2.0.0 --yes --no-git-tag-version --no-push` → lerna.json, package-lock.json, three package.json | **wall** `multiple_threads_detected` in all three modes | — | (strace: each manifest opened `O_WRONLY\|O_CREAT\|O_TRUNC`) | not searched (walled) |
| Prisma 7.10.1 (`prisma-dbout`) | `prisma db pull` → prisma/schema.prisma (hand-written: doc comments, `@map`, `@@map`) | 0, 2 operations | **FAIL 1/3**, replayed twice FAIL; evidence written | crash point 2 of 2, after `open(schema.prisma)` (`O_TRUNC`) and before its `write`: **schema.prisma 0 bytes**, the hand-written `@map`/`@@map` names and `///` comments gone. A second `db pull` writes a schema without them | none found: `search/issues` on `repo:prisma/orm` for "db pull empty schema", "db pull schema truncated", "schema.prisma empty file", "schema.prisma lost", "db pull wiped schema", "introspection overwrites schema killed", "writeFile schema atomic" |

knex was not reached: Prisma was the first of the three to reach an explore.

### Lerna: what was tried before writing the wall

1. First gate: two writers, nx's native thread renaming into `node_modules/.cache/nx-workspace-data`
   (through the workspace's `node_modules` symlink) and the main thread. `NX_WORKSPACE_DATA_DIRECTORY` and
   `NX_CACHE_DIRECTORY` moved nx's files outside the state (declared as apparatus).
2. Second gate: the libuv pool thread writes the three `package.json` (async `fs.writeFile`) and the main
   thread writes `lerna.json` (and a `mkdir` of the existing state root). `UV_THREADPOOL_SIZE=1` is set:
   it leaves one pool thread, which is still not the main thread, so a tool that mixes async and sync
   writes is not moved by it.
3. `--observe supervised` and `--observe syscalls` (`transcripts/lab-s1e-lerna-modes.txt`): the same
   refusal. The state is git-tracked manifests, so the wall costs little.

### Prisma: the define's two steps

1. `prisma` (database inside the state): the jiti config cache (`node_modules/.cache/jiti`, main thread)
   was turned off with `JITI_FS_CACHE=false`, after which one thread writes. The gate then refused
   `child_touched_state_dir` in the default mode and under supervised; under syscalls,
   `recording_run_failed` (not followed further).
2. `prisma-dbout`: `db pull`'s one write is schema.prisma, and it only reads the database, so the
   database moved to `/s/db/dev.db`, outside the state. Accepted, explored, FAIL.

The checker (`/s/prisma-check.sh`, written by seed.sh) runs `prisma validate` and then looks for the four
hand-written mappings. Seen red on an empty schema.prisma — by the mapping check: **`prisma validate`
exits 0 on an empty schema file** (`transcripts/lab-s1e.txt`).

### On Sideeye's side

- **The `child_touched_state_dir` detail does not match its capture.** It says the reader resolves a
  relative path against the subject's working directory and a child that changed its own is invisible.
  The capture (`transcripts/lab-s1e-prisma-oracle/grep.txt`): Node `chdir("/s/shop")` in the child
  before `execve` of the schema engine (pid 43), and the engine's thread tid 48 opened
  `/s/shop/prisma/dev.db` by an **absolute** path, `O_RDWR|O_CREAT|O_NOFOLLOW`, then only `pread64`
  and `fcntl` locks. Either the account cannot place an absolute open by a child's thread, or the
  detail names the wrong cause. Not followed into the source.
- Lerna's second writer on the main thread includes `mkdir(/s/mono)`, the state root that already
  exists: a call that changes nothing still counts as a write for the threads rule (the shape the
  2026-10-22 walls run met with vercel and codex).

Files: `apparatus/sets/1e/Dockerfile`, `apparatus/defines/{lerna,prisma,prisma-dbout}/`,
`transcripts/{build-set1e,entry-s1e,lab-s1e,lab-s1e-lerna-modes,lab-s1e-prisma-modes,explore-s1e}.txt`,
`transcripts/lab-s1e-prisma-oracle/`, `transcripts/explore/prisma-dbout/` (case kept). Work directory
moved to `~/.cctmp/set1e-JaWF38/work` (swept in 7 days).
