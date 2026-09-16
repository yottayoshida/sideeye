#!/bin/sh
# 2026-09-16 outside-git screen, second pass: jbang with the JVM named directly. The first pass ran
# `jbang config set` through jbang's bash launcher, which runs `java -jar jbang.jar` as a child
# inside `$(...)` and then execs what it prints; the java child's non-main thread writes
# jbang.properties, and the run refuses `child_touched_state_dir`. docs/cli.md: "Naming an
# executable image directly takes the question away." Same instruments and container as screen.sh.
set -u
R=/localrun
AP=$R/ap
AUX=$R/aux
OUT=/out/screen2
mkdir -p "$AP" "$AUX" "$OUT" "$R/wk"
cp /hostap/screen-strace.py "$AP/"
export HOME=$AUX/home TMPDIR=$AUX/tmp JBANG_NO_VERSION_CHECK=true
mkdir -p "$HOME" "$TMPDIR"
/se140/sideeye version
/semain/bin/sideeye version

cat > "$AP/setup-jbang-java.sh" <<'EOX'
#!/bin/sh
set -eu
mkdir -p "$SD"
JBANG_DIR="$SD" java -jar /opt/jbang-0.141.0/bin/jbang.jar config set first.key first-value > /dev/null 2>&1
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
  (cd "$SD" && set -f && strace -f -y -qq -o "$OUT/$name.strace" $op > "$OUT/$name.op.txt" 2>&1)
  echo "  operation rc=$?  ($(wc -l < "$OUT/$name.strace") strace lines); files: $(cd "$SD" && find . -type f | sort | tr '\n' ' ' | cut -c1-200)"
  python3 "$AP/screen-strace.py" "$OUT/$name.strace" "$SD"
  for b in 140 main; do
    case $b in 140) SE=/se140/sideeye; SHIM=/se140/libsideeye_shim.so ;;
               main) SE=/semain/bin/sideeye; SHIM=/semain/lib/libsideeye_shim.so ;; esac
    for mode in wrappers syscalls; do
      SD="$R/st/$b-$mode/$name"; export SD
      W="$R/wk/$b-$mode/$name"; mkdir -p "$SD" "$W"
      op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
      (cd "$SD" && timeout 600 "$SE" preflight --state "$SD" --setup "$AP/$setup" --operation "$op" \
        --shim "$SHIM" --oracle /usr/bin/strace --observe "$mode" --work "$W" \
        > "$OUT/$name.$b.$mode.txt" 2>&1)
      rc=$?
      printf '  %-4s %-8s rc=%s  ' "$b" "$mode" "$rc"
      grep -m1 -E '^(UNKNOWN|PREFLIGHT|SETUP|recording)' "$OUT/$name.$b.$mode.txt" | tr -s ' ' | cut -c1-150
      grep -m2 -E 'threads? of process|divergence at operation|^processes' "$OUT/$name.$b.$mode.txt" \
        | sed -E 's/^ +/        /' | cut -c1-320
    done
  done
  echo
}

screen jbang-java setup-jbang-java.sh 'env JBANG_DIR=@SD@ java -jar /opt/jbang-0.141.0/bin/jbang.jar config set second.key second-value'
