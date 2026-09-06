#!/bin/sh
# screen 第2弾: Python 枠を実操作で測る。
set -u
mkdir -p /work/d2/a /work/d2/b
cd /work/d2

# vdirsyncer: ローカル vdir 2つを同期させる。リモートは要らない。
cat > /work/d2/conf <<'CONF'
[general]
status_path = "/work/d2/status"

[pair testpair]
a = "sidea"
b = "sideb"
collections = null

[storage sidea]
type = "filesystem"
path = "/work/d2/a"
fileext = ".ics"

[storage sideb]
type = "filesystem"
path = "/work/d2/b"
fileext = ".ics"
CONF

cat > /work/d2/a/one.ics <<'ICS'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:probe-one
DTSTAMP:20260101T000000Z
DTSTART:20260101T090000Z
SUMMARY:probe event one
END:VEVENT
END:VCALENDAR
ICS

printf 'select a,b from t where a=1\n' > /work/d2/q.sql

echo "--- 素材 ---"
ls -la /work/d2 /work/d2/a

check() {
  name=$1; bin=$2; shift 2
  path=$(command -v "$bin" 2>/dev/null)
  if [ -z "$path" ]; then printf "%-12s 見つからない\n" "$name"; return 0; fi
  kind=$(file -L "$path" | cut -d: -f2- | cut -c1-40)
  if file -L "$path" | grep -q "statically linked"; then link=static
  elif file -L "$path" | grep -qi "ELF"; then link=dynamic
  else link=script; fi
  strace -f -e trace=clone,clone3 -o /tmp/tr.txt "$@" > /tmp/op.txt 2>&1
  rc=$?
  th=$(grep -c CLONE_THREAD /tmp/tr.txt 2>/dev/null | head -1)
  ch=$(grep -c clone /tmp/tr.txt 2>/dev/null | head -1)
  printf "%-12s %-8s thread=%-4s clone=%-4s rc=%-3s %s\n" \
    "$name" "$link" "$th" "$ch" "$rc" "$kind"
  if [ "$rc" -ne 0 ]; then
    echo "    失敗: $(head -4 /tmp/op.txt | tr '\n' ' ' | cut -c1-200)"
  fi
  return 0
}

echo
echo "=== screen 第2弾 ==="
echo "--- vdirsyncer discover（対話を要求するかも見る）---"
check vd-discover vdirsyncer vdirsyncer -c /work/d2/conf discover
echo "--- vdirsyncer sync（これが測る操作）---"
check vd-sync    vdirsyncer vdirsyncer -c /work/d2/conf sync
echo "--- sqlfluff fix ---"
# sqlfluff: pypi に届かないので screen できない（Dockerfile のコメント参照）

echo
echo "--- 同期後 ---"
ls -la /work/d2/a /work/d2/b
echo "--- sql ---"
cat /work/d2/q.sql
