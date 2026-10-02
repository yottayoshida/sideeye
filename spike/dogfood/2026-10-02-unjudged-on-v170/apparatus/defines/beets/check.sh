#!/bin/sh
# The library must open and still hold the first import in every world.
# (2026-09-16-threads-take-turns/apparatus/run-v18.sh, check-beets.sh, with the path moved.)
n=$(python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute('select count(*) from items').fetchone()[0])" /s/beets/lib/library.db 2>&1) || { echo "library.db does not open: $n"; exit 1; }
[ "$n" -ge 1 ] 2>/dev/null || { echo "library holds $n items; the first import is gone"; exit 1; }
exit 0
