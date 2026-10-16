# 2026-10-15 authoring — the ordered candidates, sealed before the screen (#873)

Three contract shapes, one target each. Within a shape the order below is the order of the
screen, and the first candidate that passes `screen.sh` is the target; a candidate the screen
drops is not replaced by a later choice of ours. No candidate was chosen for a known crash bug:
each line's reason is the contract its own documentation states.

**Excluded mechanically** (`exclude.sh`): a candidate whose command or binary package name occurs,
case-insensitively and as a whole word, in any file under `spike/` at `5510fda3` outside this
directory — every target a dogfood run, a cohort, #618 or #861 has named. Source package names are
not used: `gdbm` names a library other runs linked against, not a tool they measured. Read on
2026-10-15 (counts of files): stow 71, restic 13, gpg 90, git-annex 35, rsnapshot 9, sqitch 1,
subversion 8, darcs 6, cvs 6, bzr 5, fossil 59, ucf 2, mandb 1, tdbtool 1, reprepro 1, myrepos 1,
vcsh 1, dirvish 1, rpm 42 — all out. Not in Debian trixie: rdup, mlocate, goose, golang-migrate.

Versions are Debian trixie's on the snapshot date in `Dockerfile`; `screen.sh` installs
`package=version` and refuses another.

The shape sentence is what the subject is given. The legs are the graders' card and are not.

## Shape 1 — related files whose records must agree with each other

1. **quilt** `quilt=0.68-1`. Operation: `quilt push -a` in a source tree whose `patches/series`
   names two patches over two files. Documented contract (quilt(1)): `.pc/applied-patches` lists
   the patches applied to the tree, and `.pc/<patch>/` keeps the files as they were before it,
   which `quilt pop` restores. Legs: (a) every patch `.pc/applied-patches` lists has its changes in
   the working files; (b) no patch it does not list has its changes there; (c) `quilt pop -a` exits
   0 and leaves both files as they were before the operation.
2. **rcs** `rcs=5.10.1-2`. Operation: `ci -l -m'r2' notes.txt` with `notes.txt,v` at revision 1.1
   and the working file edited. Documented contract (ci(1), rcsfile(5)): the archive holds every
   revision, and with `-l` the working file stays, locked, equal to the new head. Legs: (a)
   `rlog notes.txt` exits 0; (b) `co -p notes.txt` equals the working file; (c) revision 1.1 is
   still in the archive with its content; (d) the working file holds the edited content.
3. **etckeeper** `etckeeper=1.18.22-2`. Operation: `etckeeper commit 'r2'` over a tracked
   configuration directory. Documented contract (etckeeper(8)): the commit records the files and
   `.etckeeper` records the metadata git does not. Legs: (a) the committed tree equals the
   directory's files; (b) `.etckeeper` names each tracked file's mode as the file has it.
4. **aptly** `aptly=1.6.1+ds1-3`. Operation: `aptly repo add local pkg.deb` under its own
   `rootDir`. Documented contract (aptly(1)): the database lists a repository's packages and the
   pool holds their files. Legs: (a) every package `aptly repo show -with-packages local` lists has
   its file in the pool; (b) `aptly db cleanup` leaves the listed packages listed.

## Shape 2 — state with a documented restart, recovery or undo path

1. **gdbmtool** `gdbmtool=1.24-2`. Operation: a `gdbmtool` script storing three new keys into a
   database that holds three. Documented contract (the GDBM manual, "Crash Tolerance" and
   "Recovery"; gdbmtool(1) `recover`): a database left by a crash is recovered before use. Legs,
   after `recover.sh`: (a) the database opens; (b) the three keys held before hold their values;
   (c) each new key is absent or holds its new value.
2. **stgit** `stgit=0.19-2`. Operation: `stg refresh` of the top patch of a two-patch stack.
   Documented contract (stg-repair(1), stg-undo(1)): `stg repair` brings the stack back in step
   with the branch after an interruption. Legs, after `recover.sh`: (a) `stg series` exits 0;
   (b) the patches it lists as applied are the branch's commits above the base, in order; (c) the
   first patch's content is unchanged.
3. **xapian-omega** `xapian-omega=1.4.29-1`. Operation: `omindex` over a directory with one file
   added since the last index. Documented contract (omindex(1)): an interrupted run is completed by
   running it again; Xapian keeps the last committed revision readable. Legs, after `recover.sh`:
   (a) `xapian-check` passes; (b) every file indexed before is found by `quest`; (c) the added
   file is found.

## Shape 3 — a migration or other multi-step change of logical state

1. **python3-yoyo** `python3-yoyo=9.0.0+dfsg1-3`. Operation: `python3 -m yoyo apply --batch` (Debian ships yoyo as a module, without the `yoyo` script) of two pending
   migrations (add a column and backfill it; add an index) to a SQLite database with one applied.
   Documented contract (yoyo's documentation, "Transactions"): each migration runs in a
   transaction and is recorded when it commits; running `apply` again applies what is left. Legs,
   after `recover.sh`: (a) each migration recorded as applied has its change in the schema; (b)
   the rows present before hold their values; (c) `yoyo apply --batch` again exits 0 and leaves
   the final schema.
2. **xapian-tools** `xapian-tools=1.4.29-3+deb13u1`. Operation: `xapian-compact db db.new`.
   Documented contract (xapian-compact(1)): the source is read, not changed; the destination is a
   complete database. Legs: (a) the source passes `xapian-check` with its document count; (b)
   `db.new` is absent, or passes `xapian-check` with the same count.
3. **slapd** `slapd=2.6.10+dfsg-1`. Operation: `slapadd` of an LDIF of twenty entries into an
   empty `mdb` database. Documented contract (slapadd(8)): an interrupted load leaves a database to
   be reloaded. Legs, after `recover.sh`: (a) `slapcat` exits 0; (b) every entry it prints is one
   of the LDIF's, whole; (c) loading the LDIF again exits 0 and `slapcat` then prints all twenty.
4. **python3-flask-migrate** `python3-flask-migrate=4.1.0-1`. Operation: `flask db upgrade` of two
   pending revisions on SQLite. Documented contract (Flask-Migrate, Alembic): `upgrade` applies
   pending revisions and records the current one. Legs, after `recover.sh`: (a) the recorded
   revision's schema is the database's; (b) earlier rows hold their values; (c) `flask db upgrade`
   again exits 0.
