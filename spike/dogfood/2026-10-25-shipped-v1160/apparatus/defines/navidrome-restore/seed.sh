set -eu
# navidrome's library (its seed), backed up with Navidrome's own `backup create` once per box, then
# moved on by one full scan (the third album): the database the restore overwrites is the newer one.
sh /ap/defines/navidrome/seed.sh
. /ap/defines/navidrome/env.sh
if [ ! -f /s/aux/tpl-nd-restore/navidrome.db ]; then
    mkdir -p /s/aux/ndbk /s/aux/tpl-nd-restore && cd /s/nd
    /opt/bin/navidrome backup create -d /s/aux/ndbk > /s/aux/nd-bk.log 2>&1
    mv "$(ls /s/aux/ndbk/navidrome_backup_*.db | head -1)" /s/aux/ndbk/before-third-album.db
    /opt/bin/navidrome scan --full > /s/aux/nd-scan1.log 2>&1
    cp -a /s/nd/. /s/aux/tpl-nd-restore/
fi
find /s/nd -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -a /s/aux/tpl-nd-restore/. /s/nd/
