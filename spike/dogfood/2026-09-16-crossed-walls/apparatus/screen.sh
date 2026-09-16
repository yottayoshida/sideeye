#!/bin/sh
# 2026-09-16 crossed-walls screen. Eight candidates, each one an earlier record refused
# (Bun, zstd, ninja), or a class an earlier record excluded before any run (Node tools:
# cohort 4's language-wall forecast; thread pools that create and join: the 2026-09-05 and
# 2026-09-06 screens), where a later change moved the wall.
#
# Three instruments per candidate, before any checker exists:
#   1. strace -f -y, tid-aware (screen-strace.py): threads and processes created,
#      setsid/setpgid, and which tids of which process wrote under the state directory.
#   2. `sideeye preflight --oracle strace` with the released v1.4.0 (contract v17), both
#      observation modes: what a user has today.
#   3. the same with main d5911cd (contract v18, #539: threads ordered by a creation or a
#      join), both modes: whether the unreleased change moves the answer.
#
# Runs as root in a --privileged container, so the engine can make cgroups (#559); the
# screen does not separate the default container's answer. State and work are on the
# container's own filesystem (#528).
#
#   docker run --rm --privileged --network none \
#     -v <v1.4.0 tarball dir>:/se140:ro -v <main build prefix>:/semain:ro \
#     -v <this dir>:/hostap:ro -v <out>:/out sideeye-dogfood:2026-09-16-crossed sh /hostap/screen.sh
set -u
R=/localrun
AP=$R/ap
AUX=$R/aux
OUT=/out/screen
mkdir -p "$AP" "$AUX" "$OUT" "$R/wk"
cp /hostap/screen-strace.py "$AP/"
export HOME=$AUX/home BUN_INSTALL_CACHE_DIR=$AUX/bun-cache TMPDIR=$AUX/tmp npm_config_update_notifier=false
mkdir -p "$HOME" "$BUN_INSTALL_CACHE_DIR" "$TMPDIR"

/se140/sideeye version
/semain/bin/sideeye version
cat /tmp/apt-summary.txt
{ bun --version; node --version; prettier --version; svgo --version; markdownlint --version; npm --version
  zstd --version; lz4 --version; ninja --version; uname -m; } 2>&1 | sed 's/^/  /'
echo

########## setups: each reads $SD, which the driver exports ##########
cat > "$AP/setup-bun.sh" <<'EOX'
#!/bin/sh
# The 2026-09-11 define (spike/dogfood/2026-09-11-past-walls/apparatus/screen.sh), verbatim.
set -eu
B=/localrun/aux/bun
mkdir -p "$SD" "$B/deppkg/package" "$HOME" "$BUN_INSTALL_CACHE_DIR" "$TMPDIR"
printf '{ "name": "probe-dep", "version": "1.0.0", "main": "index.js" }\n' > "$B/deppkg/package/package.json"
printf 'module.exports = "probe-dep";\n' > "$B/deppkg/package/index.js"
touch -t 202601010000 "$B/deppkg/package/package.json" "$B/deppkg/package/index.js" "$B/deppkg/package"
tar -czf "$B/dep-1.0.0.tgz" -C "$B/deppkg" package
touch -t 202601010000 "$B/dep-1.0.0.tgz"
printf '{ "name": "probe-proj", "version": "1.0.0" }\n' > "$SD/package.json"
touch -t 202601010000 "$SD/package.json" "$SD"
EOX

cat > "$AP/setup-bin.sh" <<'EOX'
#!/bin/sh
# zstd and lz4: a 1.1 MiB file of numbered lines (the 2026-09-16 zstd define's content,
# longer, so lz4's 64 KiB blocks make more than one job).
set -eu
mkdir -p "$SD"
for f in "$SD"/*; do [ -e "$f" ] && rm -f "$f"; done
python3 - "$SD/f.bin" <<'PY'
import sys
with open(sys.argv[1], 'wb') as f:
    for i in range(50000):
        f.write(b"MARKER-%06d-payload\n" % i)
PY
cp "$SD/f.bin" /localrun/aux/f.bin.orig
EOX

cat > "$AP/setup-ninja.sh" <<'EOX'
#!/bin/sh
# The 2026-09-16 define (spike/dogfood/2026-09-16-userview-3/apparatus/run-r4.sh), verbatim.
set -eu
mkdir -p "$SD"
printf 'rule cp\n  command = cp $in $out\nbuild out.txt: cp in.txt\n' > "$SD/build.ninja"
printf 'MARKER first content\n' > "$SD/in.txt"
ninja -C "$SD" >/dev/null 2>&1
printf 'MARKER second content\n' > "$SD/in.txt"
EOX

cat > "$AP/setup-prettier.sh" <<'EOX'
#!/bin/sh
set -eu
mkdir -p "$SD"
printf 'const   a = {b:1,\n c : [1,2,3]}\nfunction f( x ){return x*2}\nconsole.log( f(a.b) )\n' > "$SD/a.js"
EOX

cat > "$AP/setup-svgo.sh" <<'EOX'
#!/bin/sh
set -eu
mkdir -p "$SD"
cat > "$SD/a.svg" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!-- Generator: an editor -->
<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
  <metadata>probe</metadata>
  <g>
    <rect x="0.000" y="0.000" width="64.000" height="64.000" fill="#ffffff"/>
    <circle cx="32.000" cy="32.000" r="16.000" fill="#ff0000" stroke="none"/>
  </g>
</svg>
EOF
EOX

cat > "$AP/setup-markdownlint.sh" <<'EOX'
#!/bin/sh
set -eu
mkdir -p "$SD"
printf '# Title\nSome text   \n* item one\n+ item two\n\n\n## Section\ntext\n' > "$SD/README.md"
EOX

cat > "$AP/setup-npm.sh" <<'EOX'
#!/bin/sh
set -eu
mkdir -p "$SD"
printf '{\n  "name": "probe-proj",\n  "version": "1.0.0",\n  "description": "first"\n}\n' > "$SD/package.json"
EOX
chmod 755 "$AP"/*.sh

########## the screen ##########
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
      grep -m2 -E 'step:|threads? of process|divergence at operation|processes:' "$OUT/$name.$b.$mode.txt" \
        | sed -E 's/^ +/        /' | cut -c1-240
    done
  done
  echo
}

screen bun          setup-bun.sh          'bun add --cwd @SD@ /localrun/aux/bun/dep-1.0.0.tgz'
screen zstd         setup-bin.sh          'zstd -q --rm @SD@/f.bin'
screen lz4          setup-bin.sh          'lz4 -q -B4 -T2 --rm @SD@/f.bin'
screen ninja        setup-ninja.sh        'ninja -C @SD@'
screen prettier     setup-prettier.sh     'prettier --write @SD@/a.js'
screen svgo         setup-svgo.sh         'svgo -q @SD@/a.svg'
screen markdownlint setup-markdownlint.sh 'markdownlint --fix @SD@/README.md'
screen npm          setup-npm.sh          'npm pkg set description=second --prefix @SD@'
