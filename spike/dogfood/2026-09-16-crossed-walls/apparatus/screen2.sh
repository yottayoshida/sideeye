#!/bin/sh
# 2026-09-16 crossed-walls screen, second pass. Three defines the first pass could not answer:
#
#   ninja   the 2026-09-16 define rebuilds only when in.txt is newer than out.txt, and its
#           setup rewrites in.txt in the same clock tick as the build before it, so whether
#           the operation has work depends on the tick (the first pass: 4 operations under
#           `--observe wrappers`, 0 under `syscalls`, same image). out.txt is now dated
#           2026-01-01 after the first build, so the operation always has work.
#   lz4     lz4 1.10 starts its worker threads only above 4 MiB (measured: 3,450,000 bytes
#           start none under -T2, 5,750,000 start four), so the first pass's 1.1 MiB file
#           measured a single-threaded lz4. 5,750,000 bytes here.
#   git     a commit that triggers automatic maintenance, which git runs detached (it leaves
#           its session: the #559 shape). Three packs against gc.autoPackLimit=2.
#
# Same instruments and container as screen.sh (strace tid-aware, then preflight under the
# released v1.4.0 and main d5911cd in both observation modes, --privileged so the engine can
# make cgroups).
set -u
R=/localrun
AP=$R/ap
AUX=$R/aux
OUT=/out/screen2
mkdir -p "$AP" "$AUX" "$OUT" "$R/wk"
cp /hostap/screen-strace.py "$AP/"
export HOME=$AUX/home TMPDIR=$AUX/tmp
mkdir -p "$HOME" "$TMPDIR"
/se140/sideeye version
/semain/bin/sideeye version
git --version
echo

cat > "$AP/setup-ninja.sh" <<'EOX'
#!/bin/sh
set -eu
mkdir -p "$SD"
printf 'rule cp\n  command = cp $in $out\nbuild out.txt: cp in.txt\n' > "$SD/build.ninja"
printf 'MARKER first content\n' > "$SD/in.txt"
ninja -C "$SD" >/dev/null 2>&1
touch -d 2026-01-01T00:00:00 "$SD/out.txt"
printf 'MARKER second content\n' > "$SD/in.txt"
EOX

cat > "$AP/setup-lz4.sh" <<'EOX'
#!/bin/sh
set -eu
mkdir -p "$SD"
for f in "$SD"/*; do [ -e "$f" ] && rm -f "$f"; done
python3 - "$SD/f.bin" <<'PY'
import sys
with open(sys.argv[1], 'wb') as f:
    for i in range(250000):
        f.write(b"MARKER-%07d-payload\n" % i)
PY
cp "$SD/f.bin" /localrun/aux/lz4.orig
EOX

cat > "$AP/setup-git.sh" <<'EOX'
#!/bin/sh
set -eu
mkdir -p "$SD"
cd "$SD"
git init -q .
git config user.name probe
git config user.email probe@example.invalid
git config gc.autoPackLimit 2
for i in 1 2 3; do
  printf 'line %s\n' "$i" > "f$i.txt"
  git add "f$i.txt"
  git -c gc.auto=0 -c maintenance.auto=false commit -q -m "c$i"
  git repack -q
done
printf 'change\n' >> f1.txt
git add f1.txt
EOX
chmod 755 "$AP"/*.sh

screen() {  # screen <name> <setup> <op template>
  name=$1; setup=$2; optmpl=$3
  case "${ONLY:-}" in "") ;; *" $name "*) ;; *) return 0 ;; esac
  echo "==================== $name ===================="
  SD="$R/st/strace/$name"; export SD
  "$AP/$setup" > "$OUT/$name.setup.txt" 2>&1 || echo "  setup rc=$? (see $name.setup.txt)"
  op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
  echo "  operation: $op"
  (cd "$SD" && strace -f -y -qq -o "$OUT/$name.strace" sh -c "$op" > "$OUT/$name.op.txt" 2>&1)
  echo "  operation rc=$?  ($(wc -l < "$OUT/$name.strace") strace lines)"
  python3 "$AP/screen-strace.py" "$OUT/$name.strace" "$SD"
  for b in 140 main; do
    case $b in 140) SE=/se140/sideeye; SHIM=/se140/libsideeye_shim.so ;;
               main) SE=/semain/bin/sideeye; SHIM=/semain/lib/libsideeye_shim.so ;; esac
    for mode in wrappers syscalls; do
      SD="$R/st/$b-$mode/$name"; export SD
      W="$R/wk/$b-$mode/$name"; mkdir -p "$SD" "$W"
      op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
      (cd "$SD" && "$SE" preflight --state "$SD" --setup "$AP/$setup" --operation "$op" \
        --shim "$SHIM" --oracle /usr/bin/strace --observe "$mode" --work "$W" \
        > "$OUT/$name.$b.$mode.txt" 2>&1)
      rc=$?
      printf '  %-4s %-8s rc=%s  ' "$b" "$mode" "$rc"
      grep -m1 -E '^(UNKNOWN|PREFLIGHT|SETUP|recording)' "$OUT/$name.$b.$mode.txt" | tr -s ' ' | cut -c1-150
      grep -m2 -E 'step:|threads? of process|divergence at operation|^processes' "$OUT/$name.$b.$mode.txt" \
        | sed -E 's/^ +/        /' | cut -c1-400
    done
  done
  echo
}

screen ninja setup-ninja.sh 'ninja -C @SD@'
screen lz4   setup-lz4.sh   'lz4 -q -T2 --rm @SD@/f.bin'
screen git   setup-git.sh   'git -C @SD@ commit -q -m second'
