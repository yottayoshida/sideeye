#!/bin/sh
# The v18 measurement (#539, ADR 0067): virtualenv and beets under the branch build of
# Sideeye — not a release; the transcripts print the branch's version — in both observation
# modes: beets three explores per mode, virtualenv one explore per mode plus one
# `preflight --twice` per mode. One, because virtualenv records 1,381 kill points and an
# explore is that many worlds of two environment builds each under strace — the first
# attempt at three per mode was stopped after its preflight, at about an hour per explore.
# The thread rule is asked on every recording, so virtualenv's evidence per mode is three
# recordings (the two preflight runs and the explore's), and the verdict is one explore's. The two
# defines are the ones the earlier records used, verbatim: virtualenv's from
# `spike/dogfood/2026-09-16-userview-3/apparatus/run-r3.sh`, beets' from
# `spike/followup-item4/run.sh`. Runs in the image `Dockerfile.measure` builds, with Sideeye
# cross-built on the host (`zig build -Dtarget=aarch64-linux-gnu`) and mounted at /se, this
# directory at /hostap and an output directory at /hostout:
#
#   docker run --rm --network none --cap-add=SYS_PTRACE --security-opt seccomp=unconfined \
#       -v <zig-out>:/se:ro -v <this dir>:/hostap:ro -v <out>:/hostout \
#       sideeye-probe:threads-measure sh /hostap/run-v18.sh
#
# The predictions, committed to BUILDLOG.md before this ran: virtualenv is not refused
# `multiple_threads_detected` in either mode and its account counts two writing thread ids
# with a hand-over; beets is refused `multiple_threads_detected` in both modes with a sentence
# naming two workers and no edge between them.
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
R=/localrun
AP=$R/ap
OUT=/hostout
mkdir -p "$AP" "$OUT" "$R/wk"
cp /hostap/mkwav.py "$AP/"
"$SE" --version | tee "$OUT/version.txt"
{ python3 --version; virtualenv --version; beet version; strace -V | head -1; uname -m; } > "$OUT/environment.txt" 2>&1

cat > "$AP/setup-virtualenv.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
python3 -c "
import shutil,sys,os,glob
for p in glob.glob(os.path.join(sys.argv[1],'*')):
    shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) and not os.path.islink(p) else os.unlink(p)
" "$SD"
virtualenv -q --no-download "$SD/v1" >/dev/null 2>&1
EOS
cat > "$AP/check-virtualenv.sh" <<'EOC'
#!/bin/sh
# A crash while the second environment is being made leaves the first one working.
[ -x "$SD/v1/bin/python" ] || { echo "v1/bin/python is missing or not executable"; exit 1; }
"$SD/v1/bin/python" -c "import sys; sys.exit(0)" 2>/tmp/e.txt || {
  echo "v1's python does not run: $(tail -1 /tmp/e.txt)"; exit 1; }
exit 0
EOC
cat > "$AP/setup-beets.sh" <<'EOX'
#!/bin/sh
mkdir -p "$SD/lib" "$SD/in1" "$SD/in2"
python3 /localrun/ap/mkwav.py /tmp/src.wav
lame --quiet --tt Track1 --ta Artist1 --tl Album1 /tmp/src.wav "$SD/in1/t1.mp3"
lame --quiet --tt Track2 --ta Artist2 --tl Album2 /tmp/src.wav "$SD/in2/t2.mp3"
printf 'directory: %s/lib\nlibrary: %s/lib/library.db\nimport:\n  copy: yes\n  write: yes\n  quiet: yes\n  autotag: no\n' "$SD" "$SD" > "$SD/config.yaml"
beet -c "$SD/config.yaml" import -q "$SD/in1" > /dev/null 2>&1
EOX
cat > "$AP/check-beets.sh" <<'EOX'
#!/bin/sh
# The library must open and still hold the first import in every world.
n=$(python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute('select count(*) from items').fetchone()[0])" "$SD/lib/library.db" 2>&1) || { echo "library.db does not open: $n"; exit 1; }
[ "$n" -ge 1 ] 2>/dev/null || { echo "library holds $n items; the first import is gone"; exit 1; }
exit 0
EOX
chmod 755 "$AP"/*.sh

twice() {  # twice <name> <state rel> <setup> <op template> <mode>: recorded, never fatal
  name=$1; rel=$2; setup=$3; optmpl=$4; mode=$5
  SD="$R/st/$mode/$name/pf"; export SD
  state="$SD$rel"; mkdir -p "$state" "$R/wk/$mode/$name/pf"
  op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
  tag="$name.preflight-twice.$mode"
  echo "==================== $tag ===================="
  "$SE" preflight --twice --state "$state" --setup "$AP/$setup" --operation "$op" \
    --shim "$SHIM" --oracle /usr/bin/strace --observe "$mode" --work "$R/wk/$mode/$name/pf" \
    > "$OUT/$tag.txt" 2>&1
  echo "rc=$?"; grep -E "^PREFLIGHT|^UNKNOWN|state-changing|^SETUP" "$OUT/$tag.txt" | head -3
}
run() {  # run <name> <state rel> <setup> <op template> <check> <mode> <rep>
  name=$1; rel=$2; setup=$3; optmpl=$4; chk=$5; mode=$6; rep=$7
  SD="$R/st/$mode/$name/$rep"; export SD
  state="$SD$rel"; mkdir -p "$SD" "$state" "$R/wk/$mode/$name/$rep"
  op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
  tag="$name.$mode.$rep"
  echo "==================== $tag ===================="
  echo "op: $op"
  "$SE" explore --state "$state" --setup "$AP/$setup" --operation "$op" --check "$AP/$chk" \
    --shim "$SHIM" --oracle /usr/bin/strace --observe "$mode" --work "$R/wk/$mode/$name/$rep" \
    --json "$OUT/$tag.json" > "$OUT/$tag.txt" 2>&1
  echo "rc=$?   (0=PASS 1=FAIL 2=UNKNOWN 3=setup error)"
  grep -nE "^(PASS|FAIL|UNKNOWN|SETUP ERROR)" "$OUT/$tag.txt" | head -2
  grep -nE "crash point|two threads|No thread creation|was detached|divergence" "$OUT/$tag.txt" | head -3 | cut -c1-300
  python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print('processes:',(d.get('processes') or '')[:420])" "$OUT/$tag.json" 2>/dev/null
  echo
}
for mode in wrappers syscalls; do
  twice virtualenv "" setup-virtualenv.sh 'virtualenv -q --no-download @SD@/v2' "$mode"
  run virtualenv "" setup-virtualenv.sh 'virtualenv -q --no-download @SD@/v2' check-virtualenv.sh "$mode" 1
  for rep in 1 2 3; do
    run beets /lib setup-beets.sh 'beet -c @SD@/config.yaml import -q @SD@/in2' check-beets.sh "$mode" "$rep"
  done
done
echo "done"
