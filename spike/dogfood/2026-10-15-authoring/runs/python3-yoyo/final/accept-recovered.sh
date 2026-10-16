#!/bin/sh
# A state check.sh must accept once recover.sh has run: an apply killed after 0002 committed and
# was marked, before 0003. The operation is killed for real (SIGKILL from inside, after 0002's
# mark_one), so its lock row and whatever SQLite left are the kill's, not hand-made. Without
# recover.sh, `yoyo list` waits 10 s on that lock and fails; this script shows that too.
set -eu
S=${SIDEEYE_STATE_DIR:?}; D=$(cd "$(dirname "$0")" && pwd)
"$D/setup.sh" > /dev/null
cd "$S"
python3 -I - <<'PY' || true
import os, signal, sys
from yoyo.backends import base
from yoyo.scripts import main
orig = base.DatabaseBackend.mark_one
def mark_then_die(self, migration, log=True):
    orig(self, migration, log)
    if migration.id == "0002-add-body-len":
        self.connection.commit()
        os.kill(os.getpid(), signal.SIGKILL)
base.DatabaseBackend.mark_one = mark_then_die
sys.argv = ["yoyo", "apply", "--batch", "--database", "sqlite:///app.db", "migrations"]
main.main()
PY
echo "left by the kill: $(ls -A "$S" | tr '\n' ' ')"
if timeout 30 python3 -m yoyo list --batch --database sqlite:///app.db migrations > /tmp/accept-recovered-list.txt 2>&1; then
    echo "without recovery: list exited 0"
else
    echo "without recovery: list failed: $(tail -1 /tmp/accept-recovered-list.txt)"
fi
