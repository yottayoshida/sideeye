#!/bin/sh
# After a crash anywhere in `gogs restore`, the instance still starts and its admin can still log in:
# custom/conf/app.ini is where Gogs reads it, the database passes SQLite's integrity check and holds
# the admin alice (in the instance before the restore and in the archive alike), and alice's avatar is
# where Gogs serves it from.
set -u
d=${SIDEEYE_STATE_DIR:?}
fail() { echo "checker(gogs): $*"; exit 1; }
[ -f "$d/custom/conf/app.ini" ] || fail "custom/conf/app.ini is missing: Gogs starts with no configuration"
[ -f "$d/data/gogs.db" ] || fail "data/gogs.db is missing"
ic=$(sqlite3 "$d/data/gogs.db" 'pragma integrity_check' 2>&1) || fail "the database does not open: $ic"
[ "$ic" = ok ] || fail "integrity_check: $ic"
n=$(sqlite3 "$d/data/gogs.db" "select count(*) from \"user\" where name='alice' and is_admin=1" 2>&1) || fail "user table unreadable: $n"
[ "$n" = 1 ] || fail "the admin alice is not in the database ($n rows): nobody can log in to administer it"
[ -f "$d/data/avatars/1" ] || fail "data/avatars/1 is missing"
exit 0
