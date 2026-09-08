#!/bin/sh
# 2026-09-08 (item 4, contract v16): the thread wall's targets, judged or refused by what
# their threads wrote, in both observation modes.
#
# The image is the one the 2026-09-07 thread measurement used (`Dockerfile` beside this
# file; `sideeye-reach:2026-09-07` locally). Sideeye itself is cross-built on the host and
# mounted at /se; state and work live on the container's own filesystem (#528: a macOS bind
# mount resolves a restored file's /proc/self/fd/N to " (deleted)" and refuses
# `unresolvable_path` for nothing the target did).
#
# Seven targets. Five are the ones the strace measurement found writing from exactly one
# thread — sqlfluff, vips, zstd, bundler, beets — and the expectation is a verdict. Two are
# controls: git-annex writes from two threads of its own process (and from seventeen git
# children), so the expectation is a refusal that names the second thread; mlr (Go) was
# measured with a writer count that changes between runs, so the expectation is that
# `preflight --twice` or the repeated run below shows it. Every row of the table is the
# report's own headline, copied verbatim, per #528's rule against re-counting.
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
R=/localrun
AP=$R/ap
OUT=$R/out
mkdir -p "$AP" "$OUT" "$R/wk"
cp /hostap/mkwav.py "$AP/"

"$SE" --version

########## setup / checker ##########
# Each reads $SD, which the driver exports; the engine passes the environment through.

cat > "$AP/setup-sqlfluff.sh" <<'EOX'
#!/bin/sh
mkdir -p "$SD"; printf 'select a,b from t where a=1\n' > "$SD/q.sql"
EOX
cat > "$AP/check-sqlfluff.sh" <<'EOX'
#!/bin/sh
[ -f "$SD/q.sql" ] || { echo "q.sql is gone"; exit 1; }
grep -qi select "$SD/q.sql" || { echo "q.sql no longer holds the statement"; exit 1; }
exit 0
EOX

cat > "$AP/setup-vips.sh" <<'EOX'
#!/bin/sh
mkdir -p "$SD"; vips black "$SD/img.png" 64 64
EOX
cat > "$AP/check-vips.sh" <<'EOX'
#!/bin/sh
# The input must survive every world; the output, if present, must be a readable image.
vipsheader "$SD/img.png" > /dev/null 2>&1 || { echo "img.png unreadable"; exit 1; }
[ -e "$SD/out.png" ] && { vipsheader "$SD/out.png" > /dev/null 2>&1 || { echo "out.png present but unreadable ($(wc -c < "$SD/out.png") bytes)"; exit 1; }; }
exit 0
EOX

cat > "$AP/setup-zstd.sh" <<'EOX'
#!/bin/sh
mkdir -p "$SD"; head -c 300000 /dev/urandom > "$SD/a.bin"
EOX
cat > "$AP/check-zstd.sh" <<'EOX'
#!/bin/sh
# --rm removes the input after the output is complete: at least one of the two must be a
# whole file, or the data is gone.
if [ -f "$SD/a.bin" ]; then [ "$(wc -c < "$SD/a.bin")" = 300000 ] || { echo "a.bin truncated"; exit 1; }; exit 0; fi
[ -f "$SD/a.bin.zst" ] || { echo "neither a.bin nor a.bin.zst"; exit 1; }
zstd -t -q "$SD/a.bin.zst" || { echo "a.bin.zst does not decompress and a.bin is gone"; exit 1; }
exit 0
EOX

cat > "$AP/setup-bundler.sh" <<'EOX'
#!/bin/sh
# One file the operation never touches, so the state is not empty: with nothing in it
# the engine refuses `checker_not_falsified` — there is nothing to corrupt — which the
# first run of this sweep measured, and which says nothing about threads.
mkdir -p "$SD"; printf '# project\n' > "$SD/README.md"
EOX
cat > "$AP/check-bundler.sh" <<'EOX'
#!/bin/sh
# Content, not presence: the engine falsifies the checker by overwriting every file with
# junk first, and a checker that only asks whether README.md exists accepts that state
# (`checker_not_falsified`, measured on the second run of this sweep).
grep -qx '# project' "$SD/README.md" 2>/dev/null || { echo "README.md is gone or overwritten"; exit 1; }
[ -e "$SD/Gemfile" ] || exit 0
grep -q source "$SD/Gemfile" || { echo "Gemfile present without a source line ($(wc -c < "$SD/Gemfile") bytes)"; exit 1; }
exit 0
EOX

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

cat > "$AP/setup-annex.sh" <<'EOX'
#!/bin/sh
mkdir -p "$SD"; git -C "$SD" init -q; git -C "$SD" config user.email a@b; git -C "$SD" config user.name a
EOX
cat > "$AP/check-annex.sh" <<'EOX'
#!/bin/sh
exit 0
EOX

cat > "$AP/setup-mlr.sh" <<'EOX'
#!/bin/sh
mkdir -p "$SD"; printf 'a,b\n1,2\n3,4\n' > "$SD/f.csv"
EOX
cat > "$AP/check-mlr.sh" <<'EOX'
#!/bin/sh
[ -f "$SD/f.csv" ] || { echo "f.csv is gone"; exit 1; }
[ "$(wc -l < "$SD/f.csv")" -ge 3 ] || { echo "f.csv lost rows ($(wc -l < "$SD/f.csv") lines)"; exit 1; }
exit 0
EOX
chmod 755 "$AP"/*.sh

########## driver ##########
go() {  # go <name> <state rel> <setup> <op template> <check> [extra args...]
  name=$1; rel=$2; setup=$3; optmpl=$4; chk=$5; shift 5
  case "${ONLY:-}" in "") ;; *" $name "*) ;; *) return 0 ;; esac
  for mode in wrappers syscalls; do
    SD="$R/st/$mode/$name"
    export SD
    state="$SD$rel"
    mkdir -p "$SD" "$state" "$R/wk/$mode/$name"
    op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
    echo "==================== $name / $mode ===================="
    echo "op: $op"
    "$SE" explore --state "$state" --setup "$AP/$setup" --operation "$op" \
      --check "$AP/$chk" --shim "$SHIM" --oracle /usr/bin/strace \
      --observe "$mode" --work "$R/wk/$mode/$name" \
      --json "$OUT/$name.$mode.json" "$@" > "$OUT/$name.$mode.txt" 2>&1
    rc=$?
    echo "raw rc=$rc   (0=PASS 1=FAIL 2=UNKNOWN 3=setup error)"
    grep -nE "^(PASS|FAIL|UNKNOWN|SETUP ERROR)" "$OUT/$name.$mode.txt" | head -2
    grep -nE "crash point|oracle (agree|missed)|divergence at|violation|two threads|thread" "$OUT/$name.$mode.txt" | head -4
    python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print('processes:',(d.get('processes') or '')[:240])" "$OUT/$name.$mode.json" 2>/dev/null
    echo
  done
}

go sqlfluff ""     setup-sqlfluff.sh 'sqlfluff fix --dialect ansi @SD@/q.sql'                 check-sqlfluff.sh
go vips     ""     setup-vips.sh     'vips copy @SD@/img.png @SD@/out.png'                     check-vips.sh
go zstd     ""     setup-zstd.sh     'zstd -q --rm @SD@/a.bin'                                 check-zstd.sh
go bundler  ""     setup-bundler.sh  'bundle init --gemfile=@SD@/Gemfile'                      check-bundler.sh
go beets    /lib   setup-beets.sh    'beet -c @SD@/config.yaml import -q @SD@/in2'             check-beets.sh
go annex    ""     setup-annex.sh    'git -C @SD@ annex init'                                  check-annex.sh
go mlr      ""     setup-mlr.sh      'mlr -I --csv put $c=1 @SD@/f.csv'                        check-mlr.sh

########## determinism: the same define five times ##########
# The judged threaded targets five times each: the same define, the same crash-point
# count and the same prefix_hash, or the thread rule admitted something the scheduler
# decides. mlr is the control.
rep() {  # rep <name> <state rel> <setup> <op template> <check>
  name=$1; rel=$2; setup=$3; optmpl=$4; chk=$5
  case "${ONLY:-}" in "") ;; *" $name "*) ;; *) return 0 ;; esac
  echo "==================== $name x5 / wrappers (prefix_hash, crash_points, verdict) ===================="
  for i in 1 2 3 4 5; do
    SD="$R/st/rep$i/$name"; export SD; state="$SD$rel"
    mkdir -p "$SD" "$state" "$R/wk/rep$i/$name"
    op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
    "$SE" explore --state "$state" --setup "$AP/$setup" --operation "$op" \
      --check "$AP/$chk" --shim "$SHIM" --oracle /usr/bin/strace \
      --work "$R/wk/rep$i/$name" --json "$OUT/$name.rep$i.json" > "$OUT/$name.rep$i.txt" 2>&1
    python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print('run',sys.argv[2],d.get('verdict'),d.get('unknown_reason',''),'cp='+str(d.get('crash_points')),'hash='+str(d.get('prefix_hash'))[:16])" "$OUT/$name.rep$i.json" "$i" 2>/dev/null || echo "run $i: no report"
  done
  echo
}
# beets was the planned subject here and refuses (two threads write library.db — see
# NOTES.md), so the judged targets carry it: sqlfluff (PASS, 5 crash points) and vips
# (FAIL, 6 threads). mlr stays as the control whose writer count the strace measurement
# saw change, though it refuses on epoll before the thread rule is reached.
rep sqlfluff "" setup-sqlfluff.sh 'sqlfluff fix --dialect ansi @SD@/q.sql' check-sqlfluff.sh
rep vips     "" setup-vips.sh     'vips copy @SD@/img.png @SD@/out.png'     check-vips.sh
rep mlr      "" setup-mlr.sh      'mlr -I --csv put $c=1 @SD@/f.csv'        check-mlr.sh
