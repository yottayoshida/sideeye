#!/bin/sh
# What the first review of this record asked for: claims RESULTS made from measurements
# taken by hand and never recorded, and one that was never measured. Run in the image with
# the release tarball at /se and this directory at /hostap:
#
#   docker run --rm -v <tarball dir>:/se:ro -v <this dir>:/hostap:ro \
#     sideeye-dogfood:2026-09-11 sh /hostap/probes-review.sh
set -u
SE=/se/sideeye
SHIM=/se/libsideeye_shim.so
ONLY=" none " sh /hostap/explore.sh > /dev/null 2>&1   # materialise the setups and checkers
AP=/localrun/ap
export HOME=/localrun/aux/home BUN_INSTALL_CACHE_DIR=/localrun/aux/bun-cache TMPDIR=/localrun/aux/tmp
mkdir -p "$HOME" "$BUN_INSTALL_CACHE_DIR" "$TMPDIR"

echo "==================== versions ===================="
"$SE" version
dpkg-query -W -f='${Package} ${Version}\n' newsboat rsync ocrmypdf tesseract-ocr ghostscript ansible-core python3 libc6 nodejs
echo "oxipng: $(oxipng --version)"; echo "bun: $(bun --version)"; echo "node: $(node --version)"
npm ls -g joplin 2>/dev/null | grep joplin
echo "PTHREAD_STACK_MIN $(getconf PTHREAD_STACK_MIN)"

echo
echo "==================== newsboat: plain preflight and --twice, undated (newsboat2) and dated (newsboat3) ===================="
for def in newsboat2 newsboat3; do
  for m in wrappers syscalls; do
    for tw in plain twice; do
      SD=/localrun/st/pf-$def-$m-$tw; export SD; W=/localrun/wk/pf-$def-$m-$tw; mkdir -p "$SD" "$W"
      flag=; [ $tw = twice ] && flag=--twice
      "$SE" preflight $flag --state "$SD" --setup "$AP/setup-$def.sh" \
        --operation "newsboat -u $SD/urls -c $SD/cache.db -C $SD/config -x reload" \
        --shim "$SHIM" --oracle /usr/bin/strace --observe $m --work "$W" > /tmp/pf.txt 2>&1
      rc=$?
      printf '%s %-8s %-5s rc=%s  ' $def $m $tw $rc
      grep -m1 -E '^(PREFLIGHT|UNKNOWN|SETUP ERROR|TWICE|SPLIT)' /tmp/pf.txt | cut -c1-170 || head -1 /tmp/pf.txt
      grep -i -E 'differ|split|cache\.db' /tmp/pf.txt | head -3 | cut -c1-200 | sed 's/^/    /'
    done
  done
done

echo
echo "==================== newsboat: what an undated item is stamped with ===================="
for i in 1 2; do
  D=/localrun/aux/nbdate$i; mkdir -p "$D"
  printf '<?xml version="1.0"?>\n<rss version="2.0"><channel><title>p</title><link>http://example.invalid/</link><description>d</description><item><title>undated</title><link>http://example.invalid/u</link><guid>u</guid><description>u</description></item></channel></rss>\n' > "$D/feed.xml"
  printf 'file://%s/feed.xml\n' "$D" > "$D/urls"; : > "$D/config"
  before=$(date +%s)
  newsboat -u "$D/urls" -c "$D/cache.db" -C "$D/config" -x reload > /dev/null 2>&1
  python3 -c "import sqlite3,sys;print('run', sys.argv[2], 'read at', sys.argv[3], 'stored:', sqlite3.connect(sys.argv[1]).execute('select title, pubDate from rss_item').fetchall())" "$D/cache.db" $i "$before"
  sleep 2
done

echo
echo "==================== oxipng under ulimit -f 0, and its write path ===================="
SD=/localrun/st/ulimit; export SD; "$AP/setup-oxipng.sh"
echo "before: $(wc -c < "$SD/a.png") bytes"
( ulimit -f 0; oxipng -q -o 2 "$SD/a.png" ); echo "oxipng rc=$?"
echo "after:  $(wc -c < "$SD/a.png") bytes"
"$AP/setup-oxipng.sh"
strace -f -y -e trace=openat,write,rename,renameat,renameat2,unlink,unlinkat oxipng -q -o 2 "$SD/a.png" 2>&1 | grep -F "$SD"

echo
echo "==================== strace -k in this image ===================="
strace -V | head -1
strace -k -e trace=openat -o /dev/null true; echo "rc=$?"

echo
echo "==================== ansible: which call leaves the containment group ===================="
SD=/localrun/st/ansible-sid; export SD; "$AP/setup-ansible.sh"
strace -f -qq -e trace=setsid,setpgid,execve,clone,clone3,fork,vfork -o /tmp/an.txt \
  ansible localhost -c local -i localhost, -e ansible_python_interpreter=/usr/bin/python3 \
  -m lineinfile -a "{\"path\":\"$SD/f.txt\",\"line\":\"gamma\"}" > /dev/null 2>&1
echo "ansible rc=$?"
python3 - /tmp/an.txt <<'PY'
import re, sys
parent, prog, calls = {}, {}, []
for line in open(sys.argv[1]):
    m = re.match(r"^(\d+)\s+(\w+)\((.*)\)\s+=\s+(-?\d+)", line)
    if not m:
        continue
    pid, name, args, ret = int(m.group(1)), m.group(2), m.group(3), int(m.group(4))
    if name in ("clone", "clone3", "fork", "vfork") and ret > 0:
        parent[ret] = pid
    elif name == "execve" and ret == 0:
        prog[pid] = args.split(",", 1)[0].strip('"')
    elif name in ("setsid", "setpgid"):
        calls.append((pid, name, args, ret))
def who(p):
    return prog.get(p) or "(no exec of its own; a fork of %d, %s)" % (parent.get(p, -1), prog.get(parent.get(p, -1), "?"))
for pid, name, args, ret in calls:
    print("pid %d %s(%s) = %d   the process: %s" % (pid, name, args, ret, who(pid)))
if not calls:
    print("no setsid or setpgid in the capture")
PY

echo
echo "==================== --scratch with an absolute path ===================="
SD=/localrun/st/scr-abs; export SD; mkdir -p "$SD" /localrun/wk/scr-abs
"$SE" explore --state "$SD" --setup "$AP/setup-newsboat3.sh" \
  --operation "newsboat -u $SD/urls -c $SD/cache.db -C $SD/config -x reload" \
  --check "$AP/check-newsboat.sh" --scratch "$SD/cache.db" \
  --shim "$SHIM" --oracle /usr/bin/strace --work /localrun/wk/scr-abs > /tmp/scr.txt 2>&1
echo "explore rc=$?"; grep -m1 -E '^(SETUP ERROR|PASS|FAIL|UNKNOWN)' /tmp/scr.txt
