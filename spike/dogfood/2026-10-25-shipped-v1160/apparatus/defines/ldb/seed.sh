set -eu
# A RocksDB of 300 keys, compacted into one table file, made once per box and copied before each
# run. One option is set in the OPTIONS file the run loads (--try_load_options): no fallocate — the
# default preallocates the MANIFEST, a call Sideeye refuses. The seed's own info logs are removed, so
# the run's open creates one LOG and renames none (sideeye.toml declares it scratch).
if [ ! -f /s/.rdb-ready ]; then
    mkdir -p /s
    i=0; while [ $i -lt 300 ]; do i=$((i + 1)); printf 'k%d ==> %0100d\n' $i $i; done > /s/.rdb-load.txt
    ldb --db=/s/.rdb-pristine --create_if_missing load < /s/.rdb-load.txt > /dev/null 2>&1
    ldb --db=/s/.rdb-pristine compact > /dev/null 2>&1
    o=$(ls /s/.rdb-pristine/OPTIONS-* | sort | tail -1)
    sed -i 's/allow_fallocate=true/allow_fallocate=false/' "$o"
    grep -q 'allow_fallocate=false' "$o"
    rm -f /s/.rdb-pristine/LOG /s/.rdb-pristine/LOG.old.*
    touch /s/.rdb-ready
fi
rm -rf /s/rdb && cp -a /s/.rdb-pristine /s/rdb
install -m 755 /ap/defines/ldb/check.sh /s/rdb-check.sh
