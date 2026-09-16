#!/bin/sh
# ラウンド1 再測定: 1 回目に UNKNOWN で止まった 3 対象を define 側から直す。
#   zstd   — setup が前回の .zst を残していた（「既にある」で operation が exit 1）
#   vim    — getxattr。backup をやめた argv 形式の define を toml で書き、両方の観測モードで測る
#   zoxide — baseline が非決定的（db.zo に時刻が入る）。libfaketime を /etc/ld.so.preload に置き
#            apparatus で宣言する
set -u
SE=/se/sideeye
SHIM=/se/libsideeye_shim.so
R=/localrun
AP=$R/ap
OUTE=/out/explore
mkdir -p "$AP" "$OUTE" "$R/wk" "$R/st" "$R/aux"
"$SE" version

########## zstd: setup を直して測り直す ##########
cat > "$AP/setup-zstd.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
rm -f "$SD/f.bin.zst"
python3 - "$SD/f.bin" <<'PY'
import sys
with open(sys.argv[1], 'wb') as f:
    for i in range(20000):
        f.write(b"MARKER-%06d-payload\n" % i)
PY
cp "$SD/f.bin" /localrun/aux/f.bin.orig
EOS

cat > "$AP/check-zstd.sh" <<'EOC'
#!/bin/sh
orig=/localrun/aux/f.bin.orig
if [ -f "$SD/f.bin" ]; then
  cmp -s "$SD/f.bin" "$orig" && exit 0
  echo "f.bin が残っているが中身が違う（$(wc -c < "$SD/f.bin") bytes / 元 $(wc -c < "$orig")）"; exit 1
fi
if [ -f "$SD/f.bin.zst" ]; then
  zstd -q -d -c "$SD/f.bin.zst" > /tmp/out.bin 2>/tmp/zerr.txt || {
    echo "原本が消え、f.bin.zst も展開できない（$(wc -c < "$SD/f.bin.zst") bytes）: $(head -1 /tmp/zerr.txt)"; exit 1; }
  cmp -s /tmp/out.bin "$orig" && exit 0
  echo "原本が消え、f.bin.zst の中身が元と違う（展開 $(wc -c < /tmp/out.bin) / 元 $(wc -c < "$orig")）"; exit 1
fi
echo "原本も .zst も無い（データが消えた）"; exit 1
EOC

########## vim: backup を切った argv 形式 ##########
cat > "$AP/setup-vim.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
cat > "$SD/a.txt" <<'EOT'
MARKER line one old
line two old
line three stays
EOT
EOS
cat > "$AP/check-vim.sh" <<'EOC'
#!/bin/sh
f="$SD/a.txt"
[ -f "$f" ] || { echo "a.txt が無い（保存中に落ちて消えた）"; exit 1; }
[ -s "$f" ] || { echo "a.txt が空になった"; exit 1; }
grep -q "MARKER" "$f" || { echo "a.txt から MARKER が消えた（$(wc -c < "$f") bytes）"; exit 1; }
[ "$(wc -l < "$f")" -eq 3 ] || { echo "a.txt の行数が 3 でない: $(wc -l < "$f")"; exit 1; }
grep -q "line three stays" "$f" || { echo "最終行が消えた"; exit 1; }
exit 0
EOC
cat > "$AP/vim.toml" <<'EOT'
[world]
state = "/localrun/st/vi"
[define]
setup = "/localrun/ap/setup-vim.sh"
operation = ["vim", "-es", "-u", "NONE", "-c", "set nobackup noswapfile nowritebackup", "-c", "%s/old/new/g", "-c", "wq", "/localrun/st/vi/a.txt"]
check = "/localrun/ap/check-vim.sh"
EOT

########## zoxide: 時刻を固定する ##########
cat > "$AP/setup-zoxide.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD" /localrun/aux/dirs/kept /localrun/aux/dirs/new
_ZO_DATA_DIR="$SD" zoxide add /localrun/aux/dirs/kept
EOS
cat > "$AP/check-zoxide.sh" <<'EOC'
#!/bin/sh
out=$(_ZO_DATA_DIR="$SD" zoxide query --list 2>/tmp/zoerr.txt) || {
  echo "zoxide query が失敗した: $(head -1 /tmp/zoerr.txt)"; exit 1; }
echo "$out" | grep -q "/localrun/aux/dirs/kept" || {
  echo "前からあった kept が引けない（出力: $(echo "$out" | tr '\n' ' ' | cut -c1-80)）"; exit 1; }
exit 0
EOC
cat > "$AP/zoxide.toml" <<'EOT'
[world]
state = "/localrun/st/zo"
[define]
setup = "/localrun/ap/setup-zoxide.sh"
operation = ["zoxide", "add", "/localrun/aux/dirs/new"]
check = "/localrun/ap/check-zoxide.sh"
apparatus = ["env:FAKETIME=@2024-01-01 00:00:00", "preload:libfaketime"]
EOT

chmod 755 "$AP"/*.sh

ex() {  # ex <名前> <state> <setup> <operation> <check> [追加フラグ...]
  name=$1; state=$2; setup=$3; op=$4; chk=$5; shift 5
  echo "==================== explore: $name ===================="
  mkdir -p "$R/wk/ex-$name" "$state"
  SD="$state" "$SE" explore --state "$state" --setup "$setup" --operation "$op" --check "$chk" \
    --shim "$SHIM" --oracle /usr/bin/strace \
    --work "$R/wk/ex-$name" --json "$OUTE/$name.json" "$@" > "$OUTE/$name.txt" 2>&1
  echo "raw rc=$?   (0=PASS 1=FAIL 2=UNKNOWN 3=setup error)"
  head -14 "$OUTE/$name.txt"; echo
}

exc() {  # exc <名前> <state> <config> [追加フラグ...]
  name=$1; state=$2; cfg=$3; shift 3
  echo "==================== explore(config): $name ===================="
  mkdir -p "$R/wk/ex-$name" "$state"
  SD="$state" "$SE" explore --config "$cfg" \
    --shim "$SHIM" --oracle /usr/bin/strace \
    --work "$R/wk/ex-$name" --json "$OUTE/$name.json" "$@" > "$OUTE/$name.txt" 2>&1
  echo "raw rc=$?   (0=PASS 1=FAIL 2=UNKNOWN 3=setup error)"
  head -14 "$OUTE/$name.txt"; echo
}

ZS_ST=$R/st/zs
ex zstd "$ZS_ST" "$AP/setup-zstd.sh" "zstd -q --rm $ZS_ST/f.bin" "$AP/check-zstd.sh"

exc vim2 /localrun/st/vi "$AP/vim.toml"
exc vim2-syscalls /localrun/st/vi "$AP/vim.toml" --observe syscalls

echo "libfaketime を /etc/ld.so.preload に置く"
find / -name 'libfaketime.so*' 2>/dev/null | head -3
FT=$(find /usr/lib -name 'libfaketime.so*' 2>/dev/null | head -1)
echo "$FT" > /etc/ld.so.preload
cat /etc/ld.so.preload
FAKETIME="@2024-01-01 00:00:00" export FAKETIME
_ZO_DATA_DIR=/localrun/st/zo export _ZO_DATA_DIR
exc zoxide2 /localrun/st/zo "$AP/zoxide.toml"
: > /etc/ld.so.preload
