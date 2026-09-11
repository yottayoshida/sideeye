#!/bin/sh
# 2026-09-11 screen: the targets earlier dogfood runs turned away for threads or children,
# re-met with the released v1.3.0 (contract v16: one writing thread per process is judged;
# contract v15: reaped, non-overlapping writing children are judged).
#
# Two instruments per target, before any checker exists:
#   1. strace, tid-aware: threads and processes created, and which tids of which process
#      wrote under the state directory (screen-strace.py). The 2026-09-05 rule — measure
#      threads before the candidate table — with the count v16 actually asks.
#   2. `sideeye preflight --oracle strace`, both observation modes: the engine's own answer
#      to "does the recording phase accept this target?".
# State and work are on the container's own filesystem (#528).
set -u
SE=/se/sideeye
SHIM=/se/libsideeye_shim.so
R=/localrun
AP=$R/ap
AUX=$R/aux
OUT=/out/screen
mkdir -p "$AP" "$AUX" "$OUT" "$R/wk"
cp /hostap/mkpdf.py /hostap/screen-strace.py "$AP/"

"$SE" version
cat /tmp/apt-summary.txt
echo "bun $(bun --version)  joplin $(npm ls -g joplin 2>/dev/null | grep -o 'joplin@[^ ]*')  node $(node --version)"
for b in newsboat oxipng rsync ocrmypdf ansible bun joplin node python3; do
  p=$(command -v "$b"); printf '%-9s %s  ' "$b" "$p"; file -L "$p" | sed 's/^[^:]*: //' | cut -c1-90
done
echo

########## setups: each reads $SD, which the driver exports ##########
cat > "$AP/setup-newsboat.sh" <<'EOX'
#!/bin/sh
mkdir -p "$SD" /localrun/aux/nb
cat > /localrun/aux/nb/feed.xml <<'EOF'
<?xml version="1.0"?>
<rss version="2.0"><channel><title>probe</title><link>http://example.invalid/</link><description>d</description>
<item><title>one</title><link>http://example.invalid/1</link><guid>1</guid><description>first</description></item>
<item><title>two</title><link>http://example.invalid/2</link><guid>2</guid><description>second</description></item>
</channel></rss>
EOF
printf 'file:///localrun/aux/nb/feed.xml\n' > "$SD/urls"
: > "$SD/config"
EOX

cat > "$AP/setup-oxipng.sh" <<'EOX'
#!/bin/sh
# A 64x64 RGB gradient stored uncompressed, so oxipng has something to rewrite.
mkdir -p "$SD"
python3 - "$SD/a.png" <<'PY'
import struct, sys, zlib
w = h = 64
raw = b"".join(b"\x00" + bytes(v for x in range(w) for v in ((x * 4) % 256, (y * 4) % 256, ((x + y) * 2) % 256)) for y in range(h))
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 0)) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
PY
EOX

cat > "$AP/setup-rsync.sh" <<'EOX'
#!/bin/sh
mkdir -p "$SD" /localrun/aux/rsrc
printf 'new one\n' > /localrun/aux/rsrc/f1.txt
printf 'new two\n' > /localrun/aux/rsrc/f2.txt
printf 'old\n' > "$SD/f1.txt"
printf 'keep\n' > "$SD/keep.txt"
EOX

cat > "$AP/setup-ocrmypdf.sh" <<'EOX'
#!/bin/sh
mkdir -p "$SD"; python3 /localrun/ap/mkpdf.py "$SD/a.pdf"
EOX

cat > "$AP/setup-ansible.sh" <<'EOX'
#!/bin/sh
mkdir -p "$SD"; printf 'alpha\nbeta\n' > "$SD/f.txt"
EOX

cat > "$AP/setup-joplin.sh" <<'EOX'
#!/bin/sh
mkdir -p "$SD"
joplin --profile "$SD" mkbook TestBook > /dev/null 2>&1
joplin --profile "$SD" use TestBook > /dev/null 2>&1
joplin --profile "$SD" mknote SeedNote > /dev/null 2>&1
EOX

cat > "$AP/setup-bun.sh" <<'EOX'
#!/bin/sh
# The cohort-2 define's pre-state (spike/cohort2/bun/ops/setup.sh), with the dependency
# tarball and the ambient directories outside the state directory.
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
chmod 755 "$AP"/*.sh

# Bun's ambient directories, outside the state (the cohort-2 launcher's environment).
export HOME=/localrun/aux/home BUN_INSTALL_CACHE_DIR=/localrun/aux/bun-cache TMPDIR=/localrun/aux/tmp
mkdir -p "$HOME" "$BUN_INSTALL_CACHE_DIR" "$TMPDIR"

########## driver ##########
screen() {  # screen <name> <setup> <op template> [extra preflight args...]
  name=$1; setup=$2; optmpl=$3; shift 3
  case "${ONLY:-}" in "") ;; *" $name "*) ;; *) return 0 ;; esac
  echo "==================== $name ===================="
  # 1. strace, from a fresh setup
  SD="$R/st/strace/$name"; export SD
  "$AP/$setup" > "$OUT/$name.setup.txt" 2>&1 || echo "setup rc=$? (see $name.setup.txt)"
  op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
  echo "op: $op"
  # shellcheck disable=SC2086
  strace -f -qq -y -o "$OUT/$name.strace" \
    -e trace=clone,clone3,fork,vfork,execve,wait4,openat,write,pwrite64,writev,pwritev,rename,renameat,renameat2,unlink,unlinkat,mkdirat,ftruncate,fsync,fdatasync \
    $op > "$OUT/$name.op.txt" 2>&1
  echo "plain run under strace: rc=$?"
  python3 "$AP/screen-strace.py" "$OUT/$name.strace" "$SD"
  # 2. preflight, both modes, each from its own fresh setup
  for mode in wrappers syscalls; do
    SD="$R/st/$mode/$name"; export SD
    mkdir -p "$SD" "$R/wk/$mode/$name"
    op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
    "$SE" preflight --state "$SD" --setup "$AP/$setup" --operation "$op" \
      --shim "$SHIM" --oracle /usr/bin/strace --observe "$mode" \
      --work "$R/wk/$mode/$name" "$@" > "$OUT/$name.preflight.$mode.txt" 2>&1
    rc=$?
    printf 'preflight %-8s rc=%s  ' "$mode" "$rc"
    grep -m1 -E '^(accepted|recording accepted|UNKNOWN|SETUP ERROR|refused|PREFLIGHT)|recording (accepted|refused)' "$OUT/$name.preflight.$mode.txt" || head -1 "$OUT/$name.preflight.$mode.txt"
    grep -E 'thread|process|divergence|detector|reason' "$OUT/$name.preflight.$mode.txt" | head -4 | cut -c1-240 | sed 's/^/    /'
  done
  echo
}

screen newsboat setup-newsboat.sh 'newsboat -u @SD@/urls -c @SD@/cache.db -C @SD@/config -x reload'
screen oxipng   setup-oxipng.sh   'oxipng -q -o 2 @SD@/a.png'
screen rsync    setup-rsync.sh    'rsync -a /localrun/aux/rsrc/ @SD@/'
screen ocrmypdf setup-ocrmypdf.sh 'ocrmypdf -q --force-ocr @SD@/a.pdf @SD@/a.pdf'
screen ansible  setup-ansible.sh  'ansible localhost -c local -i localhost, -e ansible_python_interpreter=/usr/bin/python3 -m lineinfile -a {"path":"@SD@/f.txt","line":"gamma"}'
screen joplin   setup-joplin.sh   'joplin --profile @SD@ mknote SecondNote'
screen bun      setup-bun.sh      'bun add --cwd @SD@ /localrun/aux/bun/dep-1.0.0.tgz'
