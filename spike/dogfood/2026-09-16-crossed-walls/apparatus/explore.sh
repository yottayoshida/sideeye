#!/bin/sh
# 2026-09-16 crossed-walls explore: the five targets the screens accepted, each in the
# observation mode(s) its screen accepted it in.
#
#   released v1.4.0 (contract v17) — what a user has:
#     bun           --observe syscalls x3   (refused under wrappers: raw openat)
#     ninja         --observe syscalls x3   (refused under wrappers: .ninja_log through stdio)
#     markdownlint  wrappers x3, syscalls x1
#     gjf           wrappers x3, syscalls x1
#     xz            wrappers x3, syscalls x1
#   main d5911cd (contract v18, not a release): one explore per target in the first mode
#     above, to see whether the unreleased build answers the same.
#
# Runs as root in a --privileged container, so the engine can make cgroups (ninja's `cp`
# child calls setpgid; the 2026-09-16 run refused it in a default container). Image:
# Dockerfile.screen3. State and work are on the container's own filesystem (#528). Every
# line printed below is the report's own headline; nothing is re-counted (#528's rule).
#
#   docker run --rm --privileged --network none \
#     -v <v1.4.0 tarball dir>:/se140:ro -v <main build prefix>:/semain:ro \
#     -v <this dir>:/hostap:ro -v <out>:/out sideeye-dogfood:2026-09-16-crossed3 sh /hostap/explore.sh
set -u
R=/localrun
AP=$R/ap
AUX=$R/aux
OUT=/out/explore
mkdir -p "$AP" "$AUX" "$OUT" "$R/wk"
# The screens' setups, materialised by running them with a name that matches no target.
ONLY=" none " sh /hostap/screen.sh > /dev/null 2>&1
ONLY=" none " sh /hostap/screen2.sh > /dev/null 2>&1
ONLY=" none " sh /hostap/screen3.sh > /dev/null 2>&1
export HOME=$AUX/home BUN_INSTALL_CACHE_DIR=$AUX/bun-cache TMPDIR=$AUX/tmp npm_config_update_notifier=false
mkdir -p "$HOME" "$BUN_INSTALL_CACHE_DIR" "$TMPDIR"
/se140/sideeye version
/semain/bin/sideeye version

########## checkers: each reads $SD ##########
cat > "$AP/check-bun.sh" <<'EOC'
#!/bin/sh
# Cohort 2's P1 property (spike/cohort2/bun/ops/check.sh), with this run's paths: after a
# crash anywhere inside `bun add`, package.json parses, and re-running the install — the
# documented recovery — reaches the exact new state.
set -u
B=/localrun/aux/bun
fail() { echo "checker(bun-add): $*"; exit 1; }
[ -f "$SD/package.json" ] || fail "package.json is missing from the state dir"
python3 - "$SD/package.json" <<'PY' || fail "package.json does not parse — a torn manifest survived the crash"
import json, sys
json.load(open(sys.argv[1]))
PY
( cd "$SD" && bun add "$B/dep-1.0.0.tgz" ) > /tmp/bun-rerun.txt 2>&1 || \
  fail "re-running bun add exited $?: $(tail -c 200 /tmp/bun-rerun.txt)"
grep -q '"probe-dep"' "$SD/package.json" || fail "after the re-run, package.json has no probe-dep entry"
[ -f "$SD/bun.lock" ] || fail "after the re-run, bun.lock is missing"
cmp -s "$SD/node_modules/probe-dep/index.js" "$B/deppkg/package/index.js" || fail "after the re-run, the installed index.js differs from the tarball's"
exit 0
EOC

cat > "$AP/check-ninja.sh" <<'EOC'
#!/bin/sh
# The 2026-09-16 checker (spike/dogfood/2026-09-16-userview-3/apparatus/run-r4.sh): after a
# crash, ninja can still read its build directory, and the input is still there.
[ -f "$SD/build.ninja" ] || { echo "build.ninja is missing"; exit 1; }
ninja -C "$SD" -n >/tmp/e.txt 2>&1 || {
  echo "ninja cannot read the build directory: $(head -2 /tmp/e.txt | tr '\n' ' ' | cut -c1-140)"; exit 1; }
[ -f "$SD/in.txt" ] || { echo "in.txt is gone"; exit 1; }
grep -q MARKER "$SD/in.txt" || { echo "in.txt lost its MARKER"; exit 1; }
exit 0
EOC

cat > "$AP/check-markdownlint.sh" <<'EOC'
#!/bin/sh
# After a crash, README.md still holds the document — before or after the fix — and
# markdownlint can still lint it (exit 0 or 1; anything else is an error, not a finding).
f="$SD/README.md"
[ -f "$f" ] || { echo "README.md is gone"; exit 1; }
for s in 'Title' 'Some text' 'item one' 'item two' 'Section'; do
  grep -q "$s" "$f" || { echo "README.md lost \"$s\" ($(wc -c < "$f") bytes)"; exit 1; }
done
markdownlint "$f" > /tmp/ml.txt 2>&1; rc=$?
[ "$rc" -le 1 ] || { echo "markdownlint exited $rc on README.md: $(head -1 /tmp/ml.txt)"; exit 1; }
exit 0
EOC

cat > "$AP/check-gjf.sh" <<'EOC'
#!/bin/sh
# After a crash, A.java still holds the class — formatted or not — and google-java-format
# can still parse it.
f="$SD/A.java"
[ -f "$f" ] || { echo "A.java is gone"; exit 1; }
for s in 'public class A' 'sum(' 'main('; do
  grep -q "$s" "$f" || { echo "A.java lost \"$s\" ($(wc -c < "$f") bytes)"; exit 1; }
done
java --add-exports=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED \
     --add-exports=jdk.compiler/com.sun.tools.javac.code=ALL-UNNAMED \
     --add-exports=jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED \
     --add-exports=jdk.compiler/com.sun.tools.javac.parser=ALL-UNNAMED \
     --add-exports=jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED \
     --add-exports=jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED \
     -jar /opt/gjf/gjf.jar "$f" > /dev/null 2>/tmp/gjf.txt || {
  echo "google-java-format cannot parse A.java: $(head -1 /tmp/gjf.txt | cut -c1-140)"; exit 1; }
exit 0
EOC

cat > "$AP/check-xz.sh" <<'EOC'
#!/bin/sh
# After a crash, the data is in f.bin as it was, or in an f.bin.xz that decompresses to it
# (the 2026-09-16 zstd checker's property). A partial f.bin.xz beside an intact f.bin passes.
orig=/localrun/aux/xz.orig
if [ -f "$SD/f.bin" ]; then
  cmp -s "$SD/f.bin" "$orig" && exit 0
  echo "f.bin is present but differs ($(wc -c < "$SD/f.bin") bytes, original $(wc -c < "$orig"))"; exit 1
fi
if [ -f "$SD/f.bin.xz" ]; then
  xz -q -d -c "$SD/f.bin.xz" > /tmp/xz-out.bin 2>/tmp/xz-err.txt || {
    echo "f.bin is gone and f.bin.xz does not decompress ($(wc -c < "$SD/f.bin.xz") bytes): $(head -1 /tmp/xz-err.txt)"; exit 1; }
  cmp -s /tmp/xz-out.bin "$orig" && exit 0
  echo "f.bin is gone and f.bin.xz decompresses to something else"; exit 1
fi
echo "neither f.bin nor f.bin.xz is present"; exit 1
EOC
chmod 755 "$AP"/*.sh

########## the driver ##########
ex() {  # ex <build> <mode> <run> <name> <setup> <op template> <check>
  b=$1; mode=$2; i=$3; name=$4; setup=$5; optmpl=$6; chk=$7
  case "${ONLY:-}" in "") ;; *" $name "*) ;; *) return 0 ;; esac
  case $b in 140) SE=/se140/sideeye; SHIM=/se140/libsideeye_shim.so ;;
             main) SE=/semain/bin/sideeye; SHIM=/semain/lib/libsideeye_shim.so ;; esac
  tag="$name.$b.$mode.$i"
  SD="$R/st/$tag"; export SD
  W="$R/wk/$tag"; mkdir -p "$SD" "$W"
  op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
  start=$(date +%s)
  (cd "$SD" && "$SE" explore --state "$SD" --setup "$AP/$setup" --operation "$op" \
    --check "$AP/$chk" --shim "$SHIM" --oracle /usr/bin/strace --observe "$mode" \
    --work "$W" --json "$OUT/$tag.json" > "$OUT/$tag.txt" 2>&1)
  rc=$?
  printf '%-34s rc=%s %4ss  ' "$tag" "$rc" "$(( $(date +%s) - start ))"
  head -1 "$OUT/$tag.txt" | tr -s ' ' | cut -c1-160
  grep -E '^ *(explored|oracle|checker|processes|earliest|violation|crash point|step)' "$OUT/$tag.txt" \
    | head -6 | sed -E 's/^ +/    /' | cut -c1-260
}

GJF='java --add-exports=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.code=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.parser=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED -jar /opt/gjf/gjf.jar'
BUN_OP='bun add --cwd @SD@ /localrun/aux/bun/dep-1.0.0.tgz'
NJ_OP='ninja -C @SD@'
ML_OP='markdownlint --fix @SD@/README.md'
GJF_OP="$GJF --replace @SD@/A.java"
XZ_OP='xz -q -T2 --block-size=1MiB @SD@/f.bin'

for i in 1 2 3; do
  ex 140 syscalls $i bun          setup-bun.sh          "$BUN_OP" check-bun.sh
  ex 140 syscalls $i ninja        setup-ninja.sh        "$NJ_OP"  check-ninja.sh
  ex 140 wrappers $i markdownlint setup-markdownlint.sh "$ML_OP"  check-markdownlint.sh
  ex 140 wrappers $i gjf          setup-gjf.sh          "$GJF_OP" check-gjf.sh
  ex 140 wrappers $i xz           setup-xz.sh           "$XZ_OP"  check-xz.sh
done
ex 140 syscalls 1 markdownlint setup-markdownlint.sh "$ML_OP"  check-markdownlint.sh
ex 140 syscalls 1 gjf          setup-gjf.sh          "$GJF_OP" check-gjf.sh
ex 140 syscalls 1 xz           setup-xz.sh           "$XZ_OP"  check-xz.sh
ex main syscalls 1 bun          setup-bun.sh          "$BUN_OP" check-bun.sh
ex main syscalls 1 ninja        setup-ninja.sh        "$NJ_OP"  check-ninja.sh
ex main wrappers 1 markdownlint setup-markdownlint.sh "$ML_OP"  check-markdownlint.sh
ex main wrappers 1 gjf          setup-gjf.sh          "$GJF_OP" check-gjf.sh
ex main wrappers 1 xz           setup-xz.sh           "$XZ_OP"  check-xz.sh
