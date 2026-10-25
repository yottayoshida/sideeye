# 2026-10-25 shipped-v1160 — results

Twenty tools this project had not met, each judged by **the released v1.16.0**, installed in the base
box `sideeye-sv1025` by the page's installer with its digest matched (`transcripts/build-base.txt`),
in four sets run side by side, one box per set (`apparatus/sets/<N>/Dockerfile`, built `FROM` the base).
Selection is `SELECTION.md`; the detail behind every row is in `transcripts/set-{1,2,3,4}-notes.md`,
written as each set ran.

**14 FAIL, 6 PASS.** Eleven more were met and stopped at a wall, each after the next steps below; the
set's next reserve took its place. One box could not hold its target (Dokku).

## The twenty

"Lost" says what a user is left with after the kill; "no loss" FAILs are recorded with the reason.
Every FAIL was replayed twice from its case (`transcripts/explore/<t>/`), and every replay failed again.

| Set | Target | Version | Operation → state | Verdict | Lost |
|---|---|---|---|---|---|
| 1 | diesel_cli | 2.3.14 | `diesel migration run` → `app.db`, `src/schema.rs` | **FAIL** 15/53 | `src/schema.rs` 0 bytes after the migration committed (`std::fs::write`); the next `migration run` or `print-schema` writes it again |
| 1 | Prisma | 7.10.1 | `prisma db pull` → a hand-written `prisma/schema.prisma` | **FAIL** 1/3 | `schema.prisma` 0 bytes: the hand-written `@map`, `@@map` and doc comments are gone, and pulling again does not bring them back. `prisma validate` accepts the empty file |
| 1 | Turso `tursodb` | 0.8.3 | one UPDATE → `shop.db` (+ WAL, scratch) | **PASS** 15/15 | — |
| 1 | RocksDB `ldb` | 9.10.0 (Debian; upstream 11.8.1) | `ldb put` → the DB directory | **PASS** 43/43 | — |
| 1 | Flyway | 13.11.1 | `flyway migrate` → `app.db` | **PASS** 53/53 under `--observe supervised` | — |
| 2 | Symfony secrets | 8.1.9 | `secrets:generate-keys --rotate` → `config/secrets/prod` | **FAIL** 8/25 | killed after the new keys replaced the old and before every secret was sealed again: the secrets (DATABASE_URL among them) can no longer be decrypted, and the old key is gone; in other worlds a key file or `list.php` is cut short and `bin/console` itself dies |
| 2 | Nextcloud `occ` | 33.0.10 | `occ config:system:set trusted_domains` → `config/` | **FAIL** 1/4 | `config.php` empty: `secret`, `passwordsalt`, `instanceid` and the database settings all gone (`ftruncate` then `fwrite`; master the same) |
| 2 | Docusaurus | 3.10.2 | `write-translations --locale fr` → `i18n/` | **FAIL** 5/12 | the translator's `code.json` and theme files 0 bytes (`fs.outputFile` in place) |
| 2 | vcpkg | tool 2026-09-26 | `vcpkg remove zlib` → `installed/` | **FAIL** 4/55, by the checker | status left `purge ok half-installed`: `vcpkg list` no longer shows zlib, its files stay, and `remove` again says it is not installed. `install zlib` again repairs it; no user data lost |
| 2 | drizzle-kit | 0.31.11 | `drizzle-kit migrate` → `db/app.db` | FAIL 9/47 by the built-in invariant only; the checker accepted every world | **no loss**: SQLite's hot journal rolls the database back on the next open |
| 3 | systemd-sysusers | 257 (Debian; upstream 262.1) | `systemd-sysusers --root=R app.conf` → `R/etc/{passwd,shadow,group,gshadow}` | **FAIL** 3/46, by `pwck`/`grpck` | the four files renamed one after another, killed between: a group in `group` and not `gshadow`, a user in `passwd` and not `shadow`. **Running it again repairs only one of the three**: `add_user` returns when the name is in `passwd` without looking at `shadow` (262.1's source the same). Existing accounts survive |
| 3 | Vagrant | 2.4.9 (built from the tag as a gem) | `vagrant global-status --prune` → the machine index | **FAIL** 25/36; with one machine left running (define `vagrant-live`) **FAIL** 37/53 | the index 0 bytes, and `JSON.load("")` returns nil, so `global-status` lists no machines, with no error. **Nothing is lost for good**: running Vagrant in a machine's own project puts it back (`transcripts/plain-repro-s3-vagrant-recover.txt`); until then the cross-project list is empty, and the next save keeps it so. With a live machine, it drops out of `global-status` in seven worlds |
| 3 | Salt `salt-call --local` | 3008.4 (onedir) | `grains.setval` → `grains` | **FAIL** 1/3 under `--observe supervised` (named; the next step did not) | `grains` empty (`O_TRUNC`, then the YAML dump): every grain the user set reads back as `""`, with no error |
| 3 | FreshRSS | 1.30.4 | `cli/reconfigure.php` → `data/config.php` | **PASS** 7/7 | — (temporary file, `.bak`, rename) |
| 3 | wallabag | 2.6.14 | `wallabag:import` → the SQLite database | **PASS** 88/88 by the checker (database and journal scratch) | — (judged byte for byte, FAIL 20/88: `explore/wallabag-l0/`, the journal doing its job) |
| 4 | Godot | 4.7.2 | `--headless --convert-3to4` → a Godot 3 project | **FAIL** 8/20; the recovery (convert again) FAILs too | `project.godot`, scenes and scripts each 0 bytes, the original nowhere; the converter first stamps `project.godot` as converted, so a second run refuses with "already converted" (seen by hand too) |
| 4 | Luanti | 5.17.0 (built from the tag, server only) | `luantiserver --migrate-players sqlite3` → the world | **FAIL** 184/287; the recovery (migrate again) PASSes | `world.mt` still says `files`, so one to five migrated players are not found; the data is in `players.sqlite` and `players.bak/`, and migrating again brings them back |
| 4 | Paperless-ngx | 3.3.4 | `manage.py document_renamer` after `PAPERLESS_FILENAME_FORMAT` changed → `media/` + `db.sqlite3` | **FAIL** 174/210; the recovery (rename again) PASSes | a file moved to its new name with its row still naming the old one; running the renamer again adopts it |
| 4 | COLMAP | 4.2.1 (built from the tag) | `colmap point_filtering` with input and output the same model → `sparse/0` | **FAIL** 5/11 | the model's `.bin` files truncated, the model unreadable, the original nowhere |
| 4 | Firefly III | 6.7.9 (PHP 8.5) | `artisan firefly-iii:correct-database` over a damaged ledger → `database.sqlite` | **PASS** 414/414 (database and journal scratch, the checker opening it read-write) | — |

Set 3's first fifth, vcpkg `remove utfcpp`, was explored before set 2 took vcpkg as its own reserve and
PASSed 40/40 (`apparatus/defines/vcpkg-s3/`, `transcripts/explore/vcpkg-s3/`); it is kept as a
second operation of a tool counted once, and wallabag is set 3's fifth.

## Walls, with what was tried

| Set | Target | Version | Stopped at | Tried before calling it a wall |
|---|---|---|---|---|
| 1 | etcd `etcdutl defrag` | 3.7.3 (static Go) | `multiple_threads_detected` (supervised) | `GOMAXPROCS=1` declared; `strace -f`: one run of pwrites to `db.tmp.*` moves from one OS thread to another midway |
| 1 | Dolt | 2.6.0 (static Go) | the same | `GOMAXPROCS=1`; a second operation, `dolt sql -q UPDATE` |
| 1 | Grafana `grafana cli` | 13.2.4 (static Go) | gate accepted (17 ops, one writer), explore refused 3 of 3 | the wrapper `/usr/sbin/grafana` unwrapped; `grafana.db` scratch with a checker; `GOMAXPROCS=1` |
| 1 | vmrestore | 1.154.1 (static Go) | `multiple_threads_detected` (supervised) | `-concurrency=1 -skipFilePreallocation`, `GOMAXPROCS=1` |
| 1 | sqlx-cli | 0.9.0 | `multiple_threads_detected` | the main thread and sqlx's own per-connection worker both fsync the WAL; no runtime switch reaches the worker |
| 1 | Chroma | 1.5.9 | `multiple_threads_detected` | `TOKIO_WORKER_THREADS=1` |
| 1 | Lerna | 10.1.1 | `multiple_threads_detected`, all three modes | nx's cache moved out of the state (`NX_WORKSPACE_DATA_DIRECTORY`, `NX_CACHE_DIRECTORY`); `UV_THREADPOOL_SIZE=1`: the pool's one thread writes the `package.json` files asynchronously while the main thread writes `lerna.json` synchronously, so two threads remain |
| 2 | Gogs `restore` | 0.14.3 (static Go) | `multiple_threads_detected` | supervised with `GOMAXPROCS=1`; a dynamic cgo build of the tag under `--observe syscalls`; strace: writes other than the database's already come from two threads |
| 2 | gqlgen | 0.17.98 (static Go) | `multiple_threads_detected` (supervised) | strace: `models_gen.go` and `schema.resolvers.go`/`generated.go` written by different threads, each with `O_TRUNC` (a forecast of the developer's resolvers lost, not a verdict) |
| 3 | JuiceFS `config` | 1.4.2 (static Go) | `multiple_threads_detected` (supervised) | `GOMAXPROCS=1` declared: the first explore passed the threads question, the second met another OS thread opening the journal; `_journal=DELETE` in the metadata URL |
| 4 | Navidrome | 0.64.2 (static Go, cgo SQLite) | `scan --full` at the gate; `backup restore` through the gate and refused in explore | `GOMAXPROCS=1` and the scanner's and artwork's parallelism at 1: writers down from six threads to three; `strace -f`: four threads `pwrite64` the database and journal |

Dokku 0.38.32 was set 3's first reserve and is out on the box, not on a wall: its postinst and
`apps:create` expect systemd as PID 1, the configuration directory is never made, and filling it in by
hand would be a road no user takes.

## What the four sets say about Sideeye

1. **Static Go is the wall of this run: eight of eleven.** etcd, Dolt, Grafana, vmrestore, Gogs,
   gqlgen, JuiceFS and Navidrome are one shape. Under `--observe supervised` the Go runtime hands a
   goroutine to another OS thread around a blocking call, so one sequential writer reads as two
   threads, and supervised records no join or creation to order them (`threads_supervised`).
   `GOMAXPROCS=1`, the switch `docs/apparatus.md` names for Go, does not stop the handoff. And because
   the handoff is a race, **an accepted `preflight --twice` does not predict the explore's answer**
   (Grafana, JuiceFS, Navidrome's restore: accepted with one writer, refused with two).
2. **A target that closes every descriptor in a child is sent to "refused by design" when supervised
   judges it.** Flyway (the JVM's `jspawnhelper` running `uname -o`) and Salt (onedir Python closing
   each descriptor it reads from `/proc/self/fd`, not through `close_range`, which v1.15.0 handles)
   close the shim's trace and are refused `unresolvable_path`; the next step says the refusal is by
   design. Named by hand, `--observe supervised` judged both — Flyway PASS, Salt FAIL. The entry gate
   counts such a target red for the same reason.
3. **`readahead(2)` is refused as an unsupported call** (RocksDB's buffered reads). It changes
   nothing on disk, as `syncfs` and `sync_file_range`, which v1.16.0 passes over (#970), do not;
   `use_direct_reads=true` routed around it here.
4. **Prisma's `child_touched_state_dir` names a cause the trace does not show.** The refusal says a
   relative path could not be resolved against the child's cwd; the oracle's record shows Node
   changing directory in the child and the schema engine's thread opening `dev.db` by an **absolute**
   path, then only `pread` and locks (`transcripts/lab-s1e-prisma-oracle/grep.txt`). The database was
   moved out of the state, which the operation only reads.
5. **A no-op `mkdir` of an existing directory counts as a write for the threads question** (Lerna's
   main thread, `mkdir` of the state root), the shape 2026-10-22 met in vercel and codex.

None of these is a wrong verdict: every FAIL above replayed. Where a PASS declared a database or its
journal scratch (Turso, wallabag, Firefly III, Flyway), a checker that opens the database judged every
world instead of the bytes.

## Already known upstream?

Each FAIL's tracker was read (searches in `transcripts/set-N-notes.md`, "Known upstream"):

| Target | Known? |
|---|---|
| diesel_cli | no hit (five searches); the file is regenerable |
| Prisma | no hit (seven searches in `prisma/orm`) |
| Symfony secrets | no hit |
| Nextcloud | the same file emptied on a **full disk**: nextcloud/server#31869 and #18620, closed by a free-space check (#33921); the kill window between `ftruncate` and `fwrite` is still there |
| Docusaurus | no hit |
| vcpkg | no hit |
| systemd-sysusers | no hit; #43269 fixed the opposite direction |
| Vagrant | #6680 (2015) reports a corrupt index, which raises an error; an empty one read silently as no machines is not reported |
| Salt | no hit |
| Godot | godotengine/godot#45354 (an empty file written when the disk is full, open since 2021) is the same write; the converter's "already converted" stamp is not reported |
| Luanti | no hit |
| Paperless-ngx | the symptom (file and row disagree after a rename) in #5614 and #12386, both closed |
| COLMAP | no hit |

The owner chose five to draft: Nextcloud, Symfony, Vagrant, systemd-sysusers and Salt (2026-10-25;
Salt and COLMAP were the two set aside first, Salt then brought back as a silent loss at a project that
answers 7 of 10). Each was reproduced without Sideeye, by `strace -e inject=…:signal=KILL` in the set's
box (`transcripts/repro-s2-php.txt`, `transcripts/plain-repro-s3.txt`, `transcripts/recover-sysusers-262.txt`):

- **systemd-sysusers on upstream's v262.1** (`apparatus/sets/3s/`, built from the tag) FAILs as 257
  did, 3/46 at the same crash points, replayed twice (`transcripts/explore/sysusers-262/`). Killed
  before the sixth or the eighth of its eight renames, a rerun does not repair it; before the seventh,
  it does.
- **Vagrant is milder than the table above first said.** After the kill, running Vagrant in a
  machine's own project puts it back in the index (`transcripts/plain-repro-s3-vagrant-recover.txt`);
  what is lost until then is the list across projects. Its draft opens "No data is lost by this".
- Drafts, not filed: `report-symfony.md`, `report-vagrant.md`, `report-salt.md`. Nextcloud's
  `AI_POLICY.md` and systemd's `docs/CONTRIBUTING.md` ask for an issue in the contributor's own words,
  so for those two the owner writes and the agent may only translate; no draft was made.
