set -eu
# A JuiceFS volume's metadata engine on SQLite (rollback journal: `_journal=DELETE` moves it off WAL,
# whose -shm is a shared writable mapping), formatted with its own CLI over local file storage, and a
# few files written through `juicefs` itself without mounting: the database holds the volume's
# settings and every inode. The object storage lives outside the state.
rm -rf /s/jfs /s/jfsaux && mkdir -p /s/jfs /s/jfsaux/bucket
M="sqlite3:///s/jfs/jfs.db?_journal=DELETE"
juicefs format --storage file --bucket /s/jfsaux/bucket/ --trash-days 0 "$M" homevol > /s/jfsaux/format.log 2>&1
juicefs status "$M" > /s/jfsaux/status-before.json 2>/dev/null
