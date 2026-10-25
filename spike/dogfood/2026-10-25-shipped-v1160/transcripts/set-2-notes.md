# Set 2 — developer tooling (notes for SELECTION.md and RESULTS.md)

Engine: Sideeye v1.16.0, installed by the page's installer (digest `f62e7071…` matched,
`transcripts/build-base.txt`). Boxes: `sideeye-sv1025-s2` (`apparatus/sets/2/Dockerfile`,
`transcripts/build-set2.txt`) and `sideeye-sv1025-s2b` on top of it (`apparatus/sets/2b/Dockerfile`,
`transcripts/build-set2b.txt`) for what the walls were asked next and for the substitute.

## Selection material

The slate is scout 2's first, second, seventh, eighth and ninth rows (`transcripts/scout-2.txt`):
Gogs, Symfony's secrets vault, Docusaurus, drizzle-kit, Nextcloud's `occ`. etcd, Dolt, Diesel and
Grafana, also on scout 2's list, are set 1's.

- **Nextcloud reads fresh.** `fresh.sh occ` says SEEN, and the only hit is the substring of
  "occurrence" (`2026-10-09-user-data-4/SELECTION.md:294`); `fresh.sh nextcloud` is clean. The same
  reading as f2 on 2026-10-09 (a substring hit, `otf2bdf`, is not the tool).
- Substitutes, in scout 2's order: gqlgen, then vcpkg. Lerna, knex and Prisma were not reached.

## Versions (`/versions.txt` in each box)

Gogs 0.14.3 (release tarball, static Go; and the same tag built with cgo by Go 1.27.3, dynamic),
PHP 8.4.27 (Debian trixie), Symfony 8.1.9 (`composer create-project symfony/skeleton:8.1.*`),
Nextcloud 33.0.10 (download.nextcloud.com, `maintenance:install` on SQLite at build), Node 24.22.1
(the LTS line's latest), Docusaurus 3.10.2 (`create-docusaurus` classic template), drizzle-kit 0.31.11
with drizzle-orm 0.45.4 and better-sqlite3 13.0.3, gqlgen 0.17.98 (release binary, static Go),
vcpkg tool 2026-09-26 (`vcpkg-glibc-arm64`) over the registry's 2026.10.16 with zlib 1.3.2#2 and
bzip2 1.0.8#6 built at build.

## Defines (`apparatus/defines/<name>/`)

| Define | State | Operation | Checker |
|---|---|---|---|
| `symfony-secrets` | `/s/sf/config/secrets/prod` | `php bin/console secrets:generate-keys --rotate --env=prod` | `secrets:list --reveal` decrypts all three secrets to their values |
| `nextcloud-occ` | `/s/ncconf` (`NEXTCLOUD_CONFIG_DIR`) | `php /opt/nextcloud/occ config:system:set trusted_domains 1 --value=cloud.example.com` | config.php loads, keeps `secret`, `passwordsalt`, `instanceid`; `occ status` says installed |
| `docusaurus` | `/s/docu/i18n` | `node node_modules/@docusaurus/core/bin/docusaurus.mjs write-translations --locale fr` | every JSON parses; the translator's French messages are still there |
| `drizzle-kit` | `/s/dz/db` | `node node_modules/drizzle-kit/bin.cjs migrate --config drizzle.config.ts` | integrity_check ok, 120 notes; re-running migrate succeeds and leaves 0001's schema |
| `vcpkg` | `/s/vcpkg/installed` | `/s/vcpkg/vcpkg remove zlib` | `vcpkg list` still lists bzip2 with its header; re-running the remove succeeds and leaves no zlib listed or on disk |
| `gogs`, `gogs-dyn` | `/s/gogs` | `gogs restore --config … --tempdir /s/gogsaux/tmp --from <backup.zip>` | app.ini in place, integrity_check ok, admin alice present, her avatar present |
| `gqlgen` | `/s/gql/graph` | `gqlgen generate` | the developer's resolver bodies survive; re-running generate succeeds and the project builds |

Apparatus declared: `symfony-secrets` — `preload:pin-random`, `preload:libfaketime`,
`env:FAKETIME=2026-01-01 00:00:00` (libsodium seals with fresh randomness, and each vault file's first
line carries the write time: the first gate answer was byte-repeatability, offset ~60 of every file,
`1` vs `3` in the time); Node targets — `env:UV_THREADPOOL_SIZE=1` (Docusaurus also
`env:NO_UPDATE_NOTIFIER=1`); Go targets — `env:GOMAXPROCS=1`; vcpkg — `env:VCPKG_DISABLE_METRICS=1`.

Plain runs (`transcripts/lab-s2.txt`): every operation exits 0 and every checker accepts both the
seeded state and the state the operation leaves.

## Entry gate (`transcripts/entry-s2.txt`, `transcripts/entry-out/entry/<name>.*`)

| Define | Answer |
|---|---|
| `nextcloud-occ` | 0, accepted, 3 operations |
| `docusaurus` | 0, accepted, 11 operations |
| `drizzle-kit` | 0, accepted, 46 operations |
| `symfony-secrets` | 1 byte-repeatability → clock pinned → 0, accepted, 24 operations |
| `vcpkg` | 0, accepted, 54 operations |
| `gogs` | 1, static; default `no_shim_marker`, then `multiple_threads_detected` under `--observe supervised` with GOMAXPROCS=1 (tid 64 opened `gogs.db`, tid 67 `gogs.db-journal`) |
| `gogs-dyn` | 0, FOLLOW `--observe syscalls` (`oracle_missed_operation`: Go's raw syscalls); `preflight --twice --observe syscalls` then `multiple_threads_detected` (tid 21 `gogs.db`, tid 24 `gogs.db-journal`; `transcripts/lab-s2-gogs-dyn-syscalls.txt`, `apparatus/pf-mode.sh`) |
| `gqlgen` | 1, static; default `oracle_missed_operation`, supervised `multiple_threads_detected` (tid 194 wrote `models_gen.go`, tid 196 opened `schema.resolvers.go`) |

### The walls, asked further before writing them down

- **Gogs.** GOMAXPROCS=1 under supervised: wall. The same version built with cgo (dynamic) under
  `--observe syscalls`: the same wall. Would keeping the database outside the state (a PostgreSQL
  server) move it? Measured first with `strace -f` on a plain restore: the writes that are not the
  database's — the `rename`s of `custom` and `data/avatars` among them — already come from two thread
  ids (6 from tid 17, 16 from tid 21), so no: the wall is Go moving one goroutine between OS threads,
  which GOMAXPROCS=1 does not prevent and no Gogs switch does. Not tried: there is no setting left.
- **gqlgen.** `strace -f` on a plain `gqlgen generate`: `models_gen.go` opened by tid 32,
  `schema.resolvers.go` and `generated.go` by tid 33 — sequential code in the program, two OS threads.
  Every one of the three is `O_WRONLY|O_CREAT|O_TRUNC` over the file in place, so a crash between the
  truncate and the write of `schema.resolvers.go` would lose the developer's resolver bodies; that is
  a forecast from strace, not a Sideeye verdict.

## Explore (`transcripts/explore-s2.txt`, `transcripts/explore/<name>/`)

| Define | Verdict | Replays | What a crash leaves |
|---|---|---|---|
| `symfony-secrets` | **FAIL 8/25** (L0 from crash point 3; checker from 6) | FAIL, FAIL | The rotation decrypts every secret into memory, overwrites `prod.encrypt.public.php` and `prod.decrypt.private.php`, then seals each secret again (`SecretsGenerateKeysCommand::execute`, `SodiumVault::generateKeys`/`seal`, `file_put_contents(…, LOCK_EX)` at v8.1.9). World 6: the private key file torn, `secrets:list` fails (`sodium_crypto_box_seal_open(): Argument #2 ($key_pair) must be SODIUM_CRYPTO_BOX_KEYPAIRBYTES bytes long`). Worlds 9, 15, 21: the new key is complete but the secret not yet re-sealed — DATABASE_URL, then MAILER_DSN, then STRIPE_SECRET no longer decrypt, and the old key that would decrypt them is overwritten: **the secret is gone**. Worlds 12, 18, 24: `prod.list.php` torn, `bin/console` dies (`SodiumVault::list(): Return value must be of type array, int returned`). |
| `nextcloud-occ` | **FAIL 1/4** (L0 and checker, crash point 3 of 3) | FAIL, FAIL | `config.php` holding neither the old nor the new content: `Config::writeData` (v33.0.10, unchanged on master) does `fopen(r+)`, `flock`, `ftruncate(0)`, `fwrite` — no temporary file, no fsync. A crash after the truncate leaves an empty config: the instance's `secret`, `passwordsalt`, `instanceid` and database settings gone, and Nextcloud reads itself as not installed. |
| `docusaurus` | **FAIL 5/12** (L0 and checker, from crash point 2) | FAIL, FAIL | `i18n/fr/code.json` 0 bytes (and the other translation files in turn): `fs.outputFile` truncates and writes in place (`translations.ts:138`). The translator's French messages are gone. |
| `drizzle-kit` | **FAIL 9/47, L0 only** (from crash point 36) | FAIL, FAIL | `app.db` holding neither the old nor the new bytes mid-commit; the checker accepts every world — SQLite's hot rollback journal (`app.db-journal`, in the state) rolls it back on the next open, the 120 notes are there, and re-running migrate finishes. **Nothing lost**; the L0 verdict is SQLite's journal design. |
| `vcpkg` | **FAIL 4/55, checker (L2)** (crash points 9–12) | FAIL, FAIL | vcpkg journals the removal carefully (`updates/incomplete` written, then renamed to `updates/0000000000`), but the first record is `Status: purge ok half-installed`. Killed after it and before the files go: `vcpkg list` no longer shows zlib, `zlib.h`, `zconf.h` and `info/zlib_1.3.2_arm64-linux.list` stay on disk, and the documented way back — the same `vcpkg remove zlib` — says "The following packages are not installed" and removes nothing. `vcpkg install zlib` (from the build's binary cache) then completes and lists it again, so a remove after that would finish (`replay --leave-crash-state`, measured by hand). Nothing a user wrote is lost; the tree holds orphaned files the tool no longer accounts for. |

The first vcpkg explore was a SETUP ERROR (`operation: /ap/defines/vcpkg/./vcpkg does not exist`,
kept as `transcripts/explore/vcpkg-relative-op/`): a relative first word in a toml resolves against the
toml's directory (`docs/contract-freeze.md`), and the define had written `./vcpkg` meaning `cwd`. The
gate had accepted it because `apparatus/toml2flags.py` makes `state` and `cwd` absolute but hands the
operation over as written, and preflight's `--operation` resolves against `--cwd` — so the gate and the
explore resolved the same define differently. The define now names `/s/vcpkg/vcpkg`; the gap is the
apparatus's (toml2flags), not the engine's.

## Known upstream?

Read on 2026-10-25, nothing written anywhere:

- Nextcloud: nextcloud/server#31869 (config.php nearly empty after `occ maintenance:mode --on` on a
  full disk, closed completed 2022-06-14) and #18620 (complete config reset with a filled disk, closed
  by #33921 "Do not empty config.php file if reading failed"). The fix added a free-space check before
  writing; the truncate-then-write it guards is unchanged, and a kill or power loss between the two is
  not what either issue describes. Same mechanism, different trigger — to be weighed before any report.
- Symfony: searches for the vault's rotation (`secrets:generate-keys rotate`, `SodiumVault`, "secrets
  rotate lost") return nothing about an interrupted rotation.
- Docusaurus: nothing about `write-translations` emptying a translation file.
- vcpkg: nothing for "half-installed" with remove in microsoft/vcpkg-tool or microsoft/vcpkg.
- drizzle-kit: not looked for — nothing is lost.

## Seen on the way, outside Sideeye

- Gogs 0.14.3's `gogs admin create-user` on a fresh SQLite database creates only some of the tables
  (access, action, …; no `user`) and then fails "create user: user already exists: map[name:…]" — the
  box starts `gogs web` for a few seconds first (`apparatus/sets/2/Dockerfile`). Not looked up upstream.
