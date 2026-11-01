# 2026-11-01 — ADR 0110's first reopen condition, measured from re-recorded traces (#958)

ADR 0110 declined power loss as the next crash model, and its first reopen condition is
whether a power-loss rule would separate targets or fail nearly all of them. Its own figures
came from funnel notes and from committed `write-paths-*.txt` excerpts. Those excerpts cannot
answer it: their filter drops every `O_RDONLY` line, so the `openat` of a directory is gone and
an `fsync(4)` cannot be told apart as a file's or a directory's; they carry no descriptor
annotations; and they stop at fourteen lines. This run re-records the traces instead.

## The rows, counted before anything ran

From `docs/target-classes.md` at `6011b492`, its first table ("Measured, with verdicts" — the
page's supported classes): **a row is in scope when its "What happened" cell begins with
`**PASS`**. 85 rows. (A count of rows that mention PASS anywhere in the row gives 99; the
fourteen more begin with something else.)

Each row is either re-recorded or carries the reason it was not:

- **Re-recorded: 46 rows**, listed in `apparatus/targets.tsv` with the box and the define each
  uses. A row is re-recorded when some record of it names a box still on this machine and keeps
  the define that box ran — its own record (`sideeye-ud1003`, `sideeye-ud1005`,
  `sideeye-ud1007`, `sideeye-fu3-1009`, `sideeye-m1014`, `sideeye-sv1012`, `sideeye-sv170`) or a
  later one: zstd and todo.txt-cli as `2026-10-31-syscalls-under-supervised` ran them
  (`sideeye-fu3-1009` with that record's `item4` define; `sideeye-ud1007` with the release
  tarball at `/opt/todo`), RocksDB as `2026-10-29-refusals-988-990` ran it (`sideeye-r1029`,
  `2026-10-25-shipped-v1160`'s `ldb` define). Where a record kept several defines for one target,
  the one its PASS was measured with is used: `joplin-check3`, `beets-check`, `kvantum-fat`,
  `keepassxc-fat`, `rumdl-nocache`.
- **Not re-recorded: 39 rows**, each listed at the end of this page with its reason — 38 because
  no box any record of them names is on this machine, one (busybox-static) because its record
  kept no define. Their committed excerpts are not read in their place: they drop the lines this
  measurement needs and can cut a rename off.

## How each row is re-recorded

`apparatus/record.sh`, in the row's box (`--privileged --cgroupns=private --network none`, as
the records ran): the define's `seed.sh`, then its `setup`, then the operation once under
`strace -f -y -qq` from the define's `cwd`, with the run's environment (`env.sh` files, the
define's `env:` apparatus entries; `preload:` entries are not loaded — they pin clocks and
randomness, which decide no sync). The trace keeps every call that writes, names or syncs:
`write`, `pwrite64`, `writev`, `pwritev`, `pwritev2`, `sendfile`, `copy_file_range`,
`fallocate`, `ftruncate`, `truncate`, `openat`, `openat2`, `creat`, `renameat`, `renameat2`,
`linkat`, `symlinkat`, `unlinkat`, `mkdirat`, `fsync`, `fdatasync`, `sync_file_range`,
`syncfs`, `sync`, `msync`, `chdir`, `fchdir` (no `open`: every box is `aarch64`, which has none).
Before the operation runs, the state directory's names are listed (`pre.txt`): a trace cannot say
whether a create met a name already there. Every box is `aarch64`, where the path calls
exist only in their `*at` forms, and strace 6.13's `-y` prints `AT_FDCWD</cwd>` and each
descriptor's path, so every path resolves without tracking the working directory.

## The two rules, and what a trace decides under each

Only changes inside the define's state directory count.

- **(b) "a rename persists before its data"** (ext4 before `auto_da_alloc`, 2009): a rename into
  the state directory whose source was written by the run, with no `fsync` or `fdatasync` of
  that source between its last write and the rename, can leave the new name holding nothing.
  Such a rename is a **(b) candidate**. A rename whose source the run did not write is counted
  apart, not judged.
- **(a) "anything unsynced is lost"**: each file's content goes back to its last
  `fsync`/`fdatasync` (a file created in the run, never synced, is empty), and each name — a
  create, rename, unlink, link or mkdir — goes back to what it was at its directory's last sync
  after the change. Every name the run changed is then compared with the state before the
  operation and the state after it: **all lost** (every name as before — a checker passes, and a
  define with a marker loses an update the tool reported done), **all kept**, **old and new
  mixed**, or **neither old nor new** (some name ends up as it was at no point: an empty file, or
  a temporary file left behind — the candidates).

`sync_file_range` is not a sync (ADR 0110). `syncfs`, `sync` and `msync` are counted as seen and
named, not applied. A create (`O_CREAT`) of a name `pre.txt` does not list, and the run had not
made, is a new name.

## Controls

`apparatus/tabulate.py --selftest` runs the predicates over hand-written traces: a rename with
no sync, with the source synced, with another file or the directory synced instead, a rename
after which the source is synced, a prefix-sharing name, a relative path through `AT_FDCWD`,
and directory syncs before and after. `apparatus/controls/` holds three real targets recorded
the same way: `nosync` (`spike/faq/2026-10-10/box/fsync/nosync.py`: write, no sync, rename),
`syncfile` (the file synced, the directory not — the rename is lost, so the new content is
reached by no name: all lost) and `sync` (file and directory synced: all kept).

## The rows not re-recorded

| Line | Target | Record | Why not re-recorded |
|---|---|---|---|
| 37 | taskwarrior | `(none named)` | no box of this record is on this machine |
| 41 | todoman | `spike/dogfood-todoman.sh` | no box of this record is on this machine |
| 51 | papis | `spike/cohort3` | no box of this record is on this machine |
| 58 | mid3v2 (mutagen) | `spike/dogfood/2026-09-06-userview-2` | no box of this record is on this machine |
| 61 | bsdtar (libarchive) | `spike/dogfood/2026-09-06-userview-2` | no box of this record is on this machine |
| 62 | isort | `spike/dogfood/2026-09-06-userview-2` | no box of this record is on this machine |
| 65 | sqlfluff | `spike/followup-item4` | no box of this record is on this machine |
| 66 | virtualenv 20.31.2 | `spike/dogfood/2026-09-16-threads-take-turns` | no box of this record is on this machine |
| 71 | rsync 3.4.1 | `spike/dogfood/2026-09-11-past-walls` | no box of this record is on this machine |
| 72 | newsboat 2.36 | `spike/dogfood/2026-09-11-past-walls` | no box of this record is on this machine |
| 73 | ansible-core 2.19.11 | `spike/dogfood/2026-09-13-cgroup-559` | no box of this record is on this machine |
| 82 | zoxide 0.9.x | `spike/dogfood/2026-09-16-userview-3` | no box of this record is on this machine |
| 83 | pip 25.1.1 | `spike/dogfood/2026-09-16-userview-3` | no box of this record is on this machine |
| 84 | sphinx 8.x | `spike/dogfood/2026-09-16-userview-3` | no box of this record is on this machine |
| 87 | xz 5.8.1 | `spike/dogfood/2026-09-16-crossed-walls` | no box of this record is on this machine |
| 89 | hatch 1.18.0 | `spike/dogfood/2026-09-16-outside-git` | no box of this record is on this machine |
| 96 | busybox-static 1.35.0 (Debian bookworm) `sed  | `spike/dogfood/2026-09-27-supervised-static` | the record kept no define |
| 178 | fish 4.0.2 `set -U` | `spike/dogfood/2026-10-06-read-only-684` | no box of this record is on this machine |
| 207 | cookcli 0.38.0 `pantry add dairy eggs --quant | `spike/dogfood/2026-10-09-user-data-4` | no box of this record is on this machine |
| 210 | libdeflate 1.26 `libdeflate-gzip notes.txt` | `spike/dogfood/2026-10-09-user-data-4` | no box of this record is on this machine |
| 215 | hunspell 1.7.5 `-a -d en_US -p my.dic` | `spike/dogfood/2026-10-09-user-data-4` | no box of this record is on this machine |
| 216 | buildx 0.38.0 `create --append --name b1 --no | `spike/dogfood/2026-10-09-user-data-4` | no box of this record is on this machine |
| 219 | IfcOpenShell's ifcpatch 0.9.0 `-i model.ifc - | `spike/dogfood/2026-10-09-user-data-4` | no box of this record is on this machine |
| 221 | ATAC 0.23.1 `request new demo/pong …` | `spike/dogfood/2026-10-09-user-data-4` | no box of this record is on this machine |
| 223 | Redpanda's rpk 26.2.2 `profile use a` | `spike/dogfood/2026-10-09-user-data-4` | no box of this record is on this machine |
| 225 | Home Assistant 2026.10.0 `hass --script auth  | `spike/dogfood/2026-10-09-followups` | no box of this record is on this machine |
| 233 | mu 1.12.9 `move` | `spike/dogfood/2026-10-09-followups-2` | no box of this record is on this machine |
| 234 | monero-wallet-cli 0.18.5.1 `set_description` | `spike/dogfood/2026-10-09-followups-2` | no box of this record is on this machine |
| 235 | git 2.47.3 `commit` | `spike/dogfood/2026-10-09-followups-2` | no box of this record is on this machine |
| 236 | firebase-tools 15.32.1 `experiments:disable` | `spike/dogfood/2026-10-09-followups-2` | no box of this record is on this machine |
| 237 | gocryptfs 2.6.1 `-passwd` | `spike/dogfood/2026-10-09-followups-2` | no box of this record is on this machine |
| 242 | dotenvx 2.34.2 `native up`, `native down`, `1 | `spike/dogfood/2026-10-10-dotenvx` | no box of this record is on this machine |
| 243 | dotenvx 2.34.2 `gitignore --pattern` | `spike/dogfood/2026-10-10-dotenvx` | no box of this record is on this machine |
| 297 | gdbmtool 1.24-2 storing three keys | `spike/dogfood/2026-10-15-authoring` | no box of this record is on this machine |
| 300 | Turso 0.8.3 `tursodb`, one UPDATE | `spike/dogfood/2026-10-25-shipped-v1160` | no box of this record is on this machine |
| 302 | Flyway 13.11.1 `migrate` | `spike/dogfood/2026-10-25-shipped-v1160` | no box of this record is on this machine |
| 311 | FreshRSS 1.30.4 `reconfigure.php` | `spike/dogfood/2026-10-25-shipped-v1160` | no box of this record is on this machine |
| 312 | wallabag 2.6.14 `wallabag:import` | `spike/dogfood/2026-10-25-shipped-v1160` | no box of this record is on this machine |
| 317 | Firefly III 6.7.9 `firefly-iii:correct-databa | `spike/dogfood/2026-10-25-shipped-v1160` | no box of this record is on this machine |
