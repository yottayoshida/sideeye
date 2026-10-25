# Set 3 notes — system and ops tools (scout 4), for RESULTS.md and SELECTION.md

Engine: the released v1.16.0 in every box (`sideeye-sv1025-s3` and the three built on it: `-s3b` Dokku,
`-s3c` vcpkg, `-s3d` wallabag). Boxes: `apparatus/sets/3{,b,c,d}/Dockerfile`, logs `transcripts/build-set3*.txt`.

## The five explored, and what each did

| Target | Version | Operation → state | Gate | Explore | What a crash leaves | Known upstream |
|---|---|---|---|---|---|---|
| systemd-sysusers | Debian trixie 257.13 (upstream 262.1) | `systemd-sysusers --root=R app.conf` (one group, one user, one membership) → R/etc/{passwd,shadow,group,gshadow} | 0, 45 ops | **FAIL 3/46** by the checker (pwck/grpck -r -R, every old account kept); replayed twice | the four files are renamed into place one after another (group, gshadow, passwd, shadow): between two renames the databases disagree. **Re-running sysusers repairs 1 of the 3** (`transcripts/recover-sysusers-k.txt`): kill at 43 leaves group `appsvc` in group but never in gshadow; kill at 45 leaves user `appsvc` in passwd with no shadow line, and `add_user` returns as soon as passwd has the name. Every pre-existing account survives | not found (search API: `sysusers shadow` 66 hits, `sysusers gshadow` 30; nearest #43269, the reverse case, merged 2026-08; #24324 fsync) |
| Vagrant | 2.4.9 gem built from the v2.4.9 tag on trixie's Ruby 3.3 (upstream ships no linux/arm64 build) | `vagrant global-status --prune` → VAGRANT_HOME (machine index) | 0, 35 ops | **FAIL 25/36** L0; replayed twice | `unlocked_save` opens the index `"w"` (truncate) then writes; the kill leaves 0 bytes. `JSON.load("")` is nil in Ruby, so the next Vagrant reads **no machines and no error** — the checker (`global-status` exits 0) passed in every world | #6680 (2015, "Corruption of vagrant data file", closed; mitchellh: "If we can find a repro case…") — the corrupt-JSON half; the silent empty half not found |
| Vagrant, a live machine kept (`vagrant-live`) | same | the same, with a sixth entry for a project that exists and a stand-in `VBoxManage` (declared `note:`) answering running, so prune keeps it | 0, 52 ops | **FAIL 37/53** (L0 and the checker); replayed twice | in 7 worlds the live machine is gone from `global-status` with exit 0 | as above |
| Salt (`salt-call --local grains.setval`) | 3008.4 onedir, linux-arm64 | masterless minion config dir → `grains` | default 1 (`unresolvable_path`) | default and `--observe syscalls`: **UNKNOWN unresolvable_path**; `--observe supervised` named (not what the next step said): **FAIL 1/3**, the checker; replayed twice | `grains.setval` opens `grains` with `O_TRUNC` and dumps YAML; killed there, the file is empty and `grains.item` returns every grain as `""` — **all user-set grains lost, read back as unset, no error** | not found (`grains file empty` 404 hits, none on this; `grains.setval truncated` 0) |
| FreshRSS | 1.30.4 (tag tarball), PHP 8.4.27 | `cli/reconfigure.php --title … --base-url …` → data/ (DATA_PATH) | 0, 6 ops | **PASS 7/7**, checker (config.php is an array, instance salt unchanged, `list-users.php`) | temp file, copy to `.bak.php`, rename | — |
| wallabag | 2.6.14 release tarball (Symfony 4.4.51), PHP 8.4, SQLite | `wallabag:import wallabag second.json --importer=v2` (4 articles into a database holding 6) → data/db | 0, 87 ops (after pinning the clock) | **PASS 88/88** by the checker with the database and journal scratch (integrity_check, `wallabag:export` lists the 6 old titles) | rollback journal; SQLite's own recovery restores. Under L0 alone the same define is FAIL 20/88 (`transcripts/explore/wallabag-l0/`) — the newsboat/buku lesson again | — |

## Walls and the boxes that could not hold a target

- **JuiceFS 1.4.2** (`juicefs config sqlite3://…?_journal=DELETE --capacity …`): static Go, supervised. `multiple_threads_detected`: tid 380 opened jfs.db, tid 383 the journal. Tried `GOMAXPROCS=1` exported and declared (`env:GOMAXPROCS=1`): the first run of `--twice` passed, the second split the same way (tid 38 / tid 43) — the Go runtime moves a goroutine to another OS thread after a blocking call, and the tool has no switch. Other metadata engines (Redis, TiKV, PostgreSQL) need a server; badger maps its files. Recorded as the threads wall. `transcripts/try/juicefs.*`, `transcripts/entry-out/entry/juicefs.*`.
- **Dokku 0.38.32** (first reserve): packagecloud's trixie .deb unpacks, but its postinst and `apps:create` call systemd (PID 1 in a container is not), so `/var/lib/dokku/config/<app>` is never made and `config:set` fails with "Unable to create temporary environment file". Filling the directories by hand would change the path a user's install takes, so it is out as "the box cannot install it as a user would", not as a Sideeye wall. `transcripts/build-set3b.txt`.
- **gqlgen** (second reserve): skipped — set 2 already took it (`apparatus/sets/2b`).
- **vcpkg** (third reserve): measured, then found doubled. Set 3 explored `vcpkg remove utfcpp` (tool 2026-09-26, ports 817892b0, nlohmann-json + utfcpp installed at build): **PASS 40/40** with the checker (`vcpkg list` keeps nlohmann-json, its header on disk) — the removal is journaled (`updates/incomplete` → rename) before any file is deleted. At 12:48:30, twelve seconds after this explore finished, set 2 wrote its own `defines/vcpkg` (zlib/bzip2 on `/opt/vcpkg-proto`, box `sets/2b`, added at 12:47:50 — after this set checked 2b for vcpkg). Set 3's define is kept as `defines/vcpkg-s3`, its transcripts as `transcripts/explore/vcpkg-s3/`; it ran from the path `defines/vcpkg/` before the overwrite (the json's judged paths name nlohmann-json, cwd /opt/vcpkg). **The entry-gate files `entry-out/entry/vcpkg.*` are set 2's now**; set 3's gate row is in `transcripts/explore-s3-c.txt` (accepted, 39 operations). To keep twenty distinct tools, set 3's fifth is wallabag; vcpkg-s3 is an extra record of the same tool.
- **wallabag** (fourth reserve): the fifth.

## Next steps tried before calling a wall

- Salt: the gate's answer was a class wall (`unresolvable_path`, `trace-closed-by-target`); `--observe syscalls` the same; `--observe supervised`, which no sentence named, accepted 2 operations and judged. Why the default mode cannot: under strace the onedir's Python (relenv) closes a child's descriptors between fork and exec by reading `/proc/self/fd` and calling `close()` on each — no `close_range` (0 calls) — so the shim's trace descriptor is closed by an ordinary `close` (`transcripts/try/salt-grains.*`; pid 23 `which selinuxenabled`, 6 closes before its exec). v1.15.0's fix covers `closefrom`/`close_range` only. **A Sideeye-side candidate**: the refusal sends the reader to "refused by design", where `--observe supervised` judges the run.
- JuiceFS: `GOMAXPROCS=1` (above).
- wallabag: `--twice` split on the import's timestamp; pinned with libfaketime (`preload:libfaketime`, `env:FAKETIME=2026-01-01 00:00:00`, the 2026-10-12 KeePassXC/FreeCAD form). Then L0 FAIL on the raw database bytes; scratch database + journal and the checker after SQLite's recovery, as 2026-10-14's sqlite3/Django rows did.

## Sideeye-side observations

- Salt: above. Also the entry gate maps `unresolvable_path` to a wall (gate 1) although supervised crosses it.
- Vagrant's checker passing in every L0 FAIL world is the tool's behaviour (empty index read as no machines), not a weak checker: `vagrant-live` shows the loss the plain checker could not see.
- `apparatus/` collision: the four sets share `defines/` and `entry-out/entry/` by name; two sets taking the same reserve overwrote each other's define and gate transcript.

## Open points for the run

- sysusers was measured on Debian's 257; upstream 262.1's `write_files` renames in the same order (group, gshadow, passwd, shadow; sysusers.c L1063–1091) and `add_user` returns on a passwd hit (L1229–1235). Not measured on 262.1.
- Vagrant is built from the tag with `gem build`, not HashiCorp's installer (which has no linux/arm64 build); it prints "running Vagrant outside of the official installers".
- Rule 11 was not measured for this set.
- Nothing filed, nothing committed. Work directories (state snapshots) moved to `~/.cctmp/set3-ysPIOP` (73 MB); case jsons kept beside each target. Images `sideeye-sv1025-s3`, `-s3b`, `-s3c`, `-s3d` left in place.

## Files

Defines: `apparatus/defines/{salt-grains,sysusers,vagrant,vagrant-live,freshrss,juicefs,vcpkg-s3,wallabag}/`.
Tools: `apparatus/lab-s3.sh` (plain run + strace summary), `try-s3.sh` (preflight under extra flags), `run-named.sh` (explore under a named mode, replay, evidence), `recover-sysusers.sh`, `recover-sysusers-k.sh`, `keep-cases-s3.sh`.
Transcripts: `lab-s3*.txt`, `entry-s3.txt`, `try-s3-1.txt`, `try/`, `explore-s3-{a,b,c,d,d2,d3}.txt`, `explore/<target>/`, `recover-sysusers{,-k}.txt`.
