#!/bin/sh
# 2026-09-16 crossed-walls screen, third pass: the JVM, a class cohort 4 excluded by language
# alone (google-java-format --replace), and xz's thread pool, which the 2026-09-06 screen would
# have dropped for its threads (xz -T2 with 1 MiB blocks over a 5,750,000-byte file). Same
# instruments and container as screen.sh, in the image Dockerfile.screen3 builds; the screen
# function is screen2.sh's.
set -u
R=/localrun
AP=$R/ap
AUX=$R/aux
OUT=/out/screen3
mkdir -p "$AP" "$AUX" "$OUT" "$R/wk"
cp /hostap/screen-strace.py "$AP/"
export HOME=$AUX/home TMPDIR=$AUX/tmp
mkdir -p "$HOME" "$TMPDIR"
/se140/sideeye version
/semain/bin/sideeye version
{ java -version 2>&1 | head -1; xz --version | head -1; } | sed 's/^/  /'
echo

cat > "$AP/setup-gjf.sh" <<'EOX'
#!/bin/sh
set -eu
mkdir -p "$SD"
cat > "$SD/A.java" <<'EOF'
package probe;
import java.util.List;
public class A {
  public static int   sum(List<Integer> xs){int s=0;for(int x:xs){s+=x;}return s;}
    public static void main(String[] args){System.out.println(sum(List.of(1,2,3)));}
}
EOF
EOX

cat > "$AP/setup-xz.sh" <<'EOX'
#!/bin/sh
set -eu
mkdir -p "$SD"
for f in "$SD"/*; do [ -e "$f" ] && rm -f "$f"; done
python3 - "$SD/f.bin" <<'PY2'
import sys
with open(sys.argv[1], 'wb') as f:
    for i in range(250000):
        f.write(b"MARKER-%07d-payload\n" % i)
PY2
cp "$SD/f.bin" /localrun/aux/xz.orig
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

GJF='java --add-exports=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.code=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.parser=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED -jar /opt/gjf/gjf.jar'
screen gjf setup-gjf.sh "$GJF --replace @SD@/A.java"
screen xz  setup-xz.sh  'xz -q -T2 --block-size=1MiB @SD@/f.bin'
