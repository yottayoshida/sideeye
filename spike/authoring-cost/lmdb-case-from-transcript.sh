#!/bin/sh
# The `lmdb-utils` authoring case, rebuilt inside the box — #638's acceptance case.
#
# **None of this was in the repository.** `watch-defines.py` snapshots `*.toml` only, so the
# scripts a define names were never captured; that gap is #639. Every block below is quoted
# VERBATIM from `runs/lmdb-utils/transcript.jsonl`, with the timestamp of the Bash call it
# came from, so a reader checks this against the transcript rather than against prose here.
#
# Run by `reproduce-lmdb-judged-set.sh`, which pipes this in on stdin. Not part of CI.
set -eu

echo "lmdb-utils version: $(dpkg-query -W -f='${Version}' lmdb-utils)  (meta.json recorded 0.9.24-1)"

# --- verbatim, 2026-09-19T07:46:14.379Z ---
mkdir -p /home/user/lmdbcase
cd /home/user/lmdbcase
# base: 30 records that exist before the operation
: > base.txt; i=0; while [ $i -lt 30 ]; do printf "k%04d\nbase-%04d\n" $((i*10)) $i >> base.txt; i=$((i+1)); done
# load: 250 records. Keys k0000..k0249 in order; k0000,k0010,...k0240 overwrite base keys, spread over all three batches
: > load.txt; i=0; while [ $i -lt 250 ]; do printf "k%04d\nnew-%04d\n" $i $i >> load.txt; i=$((i+1)); done

# --- verbatim, 2026-09-19T07:49:00.156Z (the final setup.sh) ---
cat > /home/user/lmdbcase/setup.sh <<'SETUP_EOF'
#!/bin/sh
# Build the pre-operation environment: an LMDB env holding the 30 records of base.txt.
# lock.mdb is LMDB's shared-memory lock table (reader slots, write mutex, a txnid cache),
# written through a MAP_SHARED mapping and rebuilt by the first opener; it holds no data.
# It lives outside the judged state, behind a symlink, so only data.mdb is state.
set -e
here=/home/user/lmdbcase
mkdir -p "$here/state" "$here/lockdir"
rm -f "$here/state/data.mdb" "$here/state/lock.mdb" "$here/lockdir/lock.mdb"
ln -s "$here/lockdir/lock.mdb" "$here/state/lock.mdb"
exec mdb_load -T -f "$here/base.txt" "$here/state"
SETUP_EOF
chmod +x /home/user/lmdbcase/setup.sh

# --- verbatim, 2026-09-19T07:49:00.156Z (the final check.sh) ---
cat > /home/user/lmdbcase/check.sh <<'CHECK_EOF'
#!/bin/sh
# Invariant for `mdb_load -T -f load.txt state` after a crash and restart.
#
# What LMDB promises: a crash never corrupts the environment; it reopens at the last
# committed transaction, whole. What mdb_load does NOT promise: an all-or-nothing load.
# It commits every 100 records (measured on this 0.9.24 build: 250 records = 3 commits),
# so a crash may leave base.txt plus the first 0, 100, 200 or 250 records of load.txt.
# Anything else fails: an env that will not open, a broken tree or page accounting,
# a lost or altered base record, a torn value, a record past a commit point.
here=/home/user/lmdbcase
env=$here/state
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

fail() { echo "$1: $(tail -n 1 "$tmp/err" 2>/dev/null)" >&2; exit 1; }

mdb_stat "$env" >/dev/null 2>"$tmp/err" || fail "env does not open"
mdb_dump -p "$env" >"$tmp/dump" 2>"$tmp/err" || fail "dump fails"
grep -qx 'DATA=END' "$tmp/dump" || fail "dump has no DATA=END"
# A compacting copy walks every page and cross-checks the freelist: it refuses a leak.
mkdir "$tmp/copy"
mdb_copy -c "$env" "$tmp/copy" 2>"$tmp/err" || fail "compacting copy fails"

# Records as key<TAB>value, in the order LMDB returns them.
sed -n '/^HEADER=END$/,/^DATA=END$/p' "$tmp/dump" | sed '1d;$d' |
    sed 's/^ //' | paste - - >"$tmp/got"

for n in 0 100 200 250; do
    head -n $((2 * n)) "$here/load.txt" |
        cat "$here/base.txt" - | paste - - |
        awk -F '\t' '{ v[$1] = $2 } END { for (k in v) print k "\t" v[k] }' |
        LC_ALL=C sort >"$tmp/want"
    if cmp -s "$tmp/got" "$tmp/want"; then
        echo "state = base + first $n records of load.txt" >&2
        exit 0
    fi
done
echo "state is not base + a committed prefix of load.txt ($(wc -l <"$tmp/got") records)" >&2
exit 1
CHECK_EOF
chmod +x /home/user/lmdbcase/check.sh

# --- the define itself, committed: runs/lmdb-utils/revisions/02.toml, observed 07:49:50Z ---
cp /revisions/02.toml /home/user/lmdbcase/sideeye.toml
echo "--- the define under test (revisions/02.toml) ---"
grep -v '^#' /home/user/lmdbcase/sideeye.toml | grep . || true

echo "--- running ---"
/engine/bin/sideeye explore --config /home/user/lmdbcase/sideeye.toml \
    --shim /engine/lib/libsideeye_shim.so --oracle /usr/bin/strace \
    --work /tmp/se-run --json /tmp/se-run.json || echo "engine exit=$?"

echo "--- what the report says about the judged set ---"
for k in '"verdict": "[A-Z_]*"' '"l0": "[^"]*"' '"scratch": \[[^]]*\]' \
         '"l0_judged_paths": \[[^]]*\]' '"l0_judged_paths_omitted": [0-9]*'; do
    grep -o "$k" /tmp/se-run.json || echo "(absent: $k)"
done
