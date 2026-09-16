#!/bin/sh
# ラウンド1: preflight → explore を 5 対象で。
# state と work はコンテナ自身のファイルシステム（#528）。sideeye は /se に読み取り専用でマウント。
set -u
SE=/se/sideeye
SHIM=/se/libsideeye_shim.so
R=/localrun
AP=$R/ap
OUTP=/out/preflight
OUTE=/out/explore
mkdir -p "$AP" "$OUTP" "$OUTE" "$R/wk" "$R/st"
"$SE" version

########## setup ##########

cat > "$AP/setup-codespell.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
cat > "$SD/a.txt" <<'EOT'
MARKER-A keep this line
The reciever did not seperate the files.
Second line stays as it is.
EOT
cat > "$SD/b.txt" <<'EOT'
MARKER-B keep this line too
teh quick brown fox, occured twice.
EOT
cat > "$SD/c.txt" <<'EOT'
MARKER-C third file
adress and lenght are both wrong here.
EOT
EOS

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

cat > "$AP/setup-zstd.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
# 中身が確かめられるように、決まったバイト列で作る（乱数は使わない）。
python3 - "$SD/f.bin" <<'PY'
import sys
p = sys.argv[1]
with open(p, 'wb') as f:
    for i in range(20000):
        f.write(b"MARKER-%06d-payload\n" % i)
PY
cp "$SD/f.bin" /localrun/aux/f.bin.orig
EOS

cat > "$AP/setup-rubocop.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
cat > "$SD/a.rb" <<'EOT'
# MARKER-A
def greet( name )
  puts( "hello #{name}" )
end
greet( "world" )
EOT
cat > "$SD/b.rb" <<'EOT'
# MARKER-B
def add( a, b )
  a + b
end
puts( add( 1, 2 ) )
EOT
EOS

cat > "$AP/setup-zoxide.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD" /localrun/aux/dirs/kept /localrun/aux/dirs/new
# 既にエントリのある DB を作る（crash が壊すのは「前からあった状態」）。
_ZO_DATA_DIR="$SD" zoxide add /localrun/aux/dirs/kept
_ZO_DATA_DIR="$SD" zoxide query --list > /localrun/aux/zo-before.txt
EOS

########## checker ##########

cat > "$AP/check-codespell.sh" <<'EOC'
#!/bin/sh
# codespell --write-changes は「その場で直す」。直したかどうかは問わない。
# どのファイルも消えず、空にならず、元の MARKER 行が残っていること。
for n in a b c; do
  f="$SD/$n.txt"
  [ -f "$f" ] || { echo "$n.txt が無い"; exit 1; }
  [ -s "$f" ] || { echo "$n.txt が空になった"; exit 1; }
  m=$(echo "$n" | tr 'a-z' 'A-Z')
  grep -q "MARKER-$m" "$f" || { echo "$n.txt から MARKER-$m が消えた（$(wc -c < "$f") bytes）"; exit 1; }
done
# 3 ファイルとも行数が保たれている（途中で切れていない）
[ "$(wc -l < "$SD/a.txt")" -eq 3 ] || { echo "a.txt の行数が 3 でない: $(wc -l < "$SD/a.txt")"; exit 1; }
[ "$(wc -l < "$SD/b.txt")" -eq 2 ] || { echo "b.txt の行数が 2 でない: $(wc -l < "$SD/b.txt")"; exit 1; }
[ "$(wc -l < "$SD/c.txt")" -eq 2 ] || { echo "c.txt の行数が 2 でない: $(wc -l < "$SD/c.txt")"; exit 1; }
exit 0
EOC

cat > "$AP/check-vim.sh" <<'EOC'
#!/bin/sh
# vim が :wq で書いたファイルは、置換前か置換後のどちらかとして読める。
# 消える・空になる・途中で切れるのは、エディタが保存中に落ちた時に利用者が失うもの。
f="$SD/a.txt"
[ -f "$f" ] || { echo "a.txt が無い（保存中に落ちて消えた）"; exit 1; }
[ -s "$f" ] || { echo "a.txt が空になった"; exit 1; }
grep -q "MARKER" "$f" || { echo "a.txt から MARKER が消えた（$(wc -c < "$f") bytes）"; exit 1; }
[ "$(wc -l < "$f")" -eq 3 ] || { echo "a.txt の行数が 3 でない: $(wc -l < "$f")"; exit 1; }
grep -q "line three stays" "$f" || { echo "最終行が消えた"; exit 1; }
exit 0
EOC

cat > "$AP/check-zstd.sh" <<'EOC'
#!/bin/sh
# zstd --rm は「圧縮に成功してから」元を消す（man: after successful de/compression）。
# 原本がそのまま残っているか、.zst から元のバイト列が戻せるか、どちらかが成り立つこと。
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

cat > "$AP/check-rubocop.sh" <<'EOC'
#!/bin/sh
# rubocop -a（autocorrect）はソースをその場で書き換える。書き換えの途中で落ちても、
# 残ったファイルは Ruby として読めて、元の中身を持っていること。
for n in a b; do
  f="$SD/$n.rb"
  [ -f "$f" ] || { echo "$n.rb が無い"; exit 1; }
  [ -s "$f" ] || { echo "$n.rb が空になった"; exit 1; }
  ruby -c "$f" >/dev/null 2>&1 || { echo "$n.rb が Ruby として壊れている（$(wc -c < "$f") bytes）"; exit 1; }
  m=$(echo "$n" | tr 'a-z' 'A-Z')
  grep -q "MARKER-$m" "$f" || { echo "$n.rb から MARKER-$m が消えた"; exit 1; }
done
grep -q "def greet" "$SD/a.rb" || { echo "a.rb から def greet が消えた"; exit 1; }
grep -q "def add"   "$SD/b.rb" || { echo "b.rb から def add が消えた"; exit 1; }
exit 0
EOC

cat > "$AP/check-zoxide.sh" <<'EOC'
#!/bin/sh
# 追加の途中で落ちても、前からあったエントリは引ける（DB が読めなくならない）。
out=$(_ZO_DATA_DIR="$SD" zoxide query --list 2>/tmp/zoerr.txt) || {
  echo "zoxide query が失敗した: $(head -1 /tmp/zoerr.txt)"; exit 1; }
echo "$out" | grep -q "/localrun/aux/dirs/kept" || {
  echo "前からあった kept が引けない（出力: $(echo "$out" | tr '\n' ' ' | cut -c1-80)）"; exit 1; }
exit 0
EOC

chmod 755 "$AP"/*.sh
mkdir -p /localrun/aux

pf() {
  name=$1; state=$2; setup=$3; op=$4; shift 4
  echo "-------- preflight: $name --------"
  mkdir -p "$R/wk/pf-$name" "$state"
  SD="$state" "$SE" preflight --state "$state" --setup "$setup" --operation "$op" \
    --shim "$SHIM" --work "$R/wk/pf-$name" > "$OUTP/$name.txt" 2>&1
  echo "raw rc=$?"
  grep -E "^PREFLIGHT|^UNKNOWN|state-changing|detector" "$OUTP/$name.txt" | head -4
}

ex() {
  name=$1; state=$2; setup=$3; op=$4; chk=$5; shift 5
  echo "==================== explore: $name ===================="
  mkdir -p "$R/wk/ex-$name" "$state"
  SD="$state" "$SE" explore --state "$state" --setup "$setup" --operation "$op" --check "$chk" \
    --shim "$SHIM" --oracle /usr/bin/strace \
    --work "$R/wk/ex-$name" --json "$OUTE/$name.json" "$@" > "$OUTE/$name.txt" 2>&1
  echo "raw rc=$?   (0=PASS 1=FAIL 2=UNKNOWN 3=setup error)"
  head -18 "$OUTE/$name.txt"
  echo
}

export SD
CS_ST=$R/st/cs;  VI_ST=$R/st/vi;  ZS_ST=$R/st/zs;  RB_ST=$R/st/rb;  ZO_ST=$R/st/zo
CS_OP="codespell -w $CS_ST/a.txt $CS_ST/b.txt $CS_ST/c.txt"
VI_OP="vim -es -u NONE -c %s/old/new/g -c wq $VI_ST/a.txt"
ZS_OP="zstd -q --rm $ZS_ST/f.bin"
RB_OP="rubocop -a --force-default-config --only Layout/SpaceInsideParens $RB_ST/a.rb $RB_ST/b.rb"
ZO_OP="zoxide add /localrun/aux/dirs/new"

pf codespell "$CS_ST" "$AP/setup-codespell.sh" "$CS_OP"
pf vim       "$VI_ST" "$AP/setup-vim.sh"       "$VI_OP"
pf zstd      "$ZS_ST" "$AP/setup-zstd.sh"      "$ZS_OP"
pf rubocop   "$RB_ST" "$AP/setup-rubocop.sh"   "$RB_OP"
_ZO_DATA_DIR="$ZO_ST" export _ZO_DATA_DIR
pf zoxide    "$ZO_ST" "$AP/setup-zoxide.sh"    "$ZO_OP"
unset _ZO_DATA_DIR
echo

echo "######################## explore ########################"
ex codespell "$CS_ST" "$AP/setup-codespell.sh" "$CS_OP" "$AP/check-codespell.sh"
ex vim       "$VI_ST" "$AP/setup-vim.sh"       "$VI_OP" "$AP/check-vim.sh"
ex zstd      "$ZS_ST" "$AP/setup-zstd.sh"      "$ZS_OP" "$AP/check-zstd.sh"
ex rubocop   "$RB_ST" "$AP/setup-rubocop.sh"   "$RB_OP" "$AP/check-rubocop.sh"
_ZO_DATA_DIR="$ZO_ST" export _ZO_DATA_DIR
ex zoxide    "$ZO_ST" "$AP/setup-zoxide.sh"    "$ZO_OP" "$AP/check-zoxide.sh"
unset _ZO_DATA_DIR
