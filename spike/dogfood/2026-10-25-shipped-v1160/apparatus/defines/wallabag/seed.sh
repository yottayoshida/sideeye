set -eu
# A wallabag instance's database (SQLite, at the path its parameters.yml names) holding the default user
# and 6 articles with their tags and annotations, imported with wallabag's own importer; the operation
# imports 4 more from a JSON export, the way a user moves a reading list in. The pristine database the
# box's build installed is kept once per container, so every seed starts from it.
mkdir -p /s/wbaux
[ -f /s/wbaux/pristine.sqlite ] || cp /opt/wallabag/data/db/wallabag.sqlite /s/wbaux/pristine.sqlite
cp /s/wbaux/pristine.sqlite /opt/wallabag/data/db/wallabag.sqlite
rm -f /opt/wallabag/data/db/wallabag.sqlite-journal
python3 /ap/defines/wallabag/make_export.py 0 6 /s/wbaux/first.json
python3 /ap/defines/wallabag/make_export.py 100 4 /s/wbaux/second.json
cd /opt/wallabag && php bin/console wallabag:import wallabag /s/wbaux/first.json --importer=v2 --env=prod -n > /s/wbaux/seed-import.log 2>&1
python3 -c 'import sqlite3; c=sqlite3.connect("/opt/wallabag/data/db/wallabag.sqlite"); print("entries", c.execute("select count(*) from wallabag_entry").fetchone()[0])' >> /s/wbaux/seed-import.log
