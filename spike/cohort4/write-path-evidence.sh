#!/bin/sh
# write-path-evidence.sh - re-derive both cohort-4 candidates' write paths
# from public sources, and print the commands that did it.
#
# Why this exists: the 2026-08-22 himalaya finding (io-maildir std driver,
# no fsync, tmp -> new) lived only in a chat transcript. Nothing in the
# repository could be pointed at, so no diff-level check could reach it.
# This script puts the derivation in a file that a reviewer can re-run.
#
# It reads sources. It never runs either target. Provenance stays
# "assisted": what was read is named here.
#
# Usage: sh spike/cohort4/write-path-evidence.sh <workdir>
set -u
WORK=${1:?usage: write-path-evidence.sh <workdir>}
mkdir -p "$WORK"
echo "== write-path evidence, both candidates"
echo "== date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "== workdir: $WORK"
echo

echo "########## himalaya (Rust) ##########"
echo "\$ git clone --depth 1 --branch v2.1.0 https://github.com/pimalaya/himalaya.git"
[ -d "$WORK/himalaya" ] || git clone --depth 1 --quiet --branch v2.1.0 \
    https://github.com/pimalaya/himalaya.git "$WORK/himalaya"
echo "  HEAD: $(git -C "$WORK/himalaya" log --format=%H -1)  tag: $(git -C "$WORK/himalaya" describe --tags)"
echo

echo "-- the maildir I/O crate, pinned by Cargo.lock"
echo "\$ grep -A3 '^name = \"io-maildir\"' Cargo.lock"
grep -A3 '^name = "io-maildir"' "$WORK/himalaya/Cargo.lock" | sed 's/^/  /'
LOCKSUM=$(grep -A3 '^name = "io-maildir"' "$WORK/himalaya/Cargo.lock" | grep checksum | cut -d'"' -f2)
echo

echo "-- fetch that exact crate and verify it is the one the lockfile pins"
echo "\$ curl -sSL https://static.crates.io/crates/io-maildir/io-maildir-0.3.0.crate"
echo "   (the crates.io /api/v1 download endpoint refuses without a User-Agent:"
echo "    it answers 200 with a JSON data-access-policy error body, 277 bytes.)"
[ -f "$WORK/io-maildir.crate" ] || curl -sSL -A 'sideeye-scout/1.0' \
    -o "$WORK/io-maildir.crate" \
    https://static.crates.io/crates/io-maildir/io-maildir-0.3.0.crate
GOTSUM=$(shasum -a 256 "$WORK/io-maildir.crate" | cut -d' ' -f1)
echo "  sha256 downloaded : $GOTSUM"
echo "  sha256 in Cargo.lock: $LOCKSUM"
if [ "$GOTSUM" = "$LOCKSUM" ]; then
    echo "  MATCH - the source read below is the source that gets built"
else
    echo "  MISMATCH - stop; the source below is not what himalaya builds"
    exit 2
fi
mkdir -p "$WORK/io-maildir"
tar xzf "$WORK/io-maildir.crate" -C "$WORK/io-maildir" --strip-components=1
echo

echo "-- which 'fs' is it? (cargo's wall was a raw syscall, not Rust as such)"
echo "\$ sed -n '9,15p' src/client.rs"
sed -n '9,15p' "$WORK/io-maildir/src/client.rs" | sed 's/^/  /'
echo

echo "-- every filesystem-mutating call in the std driver"
echo "\$ grep -rnE 'fs::(rename|write|copy|remove_file|remove_dir_all|create_dir_all)' src/"
grep -rnE 'fs::(rename|write|copy|remove_file|remove_dir_all|create_dir_all)' \
    "$WORK/io-maildir/src" | sed "s|$WORK/io-maildir/|  |"
echo

echo "-- durability: is anything flushed to disk?"
echo "\$ grep -rcE 'sync_all|sync_data|fsync' src/   (count over the whole crate)"
N=$(grep -rE 'sync_all|sync_data|fsync' "$WORK/io-maildir/src" | wc -l | tr -d ' ')
echo "  $N occurrences"
echo "  control: the same grep for a call that IS present, so a 0 is a measurement"
echo "\$ grep -rcE 'fs::rename' src/"
echo "  $(grep -rE 'fs::rename' "$WORK/io-maildir/src" | wc -l | tr -d ' ') occurrences"
echo

echo "-- per-operation atomicity: the arms differ, and only one has an interior"
echo "\$ head -3 src/entry/store.rs ; head -3 src/entry/copy.rs"
sed -n '1,2p' "$WORK/io-maildir/src/entry/store.rs" | sed 's/^/  store: /'
sed -n '1,3p' "$WORK/io-maildir/src/entry/copy.rs" | sed 's/^/  copy:  /'
echo "\$ grep -n 'build_target_path\|WantsCopy' src/entry/copy.rs"
grep -n 'build_target_path\|WantsCopy(pairs)' "$WORK/io-maildir/src/entry/copy.rs" | head -4 | sed 's/^/  /'
echo

echo "-- threads: where they are, and whether a mutating command reaches them"
echo "\$ grep -rn 'thread::' src/   (io-maildir)"
grep -rn 'thread::' "$WORK/io-maildir/src" | sed "s|$WORK/io-maildir/|  |"
echo "\$ grep -rn 'read_entries' himalaya/src/   (the callers)"
grep -rn 'read_entries' "$WORK/himalaya/src" | sed "s|$WORK/himalaya/|  |"
echo

echo "-- rustix carried, but by whom? (read-only rustix is tolerated; writes are not)"
echo "\$ reverse-lookup of Cargo.lock dependency lists"
python3 - "$WORK/himalaya/Cargo.lock" <<'PYEOF' | sed 's/^/  /'
import sys, re
txt = open(sys.argv[1]).read()
rev = {}
for b in txt.split('[[package]]'):
    m = re.search(r'^name = "(.+?)"', b, re.M)
    if not m:
        continue
    dm = re.search(r'^dependencies = \[(.*?)\]', b, re.M | re.S)
    if not dm:
        continue
    for d in re.findall(r'"([^"]+)"', dm.group(1)):
        rev.setdefault(d.split()[0], []).append(m.group(1))
for t in ('rustix', 'linux-raw-sys'):
    print(f'{t} <- {sorted(set(rev.get(t, [])))}')
PYEOF
echo

echo "########## vdirsyncer (Python) ##########"
echo "\$ git clone --depth 1 https://github.com/pimutils/vdirsyncer.git"
[ -d "$WORK/vdirsyncer" ] || git clone --depth 1 --quiet \
    https://github.com/pimutils/vdirsyncer.git "$WORK/vdirsyncer"
echo "  HEAD: $(git -C "$WORK/vdirsyncer" log --format=%H -1)"
echo "  NOTE: default branch, not a tag - the newest tag v0.20.0 is the PyPI 0.20.0 of 2025-08-28"
echo

echo "-- the single atomic-write helper every local write goes through"
echo "\$ sed -n '208,231p' vdirsyncer/utils.py"
sed -n '208,231p' "$WORK/vdirsyncer/vdirsyncer/utils.py" | sed 's/^/  /'
echo

echo "-- its call sites, with the overwrite flag that decides the shape"
echo "\$ grep -rn 'atomic_write(' vdirsyncer/ --include='*.py'"
grep -rn 'atomic_write(' "$WORK/vdirsyncer/vdirsyncer" --include='*.py' \
    | sed "s|$WORK/vdirsyncer/|  |"
echo

echo "-- does tempfile.mkstemp reach libc mkstemp(3)?  (#39's wall is C-specific)"
echo "\$ python3 -c \"import tempfile, inspect; print(inspect.getsourcefile(tempfile))\""
python3 -c "import tempfile, inspect; print('  ' + inspect.getsourcefile(tempfile))"
echo "\$ python3 -c \"import tempfile, inspect; print(inspect.getsource(tempfile._mkstemp_inner))\" | grep -n 'open'"
python3 -c "import tempfile, inspect; print(inspect.getsource(tempfile._mkstemp_inner))" \
    | grep -n '_os.open\|FileExistsError' | sed 's/^/  /'
echo "  reading: the name loop and the open are Python-level, so an interposer"
echo "  sees the openat. This is the opposite of the C mkstemp(3) case in #39."
echo "  NOT SETTLED HERE: this was read on the host's CPython"
echo "  ($(python3 -V 2>&1)). The image's interpreter is what the probe must confirm,"
echo "  via preflight.sh visibility."
echo

echo "-- threads and the event loop"
echo "\$ grep -rnE 'threading|to_thread|run_in_executor|ThreadPool' vdirsyncer/ --include='*.py'"
grep -rnE 'threading|to_thread|run_in_executor|ThreadPool' \
    "$WORK/vdirsyncer/vdirsyncer" --include='*.py' | sed "s|$WORK/vdirsyncer/|  |"
echo

echo "-- interactivity of the command a checker would want"
echo "\$ grep -rn 'click.confirm' vdirsyncer/ --include='*.py'"
grep -rn 'click.confirm' "$WORK/vdirsyncer/vdirsyncer" --include='*.py' \
    | sed "s|$WORK/vdirsyncer/|  |"
echo

echo "-- the status store (rule 7 reads on the MAIN store; this is the other one)"
echo "\$ grep -rn 'sqlite3\|class SqliteStatus' vdirsyncer/sync/status.py"
grep -n 'sqlite3\|class SqliteStatus' "$WORK/vdirsyncer/vdirsyncer/sync/status.py" \
    | sed 's/^/  /'
echo
echo "== end of evidence"
