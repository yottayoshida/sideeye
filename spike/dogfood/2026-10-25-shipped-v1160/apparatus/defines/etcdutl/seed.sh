set -eu
# The keyspace is made once per box by a real etcd (500 puts, then 250 deletes, so the defrag has
# free pages to drop) and copied from there before every run: a server per run is slow.
if [ ! -f /s/.etcd-expect ]; then
    mkdir -p /s
    etcd --data-dir /s/.etcd-pristine --listen-client-urls http://127.0.0.1:2379 --advertise-client-urls http://127.0.0.1:2379 \
         --listen-peer-urls http://127.0.0.1:2380 > /s/.etcd-seed.log 2>&1 &
    pid=$!
    i=0; until etcdctl endpoint health > /dev/null 2>&1; do i=$((i + 1)); [ $i -lt 50 ] || exit 1; sleep 0.2; done
    for i in $(seq 1 500); do etcdctl put "k$i" "$(printf '%0200d' "$i")" > /dev/null; done
    for i in $(seq 1 250); do etcdctl del "k$i" > /dev/null; done
    kill $pid; wait $pid || true
    etcdutl snapshot status /s/.etcd-pristine/member/snap/db -w json 2> /dev/null \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["hash"], d["revision"], d["totalKey"])' > /s/.etcd-expect
fi
rm -rf /s/etcd && cp -a /s/.etcd-pristine /s/etcd
install -m 755 /ap/defines/etcdutl/check.sh /s/etcd-check.sh
