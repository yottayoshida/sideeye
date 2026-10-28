set -eu
# Two VictoriaMetrics data directories, made once per box by a real server: the one the user has
# (/s/.vm-old, series `oldmetric`) and the one a backup holds (/s/.vm-backup, taken by vmbackup from a
# snapshot of a directory holding `newmetric`). Each run restores the backup over a copy of the first.
mk() { # <dir> <metric> [<backup dst>]
    victoria-metrics -storageDataPath="$1" -httpListenAddr=127.0.0.1:8428 -loggerLevel=ERROR > /s/.vm-seed.log 2>&1 &
    pid=$!
    i=0; until curl -s 127.0.0.1:8428/health > /dev/null; do i=$((i + 1)); [ $i -lt 100 ] || exit 1; sleep 0.1; done
    python3 -c "
for s in range(20):
    for t in range(50):
        print('$2{series=\"s%d\"} %d %d' % (s, s * 100 + t, 1767225600000 + t * 60000))" \
        | curl -s --data-binary @- 127.0.0.1:8428/api/v1/import/prometheus
    curl -s 127.0.0.1:8428/internal/force_flush > /dev/null
    if [ $# -ge 3 ]; then
        snap=$(curl -s 127.0.0.1:8428/snapshot/create | python3 -c 'import json,sys; print(json.load(sys.stdin)["snapshot"])')
        vmbackup -storageDataPath="$1" -snapshotName="$snap" -dst="fs://$3" -httpListenAddr=127.0.0.1:8420 -loggerLevel=ERROR >> /s/.vm-seed.log 2>&1
    fi
    kill $pid; wait $pid || true
}
if [ ! -f /s/.vm-ready ]; then
    mkdir -p /s
    mk /s/.vm-new newmetric /s/.vm-backup
    mk /s/.vm-old oldmetric
    touch /s/.vm-ready
fi
rm -rf /s/vm && cp -a /s/.vm-old /s/vm
[ -f /ap/defines/vmrestore/check.sh ] && install -m 755 /ap/defines/vmrestore/check.sh /s/vm-check.sh
true
