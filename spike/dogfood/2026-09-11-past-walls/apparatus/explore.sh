#!/bin/sh
# 2026-09-11 explore: the three targets the screen accepted, judged in both observation
# modes; the two threaded/child targets five more times for the rules' determinism; and
# the two refusals #540 asks about, five times each, to see that the refusal is stable.
# State and work are on the container's own filesystem (#528). Every line printed below
# is the report's own headline; nothing is re-counted (#528's rule).
set -u
SE=/se/sideeye
SHIM=/se/libsideeye_shim.so
R=/localrun
AP=$R/ap
OUT=/out/explore
mkdir -p "$OUT"
# The screen's setups (joplin, bun, oxipng, rsync) are materialised by running it with a
# name that matches no target.
ONLY=" none " sh /hostap/screen.sh > /dev/null 2>&1
export HOME=/localrun/aux/home BUN_INSTALL_CACHE_DIR=/localrun/aux/bun-cache TMPDIR=/localrun/aux/tmp
mkdir -p "$HOME" "$BUN_INSTALL_CACHE_DIR" "$TMPDIR" "$R/wk"
"$SE" version

########## setups and checkers ##########
cat > "$AP/setup-newsboat2.sh" <<'EOX'
#!/bin/sh
# Pre-state: a cache that already holds item "one" from a first reload. The feed then
# gains item "two", and the operation's reload writes it into the existing cache — a
# mutation of state that was there before, not the creation of a new file.
set -eu
mkdir -p "$SD" /localrun/aux/nb
feed() {
  { printf '<?xml version="1.0"?>\n<rss version="2.0"><channel><title>probe</title><link>http://example.invalid/</link><description>d</description>\n'
    for t in "$@"; do printf '<item><title>%s</title><link>http://example.invalid/%s</link><guid>%s</guid><description>%s</description></item>\n' "$t" "$t" "$t" "$t"; done
    printf '</channel></rss>\n'; } > /localrun/aux/nb/feed.xml
}
feed one
printf 'file:///localrun/aux/nb/feed.xml\n' > "$SD/urls"
: > "$SD/config"
newsboat -u "$SD/urls" -c "$SD/cache.db" -C "$SD/config" -x reload
feed one two
EOX
cat > "$AP/setup-newsboat3.sh" <<'EOX'
#!/bin/sh
# As setup-newsboat2.sh, with a pubDate on every item. The first explore of this day
# refused `baseline_violates_invariant` on cache.db: an item with no pubDate is stamped
# with the time it was read, so two runs never leave the same bytes. With the dates in
# the feed, `preflight --twice` finds the two runs equal in both modes.
set -eu
mkdir -p "$SD" /localrun/aux/nb
feed() {
  { printf '<?xml version="1.0"?>\n<rss version="2.0"><channel><title>probe</title><link>http://example.invalid/</link><description>d</description>\n'
    for t in "$@"; do printf '<item><title>%s</title><link>http://example.invalid/%s</link><guid>%s</guid><pubDate>Mon, 07 Sep 2026 10:00:00 +0000</pubDate><description>%s</description></item>\n' "$t" "$t" "$t" "$t"; done
    printf '</channel></rss>\n'; } > /localrun/aux/nb/feed.xml
}
feed one
printf 'file:///localrun/aux/nb/feed.xml\n' > "$SD/urls"
: > "$SD/config"
newsboat -u "$SD/urls" -c "$SD/cache.db" -C "$SD/config" -x reload
feed one two
EOX
cat > "$AP/check-newsboat.sh" <<'EOX'
#!/bin/sh
# In every world: the cache opens, passes SQLite's own integrity check and still holds
# item "one" from before the operation; and the next reload — newsboat's own recovery,
# which is running it again — succeeds.
db="$SD/cache.db"
[ -f "$db" ] || { echo "cache.db is gone"; exit 1; }
out=$(python3 - "$db" 2>&1 <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
ok = c.execute("pragma integrity_check").fetchone()[0]
if ok != "ok":
    print("integrity_check:", ok); sys.exit(1)
titles = [r[0] for r in c.execute("select title from rss_item")]
if "one" not in titles:
    print("item one is gone; items:", titles); sys.exit(1)
PY
) || { echo "cache.db: $(printf '%s' "$out" | tail -c 200)"; exit 1; }
newsboat -u "$SD/urls" -c "$db" -C "$SD/config" -x reload > /tmp/nb-recover.$$ 2>&1 \
  || { echo "the next reload failed: $(tail -c 200 /tmp/nb-recover.$$)"; exit 1; }
exit 0
EOX

cat > "$AP/check-oxipng.sh" <<'EOX'
#!/bin/sh
# The image must decode, in every world, to exactly the pixels setup wrote. oxipng is
# lossless, so the old file and the new one decode the same; anything else is a torn file.
python3 - "$SD/a.png" <<'PY'
import struct, sys, zlib
def fail(m):
    print(m); sys.exit(1)
w = h = 64
want = b"".join(bytes(v for x in range(w) for v in ((x * 4) % 256, (y * 4) % 256, ((x + y) * 2) % 256)) for y in range(h))
try:
    d = open(sys.argv[1], "rb").read()
except OSError as e:
    fail("a.png does not open: %s" % e)
if d[:8] != b"\x89PNG\r\n\x1a\n":
    fail("a.png is not a PNG (%d bytes)" % len(d))
pos, idat, ihdr = 8, b"", None
while True:
    if pos + 12 > len(d):
        fail("a.png ends inside a chunk (%d bytes)" % len(d))
    n, t = struct.unpack(">I4s", d[pos:pos + 8])
    body, crc = d[pos + 8:pos + 8 + n], d[pos + 8 + n:pos + 12 + n]
    if len(body) != n or len(crc) != 4:
        fail("a.png: chunk %r truncated" % t)
    if struct.unpack(">I", crc)[0] != zlib.crc32(t + body) & 0xffffffff:
        fail("a.png: bad CRC in %r" % t)
    if t == b"IHDR":
        ihdr = struct.unpack(">IIBBBBB", body)
    elif t == b"IDAT":
        idat += body
    elif t == b"IEND":
        break
    pos += 12 + n
if ihdr is None:
    fail("a.png has no IHDR")
W, H, depth, ctype, _, _, interlace = ihdr
if (W, H, depth, ctype, interlace) != (w, h, 8, 2, 0):
    fail("a.png is a format this checker does not decode: %r" % (ihdr,))
raw, stride, bpp = zlib.decompress(idat), w * 3, 3
out, prev, i = bytearray(), bytearray(stride), 0
for _ in range(h):
    f, line = raw[i], bytearray(raw[i + 1:i + 1 + stride]); i += 1 + stride
    for x in range(stride):
        a = line[x - bpp] if x >= bpp else 0
        b = prev[x]
        c = prev[x - bpp] if x >= bpp else 0
        if f == 1: line[x] = (line[x] + a) & 255
        elif f == 2: line[x] = (line[x] + b) & 255
        elif f == 3: line[x] = (line[x] + ((a + b) >> 1)) & 255
        elif f == 4:
            p = a + b - c
            pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            line[x] = (line[x] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        elif f != 0:
            fail("a.png: filter type %d" % f)
    out += line; prev = line
if bytes(out) != want:
    fail("a.png decodes to different pixels")
PY
EOX

cat > "$AP/check-rsync.sh" <<'EOX'
#!/bin/sh
# Each destination file is its old version or its new one, byte for byte; the file the
# transfer never touches is unchanged.
[ -f "$SD/f1.txt" ] || { echo "f1.txt is gone"; exit 1; }
printf 'old\n' | cmp -s - "$SD/f1.txt" || printf 'new one\n' | cmp -s - "$SD/f1.txt" \
  || { echo "f1.txt holds neither version ($(wc -c < "$SD/f1.txt") bytes)"; exit 1; }
[ ! -e "$SD/f2.txt" ] || printf 'new two\n' | cmp -s - "$SD/f2.txt" \
  || { echo "f2.txt is present and not the new version ($(wc -c < "$SD/f2.txt") bytes)"; exit 1; }
printf 'keep\n' | cmp -s - "$SD/keep.txt" || { echo "keep.txt changed"; exit 1; }
exit 0
EOX
chmod 755 "$AP"/*.sh

########## drivers ##########
summ() {  # summ <json> <label>
  python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
print(sys.argv[2], d.get('verdict'), d.get('unknown_reason') or '', 'cp='+str(d.get('crash_points')), 'hash='+str(d.get('prefix_hash'))[:16])" "$1" "$2" 2>/dev/null || echo "$2: no report"
}

go() {  # go <name> <setup> <op template> <check> [extra args...]
  name=$1; setup=$2; optmpl=$3; chk=$4; shift 4
  case "${ONLY:-}" in "") ;; *" $name "*) ;; *) return 0 ;; esac
  for mode in wrappers syscalls; do
    SD="$R/st/$mode/$name"; export SD
    mkdir -p "$SD" "$R/wk/$mode/$name"
    op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
    echo "==================== $name / $mode ===================="
    echo "op: $op"
    "$SE" explore --state "$SD" --setup "$AP/$setup" --operation "$op" \
      --check "$AP/$chk" --shim "$SHIM" --oracle /usr/bin/strace \
      --observe "$mode" --work "$R/wk/$mode/$name" \
      --json "$OUT/$name.$mode.json" "$@" > "$OUT/$name.$mode.txt" 2>&1
    echo "raw rc=$?   (0=PASS 1=FAIL 2=UNKNOWN 3=setup error)"
    grep -E "^(PASS|FAIL|UNKNOWN|SETUP ERROR)" "$OUT/$name.$mode.txt" | head -2
    grep -E "^ *(explored|oracle|checker|processes|earliest|violation|crash point)" "$OUT/$name.$mode.txt" | head -6 | cut -c1-260
    echo
  done
}

rep() {  # rep <name> <setup> <op template> <check>
  name=$1; setup=$2; optmpl=$3; chk=$4
  case "${ONLY:-}" in "") ;; *" $name "*) ;; *) return 0 ;; esac
  echo "==================== $name x5 / wrappers ===================="
  for i in 1 2 3 4 5; do
    SD="$R/st/rep$i/$name"; export SD
    mkdir -p "$SD" "$R/wk/rep$i/$name"
    op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
    "$SE" explore --state "$SD" --setup "$AP/$setup" --operation "$op" \
      --check "$AP/$chk" --shim "$SHIM" --oracle /usr/bin/strace \
      --work "$R/wk/rep$i/$name" --json "$OUT/$name.rep$i.json" > "$OUT/$name.rep$i.txt" 2>&1
    summ "$OUT/$name.rep$i.json" "run $i"
  done
  echo
}

prep() {  # prep <name> <setup> <op template>: the refusal, five times
  name=$1; setup=$2; optmpl=$3
  case "${ONLY:-}" in "") ;; *" $name "*) ;; *) return 0 ;; esac
  echo "==================== $name preflight x5 / wrappers ===================="
  for i in 1 2 3 4 5; do
    SD="$R/st/prep$i/$name"; export SD
    mkdir -p "$SD" "$R/wk/prep$i/$name"
    op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
    "$SE" preflight --state "$SD" --setup "$AP/$setup" --operation "$op" \
      --shim "$SHIM" --oracle /usr/bin/strace \
      --work "$R/wk/prep$i/$name" > "$OUT/$name.prep$i.txt" 2>&1
    printf 'run %s rc=%s  ' "$i" "$?"
    grep -m1 -E '^(UNKNOWN|PREFLIGHT)' "$OUT/$name.prep$i.txt" | tr -s ' '
    grep -m1 -E 'two threads of process|divergence at operation' "$OUT/$name.prep$i.txt" | sed -E 's/process [0-9]+/process N/; s/tid [0-9]+/tid N/g; s/^ +/    /' | cut -c1-220
  done
  echo
}

go  newsboat setup-newsboat2.sh 'newsboat -u @SD@/urls -c @SD@/cache.db -C @SD@/config -x reload' check-newsboat.sh
go  newsboat3 setup-newsboat3.sh 'newsboat -u @SD@/urls -c @SD@/cache.db -C @SD@/config -x reload' check-newsboat.sh
go  oxipng   setup-oxipng.sh    'oxipng -q -o 2 @SD@/a.png'            check-oxipng.sh
go  rsync    setup-rsync.sh     'rsync -a /localrun/aux/rsrc/ @SD@/'   check-rsync.sh
rep oxipng   setup-oxipng.sh    'oxipng -q -o 2 @SD@/a.png'            check-oxipng.sh
rep rsync    setup-rsync.sh     'rsync -a /localrun/aux/rsrc/ @SD@/'   check-rsync.sh
prep joplin  setup-joplin.sh    'joplin --profile @SD@ mknote SecondNote'
prep bun     setup-bun.sh       'bun add --cwd @SD@ /localrun/aux/bun/dep-1.0.0.tgz'
