# 2026-10-25 shipped-v1160 — selection

The owner's request, 2026-10-25: **"sideeye dogfooding 新規（最新verで当てられるもの） 5OSS x 4セット"** —
twenty tools this project has never met, which the released v1.16.0 can be pointed at, in four sets of
five. Asked how long it was taking, the owner agreed to start each set as soon as its scout returned and
to run the four sets side by side, each in a box of its own (`apparatus/build-set.sh`).

## The conditions

2026-10-12's three (`../2026-10-12-shipped-v1120/SELECTION.md`), moved to v1.16.0, are written out in
`apparatus/scout-brief.md`, the page every scout was given:

1. **Fresh**: `apparatus/fresh.sh` (2026-10-09's copy with `mine` pointed here; its selftest adds
   2026-10-09's and 2026-10-12's own targets, `scw` and SwiftLint, as cases that must read seen —
   green, run before the scouts) and `apparatus/word-recheck.sh` (2026-10-05's, whole words); and the
   project is not one of the 44 repositories in `spike/upstream-reports.tsv`
   (`apparatus/reported-repos.txt`).
2. **Reachable on v1.16.0**: Linux arm64, a CLI, a non-interactive command that changes a file or
   directory the user keeps, no network during it. What v1.13.0–v1.16.0 newly let through (read from
   `CHANGELOG.md`): a directory renamed inside the state (v1.15.0); an open through `_FORTIFY_SOURCE`'s
   `__open_2` and a `close_range` (v1.15.0, #900); calls that change nothing — `syncfs`,
   `sync_file_range`, an empty path (v1.16.0, #970); a tool that changes directory before running a
   helper (v1.15.0); many children whose exec fails (v1.15.0); non-ASCII paths (v1.15.0).
3. **Worth a bug**: at least 10,000 stars, pushed within six months, not archived, issues on; data a
   user would be hurt to lose; not a formatter or a linter's `--fix`. An embedded database's own file
   is allowed, as DuckDB was on 2026-10-12 (rule 7 of `spike/cohort4/SCOUT-BRIEF.md` set aside the
   same way).

Rule 11 is measured and recorded, not used to turn a candidate away: 2026-10-12 took its ten on the
star bar, and the bar here is the same (see below).

## How the twenty were found

Four scouts ran in parallel, each a fresh read-only subagent given one field and the brief; each ran
`fresh.sh`, `word-recheck.sh` and `stars.sh` itself and read the mechanism in the upstream source
through `gh api` where it could. Reports: `transcripts/scout-{1,2,3,4}.txt`.

| Scout | Field | Names | Kept |
|---|---|---|---|
| 1 | databases, storage engines, indexes, queues | ~150 | 10 |
| 2 | developer tooling that changes state in place (not formatters) | 117 | 19 |
| 3 | personal and creative data | ~150 | 15 |
| 4 | Linux system, ops and infrastructure | ~150 | 10 + 5 |

The 59 kept, counted with the tools two scouts both kept, is the `candidates` figure in
`spike/outcome-funnel-campaigns.tsv`; the names put to `fresh.sh`, about 570 across the four, are
approximate because each scout counted spellings and tools its own way.

Most of each field was already met: scout 2 found 66 of 117 seen (package managers above all), scout 4
81 of about 150 (the certificate and backup fields are used up). Three seen answers were substrings of
other words, and those tools were taken as fresh, as `f2` was on 2026-10-09: `occ` (Nextcloud's
command) hit "occurrence", `redis` "rediscovered", `cscli` "pcsclite"; systemd's only hit is a line
in a bug-label screen, the status FreeCAD had when 2026-10-12 took it.

Sets were filled in the order the scouts returned, a tool kept by two scouts going to the first:

| Set | From | Targets | Reserves, in order |
|---|---|---|---|
| 1 | scout 1 | etcd `etcdutl`, Dolt, Turso `tursodb`, diesel_cli, Grafana `grafana cli` | vmrestore, Flyway, sqlx-cli, RocksDB `ldb`, Chroma |
| 2 | scout 2 | Gogs `restore`, Symfony secrets, Nextcloud `occ`, Docusaurus `write-translations`, drizzle-kit | gqlgen, vcpkg, Lerna, knex, Prisma |
| 3 | scout 4 | Salt `salt-call --local`, systemd-sysusers, Vagrant, FreshRSS, JuiceFS | Dokku, gqlgen, vcpkg, wallabag |
| 4 | scout 3 | Paperless-ngx `document_renamer`, Godot `--convert-3to4`, Luanti, Navidrome, Firefly III | COLMAP, Tiled, QGIS, calibre-web |

A target the entry gate refuses on a wall is recorded as walled — after the tool's own switch for one
thread, `--observe supervised`, scratch with a checker, FAT and another place to write were tried, the
lessons of 2026-10-09 — and the set's next reserve takes its place, so each set holds five that
reached a verdict. The walls are in `RESULTS.md`. The sets as they ended:

| Set | The five judged | Walled or out, in the order met |
|---|---|---|
| 1 | diesel_cli, Turso, RocksDB `ldb`, Flyway, **Prisma** (scout 1 spent; taken from set 2's unused reserves, after Lerna) | etcd, Dolt, Grafana, vmrestore, sqlx-cli, Chroma, Lerna |
| 2 | Symfony secrets, Nextcloud `occ`, Docusaurus, drizzle-kit, **vcpkg** | Gogs, gqlgen |
| 3 | systemd-sysusers, Vagrant, Salt, FreshRSS, **wallabag** | JuiceFS; Dokku (the box); vcpkg went to set 2 |
| 4 | Paperless-ngx, Godot, Luanti, Firefly III, **COLMAP** | Navidrome |

Versions moved from the scouts' rows in three places, each in `RESULTS.md`'s table: Luanti 5.17.0 and
COLMAP 4.2.1 were built from their tags (no Linux binary upstream; Debian is several releases behind),
Vagrant 2.4.9 from its tag as a gem (no linux/arm64 installer), and systemd-sysusers and RocksDB are
Debian's (257 against 262.1, 9.10.0 against 11.8.1). Prisma is 7.10.1, GitHub's latest release, where
npm's `latest` names a release candidate.

## Rule 11, recorded (`transcripts/receipts/`)

The last ten bug reports and the first reply from the project within seven days (`apparatus/rule11.sh`,
`score11.py`, 2026-10-09's). Where the first pass took no bug label, the tracker's own label was read
and the row measured again (`rule11-*-2.txt`).

| Repository | Answered within 7 days | Label |
|---|---|---|
| firefly-iii/firefly-iii | 10/10 | any (no bug label) |
| luanti-org/luanti | 9/10 | bug |
| FreshRSS/FreshRSS | 8/10 | Bug (unconfirmed) |
| saltstack/salt | 7/10 | bug |
| diesel-rs/diesel | 6/10 | bug |
| hashicorp/vagrant | 5/10 | bug |
| godotengine/godot | 5/10 | bug |
| facebook/docusaurus | 4/10 | bug |
| etcd-io/etcd | 3/10 | type/bug |
| nextcloud/server | 3/10 | bug |
| paperless-ngx/paperless-ngx | 3/10 | bug |
| dolthub/dolt | 2/10 | bug |
| gogs/gogs | 2/10 | 💊 bug |
| systemd/systemd | 2/10 | bug 🐛 |
| symfony/symfony | 1/3 | Bug |
| juicedata/juicefs | 1/10 | kind/bug |
| navidrome/navidrome | 1/10 | bug |
| tursodatabase/turso | 0/10 | any (no bug label) |
| drizzle-team/drizzle-orm | 0/10 | bug |
| grafana/grafana | 0/10 | type/bug |

Nine fall under 2026-09-28's bar of three. That bears on whether a finding is worth reporting, which
`RESULTS.md` decides per finding, not on whether it is measured.
