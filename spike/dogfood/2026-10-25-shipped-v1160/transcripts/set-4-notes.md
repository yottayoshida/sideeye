# Set 4 — personal and creative data (from scout 3)

Material for RESULTS.md and SELECTION.md. Box `sideeye-sv1025-s4` (`apparatus/sets/4/Dockerfile`,
`transcripts/build-set4.txt`), FROM the run's base `sideeye-sv1025` (Sideeye v1.16.0 by the page's
installer, digest matched). Versions in the box's `/versions.txt` (`transcripts/lab-s4.txt`, head).

## The five, and what each was taken from

| define | tool | version | from | linkage |
|---|---|---|---|---|
| `paperless` | Paperless-ngx `manage.py document_renamer` | 3.3.4 | its release tarball; the pinned `requirements.txt` into a venv on Debian's Python 3.13.5, `mysqlclient` and `psycopg-c` left out (the state is SQLite) | Python, dynamic |
| `godot` | Godot `--headless --convert-3to4` | 4.7.2-stable | `Godot_v4.7.2-stable_linux.arm64.zip` | dynamic |
| `luanti` | Luanti `luantiserver --migrate-players sqlite3` | 5.17.0 | **built from the 5.17.0 tag, server only** (`-DBUILD_CLIENT=FALSE`): upstream ships no Linux binary (apk, Windows and macOS zips only) and Debian trixie carries 5.10.0, seven releases behind. Curl, LevelDB, Redis, PostgreSQL and Prometheus off. Game: devtest from the same tree | dynamic |
| `navidrome`, `navidrome-restore` | Navidrome `scan --full`, `backup restore` | 0.64.2 | `navidrome_0.64.2_linux_arm64.tar.gz` | **static** (Go with cgo SQLite) |
| `firefly` | Firefly III `artisan firefly-iii:correct-database` | 6.7.9 | `FireflyIII-v6.7.9.tar.gz` (vendor included). **Needs PHP 8.5** (`vendor/composer/platform_check.php` refuses Debian trixie's 8.4.27): PHP 8.5.11 from packages.sury.org | PHP, dynamic |

## Defines — what was decided and why

- **Paperless**: six documents, three correspondents, each with an original, an archived version and a
  thumbnail on disk and a row in `db.sqlite3`, built through Django (`make_docs.py`, rows created with no
  filename so no move fires, then files written and the row updated by queryset). The operation is
  Paperless's documented reason to run `document_renamer`: `PAPERLESS_FILENAME_FORMAT` changed, to
  `{{ correspondent }}/{{ title }}`, so every original and archive moves into a correspondent's
  directory (names with spaces: `Tax Office/Letter 1.pdf`). Settings, each through a variable
  Paperless reads: SQLite's WAL (hard-coded in `init_command`, `settings/custom.py`) replaced by
  `PAPERLESS_DB_OPTIONS=init_command=PRAGMA journal_mode=DELETE;…` with every other PRAGMA as shipped;
  no Redis — `PAPERLESS_CACHE_BACKEND` LocMem and `PAPERLESS_CHANNELS_BACKEND` InMemory (without them
  `migrate` and `document_renamer` die on `redis.exceptions.ConnectionError`); the consumption
  directory must exist or every command stops on a system-check error. Checker: Paperless's own
  `document_sanity_checker` (exit status is 0 whatever it finds, so its "No issues detected" line is
  read). `[recovery]`: `document_renamer` again — the code adopts a file already at its new name with the
  stored checksum (`signals/handlers.py`, `original_already_moved`). `media.lock` scratch.
- **Godot**: a Godot 3 project written as the 3.x editor writes one (project.godot config_version=4,
  two format=2 scenes with Spatial/KinematicBody/RigidBody, 3.x GDScript with onready/export/yield).
  Checker: every file is either its seeded bytes or the bytes one uninterrupted conversion gives it
  (references made once per box). `[recovery]`: the conversion run again, then the project must equal the
  one-pass conversion; measured beforehand that converting twice gives the same bytes. `.godot` scratch.
- **Luanti**: **direction changed from the brief's `--migrate-players files` to `files` → `sqlite3`**:
  that is the upgrade a world kept since before sqlite3 became the default makes, and it is the longer
  path — each player saved to `players.sqlite`, its file moved to `players.bak/`, then `world.mt`
  rewritten (`serverenvironment.cpp`, `migratePlayersDatabase`). Five players in the files backend,
  each with health, position, extended attributes and inventory. Checker: every player reads back,
  from the backend world.mt names, with the seeded health and dirt count. `[recovery]`: the migration
  again unless world.mt already names sqlite3 (it then refuses "new backend is same").
- **Navidrome**: a listener's library — two albums scanned, admin made by the server's first start
  (`ND_DEVAUTOCREATEADMINPASSWORD`; `user create` reads a password only from a terminal, `scan` makes
  no schema), play count, rating and star on every track — then a third album lands in the music
  folder (outside the state). The WAL in the default DbPath is replaced through the config file
  (`ND_CONFIGFILE`): **`ND_DBPATH` in the environment is not read** (the debug line "Opening DataBase"
  still names the default). Checker: integrity_check, the admin, the six tracks' annotations, 6 or 9
  tracks.
  - `navidrome` (`scan --full`): **wall, multiple_threads_detected under supervised**. With
    `GOMAXPROCS=1`, 6 writing thread ids; adding `DevScannerThreads = 1` and
    `DevArtworkWorkerConcurrency = 1` (the scanner's and artwork worker's own concurrency,
    `conf/configuration.go`), 3. `strace -f` names the writers: four OS threads each `pwrite64` into
    `navidrome.db` and its journal — the SQLite calls go through cgo on whichever Go thread runs the
    goroutine, and nothing in Navidrome or Go's environment pins that to one thread.
  - `navidrome-restore` (`backup restore --backup-file … --force`): the same database written from one
    call — SQLite's online backup API, `Step(-1)` (`db/backup.go`). The backup is Navidrome's own
    `backup create` of the two-album library; the live database has the third album. One writing
    thread under supervised; this is the define explored.
- **Firefly III**: books made through the classes the UI and API store with (`make_data.php`:
  AccountRepository, TransactionGroupFactory) — Checking and Savings with opening balances, a salary,
  four groceries, rent, a transfer — then `inject.sql` breaks what `correct-database` exists to repair:
  two groceries made uneven, the rent paid to the employer's revenue account. One `correct-database`
  before the data makes the owner's group and the OAuth keys (storage/, outside the state, kept for
  every world). The operation evens the two journals, creates an expense account and moves the rent to
  it, and recomputes every transaction's running-balance columns. Checker: nine journals of two legs,
  each summing to zero or to the value the seed broke it to, Checking 3052.70 and Savings 8500.00,
  rent to "Employer" of either type; running balances (derived) not read. `[recovery]`: the repair
  again, then strict — every journal zero and the rent at the expense account. No `.env`: settings by
  environment (`env.sh`), cache and sessions in memory, logs to stderr.

## Entry gate (`transcripts/entry-s4-first.txt`, `entry-s4.txt`, `entry-s4-restore.txt`)

First pass: godot accepted (19 operations); paperless, luanti, firefly **byte-repeatability** — two
clean runs a second apart wrote different timestamps into the database (`created_at`, `modified`, a
player's row). Fixed by pinning the clock: libfaketime by `/etc/ld.so.preload`, `FAKETIME="2026-01-01
00:00:00"`, `FAKETIME_DONT_FAKE_MONOTONIC=1`, declared as apparatus (2026-10-12's FreeCAD shape). Then
paperless 209, luanti 286, firefly 413 operations accepted. navidrome refused threads (above);
navidrome-restore accepted under supervised, 717 operations (first a DEFINE answer: its env.sh was
missing, so `GOMAXPROCS` was absent — the apparatus check named it).

## Substitute for Navidrome: COLMAP 4.2.1 (`sets/4b`, box `sideeye-sv1025-s4b`)

Navidrome met the threads wall in both forms (the restore was accepted by the gate with one writing
thread, then refused in explore: "a thread was created in an explored world" — which Go thread runs a
cgo call varies between runs), so scout 3's first reserve was taken. COLMAP publishes no Linux binary
and Debian trixie carries 3.10, a major version behind; built from the 4.2.1 tag
(`-DCUDA_ENABLED=OFF -DGUI_ENABLED=OFF -DOPENGL_ENABLED=OFF -DONNX_ENABLED=OFF`, `ninja -j2`). Four build
failures on the way, each a dependency, recorded in `sets/4b/Dockerfile`: Debian's OpenImageIO cmake
file names `/usr/bin/iconvert` (openimageio-tools) and `/usr/include/opencv4` (libopencv-dev); OpenGL
headers are found unconditionally; COLMAP's fetched ONNX Runtime lands where its own cmake does not
look on arm64; `-j4` was killed by the VM's memory while three other sets ran.

Define `colmap`: a sparse reconstruction (one pinhole camera, three images, twelve points seen by all
three, four observations in image 2 moved 30 px) written as text by `make_model.py` and converted to
binary with COLMAP's own `model_converter`; operation `point_filtering --input_path sparse/0
--output_path sparse/0 --max_reproj_error 4` (the in-place form, input and output the same model).
Checker: the model loads with COLMAP itself (`model_converter` to text) and its files agree — every
2D point an image assigns to a 3D point is in that point's track, and every track entry points back.
Plain run: 4 observations filtered, consistent (`transcripts/lab-s4-colmap.txt`). Gate: accepted, 10
operations (`transcripts/entry-s4b.txt`).

## Explore (`transcripts/explore-s4.txt`, `explore-s4b*.txt`, `explore-s4c.txt`, `explore-s4d.txt`)

| define | verdict | replays | recovery | what the crash left |
|---|---|---|---|---|
| `godot` | **FAIL 8/20** (built-in atomicity and the checker) | 2/2 FAIL | **fail** at crash point 7 | every file the converter rewrites is opened with truncation and then written (`FileAccess::open(…, WRITE)`, `project_converter_3_to_4.cpp` 303 and 461): worlds 7, 9, 11, 13, 15, 17, 19 hold one file at **0 bytes** — project.godot, default_env.tres, both scenes, both scripts in turn — its original nowhere. World 8 holds project.godot as the old file with the converter's marker line prepended: **the first thing the converter writes is "; Project was converted by built-in tool to Godot 4"**, before any file is converted, and a second run refuses on that line ("Project was already converted with this tool", line 301). Measured by hand (`transcripts/lab-s4-godot-mixed.txt`): a project whose project.godot carries the marker and whose scripts are still 3.x is refused, and the scripts stay 3.x. The recovery at the earliest exhibit (project.godot 0 bytes, no marker) converts, but the 0-byte project.godot stays without its name, main scene and input map. |
| `luanti` | **FAIL 184/287** (the checker) | 2/2 FAIL | **pass** at crash point 102 | each player is saved to players.sqlite and its file moved to players.bak/ before world.mt names the new backend; in between, world.mt says `files` and the server reads 4, 3, 2, 1 or 0 of the five players (45 worlds each for 4–1, 4 for 0). Nothing lost: every player is in players.sqlite or players/ and in players.bak/; running the migration again finishes it. Not measured: a server started in that state (a missing player joining is created fresh, and a later migration would then save the fresh profile over the migrated row). |
| `paperless` | **FAIL 174/210** (the checker) | 2/2 FAIL | **pass** at crash point 11 | a document's original is renamed into its correspondent's directory, then its archive, then its row updated: in between, the sanity checker reports "Original (or Archived version) of document does not exist" for that document (29 worlds each for #1–#6). Nothing lost: the files are at their new names with the stored checksums, and `document_renamer` run again adopts them (`original_already_moved`). Known as a symptom: paperless-ngx/paperless-ngx#5614 and #12386 (files moved on disk, the database not), both closed completed. |
| `firefly` | **PASS 414/414** (the checker; the database and its journal scratch) | — | not run | every world reads back nine journals, the two balances and the rent at the old or the new account; the repair is one transaction per step or idempotent where it is not. |
| `colmap` | **FAIL 5/11** (built-in atomicity and the checker) | 2/2 FAIL | — | rigs.bin, cameras.bin, frames.bin, images.bin and points3D.bin are each opened with truncation and written over the input model: worlds 2, 4, 6, 8, 10 cannot be loaded ("Camera 1 from rig 1 not found", "Image 3 does not exist in frame 3", or empty), the input model nowhere. No issue found upstream (searches in RESULTS). |
| `navidrome` (`scan --full`) | **wall** at the gate, multiple_threads_detected under supervised | — | — | see Defines |
| `navidrome-restore` | **wall** in explore, multiple_threads_detected under supervised (gate accepted, one writer) | — | — | default mode `no_shim_marker` (static), followed to supervised as the next step named |

### Passes that were thrown away, and why

- **firefly, first explore: FAIL 401/414 — void.** The checker opened the database read-only, and a
  crash inside a transaction leaves a hot journal that SQLite must roll back on open: 127 worlds read
  "attempt to write a readonly database". The other failures were the built-in layer judging
  database.sqlite's bytes alone while its rollback journal held the rest. Re-run with the database and
  journal scratch and a read-write open, the shape 2026-10-14's `sqlite-txn` define used. First-pass
  transcripts moved out of the tree (`~/.cctmp/set4-…/first-pass/`).
- **paperless, first explore**: stopped before it finished, same database shape; re-run with
  `data/db.sqlite3` and its journal scratch. **Second explore: FAIL, earliest exhibit void** — the
  checker rejected on Paperless's global *warning* about an orphaned `__paperless_write_test_<pid>__`
  (the start-up probe a killed run leaves in the media directory). The checker now rejects on ERROR
  lines only; the third run is the one in the table (`transcripts/explore-s4b-first.txt`,
  `explore-s4c.txt`).

### Upstream reads (no writes)

- Godot: godotengine/godot#45354 "Godot writes empty files when there is no space left on disk" (open
  since 2021, 14 comments) is the same truncate-then-write class for the editor's saves; nothing found
  for the 3-to-4 converter, its marker-first order, or resuming an interrupted conversion.
- Luanti: #7701 (migration slow with many players, open), #7697 (progress message); nothing on an
  interrupted migration. The files backend is deprecated; #13986 (remove it) was closed unmerged.
- COLMAP: no issue on in-place model writes or a truncated model.
