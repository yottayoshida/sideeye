#!/bin/sh
# What a user meets in each FAIL's checker_earliest state, rebuilt by hand from the evidence table
# (a replay leaves the completed run behind, not the crashed state), without Sideeye:
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-m1014 sh /ap/lab-1.sh
set -u
export PYTHONDONTWRITEBYTECODE=1

echo "### useradd, crash point 46: passwd replaced, shadow, group and gshadow not yet"
sh /ap/defines/useradd/seed.sh
E=/s/useradd/root/etc
cp $E/passwd /tmp/passwd.old
useradd --prefix /s/useradd/root -M -d / -G staff -p '$6$s$h' -s /bin/sh alice
cp $E/passwd /tmp/passwd.new
sh /ap/defines/useradd/seed.sh
cp /tmp/passwd.old $E/passwd- && cp /tmp/passwd.new $E/passwd
wc -c $E/passwd $E/shadow $E/group $E/gshadow
echo "--- pwck -r"; pwck -r -R /s/useradd/root; echo "exit $?"
echo "--- useradd alice again"; useradd --prefix /s/useradd/root -M -d / -G staff -p '$6$s$h' -s /bin/sh alice; echo "exit $?"
echo "--- passwd -S alice"; passwd --prefix /s/useradd/root -S alice; echo "exit $?"
echo "--- userdel alice"; userdel --prefix /s/useradd/root alice; echo "exit $?"
grep -c '^alice:' $E/passwd $E/shadow $E/group $E/gshadow

echo
echo "### dpkg-divert, crash point 11: the diversion recorded, the file not yet moved"
sh /ap/defines/divert/seed.sh
V="dpkg-divert --admindir /s/dv/admin --instdir /s/dv/root"
printf '/usr/bin/tool\n/usr/bin/tool.distrib\n:\n' > /s/dv/admin/diversions
ls /s/dv/root/usr/bin
echo "--- --list"; $V --list
echo "--- --truename /usr/bin/tool"; $V --truename /usr/bin/tool; ls -l /s/dv/root/usr/bin/tool.distrib 2>&1
echo "--- the same --add again"; $V --rename --divert /usr/bin/tool.distrib --add /usr/bin/tool; echo "exit $?"; ls /s/dv/root/usr/bin
echo "--- --rename --remove"; $V --rename --remove /usr/bin/tool; echo "exit $?"; ls /s/dv/root/usr/bin; $V --list

echo
echo "### Alembic: where the batch migration's transactions begin and commit"
sh /ap/defines/alembic/seed.sh
python3 - <<'PY'
import logging
from alembic.config import Config
from alembic import command
logging.basicConfig(format="%(message)s")
logging.getLogger("sqlalchemy.engine").setLevel(logging.INFO)
command.upgrade(Config("/s/al-aux/proj/alembic.ini"), "head")
PY
echo "--- crash point 15's state: revision 1, its table and rows, and the batch's temporary table committed"
sh /ap/defines/alembic/seed.sh
sqlite3 /s/al/app.db "CREATE TABLE _alembic_tmp_notes (id INTEGER NOT NULL, text TEXT, created INTEGER DEFAULT '0' NOT NULL, PRIMARY KEY (id));"
sqlite3 /s/al/app.db "SELECT version_num FROM alembic_version; SELECT count(*) FROM notes; SELECT name FROM sqlite_master WHERE type = 'table';"
echo "--- alembic upgrade head"
python3 -m alembic -c /s/al-aux/proj/alembic.ini upgrade head 2>&1 | grep -E 'OperationalError|already exists' | head -2
echo "--- alembic current"; python3 -m alembic -c /s/al-aux/proj/alembic.ini current 2>&1 | tail -1
