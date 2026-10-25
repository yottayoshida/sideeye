set -eu
# A RocksDB of 300 keys, compacted into one table file, made once per box and copied before each
# run. One option is set in the OPTIONS file the run loads (--try_load_options): no fallocate — the
# default preallocates the MANIFEST, a call Sideeye refuses. The seed's own info logs are removed, so
# the run's open creates one LOG and renames none (sideeye.toml declares it scratch).
if [ ! -f /s/.rdbd-ready ]; then
    mkdir -p /s
    i=0; while [ $i -lt 300 ]; do i=$((i + 1)); printf 'k%d ==> %0100d\n' $i $i; done > /s/.rdbd-load.txt
    ldb --db=/s/.rdbd-pristine --create_if_missing load < /s/.rdbd-load.txt > /dev/null 2>&1
    ldb --db=/s/.rdbd-pristine compact > /dev/null 2>&1
    o=$(ls /s/.rdbd-pristine/OPTIONS-* | sort | tail -1)
    sed -i -e 's/allow_fallocate=true/allow_fallocate=false/' -e 's/use_direct_reads=false/use_direct_reads=true/' "$o"
    grep -q 'allow_fallocate=false' "$o" && grep -q 'use_direct_reads=true' "$o"
    rm -f /s/.rdbd-pristine/LOG /s/.rdbd-pristine/LOG.old.*
    touch /s/.rdbd-ready
fi
rm -rf /s/rdb && cp -a /s/.rdbd-pristine /s/rdb
install -m 755 /ap/defines/ldb-direct/check.sh /s/rdb-check.sh
