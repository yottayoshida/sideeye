#!/bin/sh
# slate 2: preflight → explore を 3 対象で回す。
#
# checker は「読める」で止めない。slate 1 の mid3v2 が示したとおり、控えを作らない
# ツールは crash 後もファイルが読めるので、「読める」だけの checker は全 world で
# 通って何も検査しない。だから元からあった中身が残ることまで見る。
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
OUTP=/work/out2-pf
OUTE=/work/out2-ex
AP=/work/ap2
mkdir -p "$OUTP" "$OUTE" "$AP" /work/wk2-pf /work/wk2-ex

########## setup ##########

cat > "$AP/setup-ttf.sh" <<'EOS'
#!/bin/sh
mkdir -p /work/st2/ft
cp /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf /work/st2/ft/f.ttf
EOS

cat > "$AP/setup-tar.sh" <<'EOS'
#!/bin/sh
mkdir -p /work/st2/ar /tmp/tsrc
printf 'one\n'   > /tmp/tsrc/f1.txt
printf 'two\n'   > /tmp/tsrc/f2.txt
printf 'three\n' > /tmp/tsrc/f3.txt
bsdtar -cf /work/st2/ar/a.tar -C /tmp/tsrc f1.txt f2.txt
EOS

cat > "$AP/setup-bean.sh" <<'EOS'
#!/bin/sh
mkdir -p /work/st2/bc
cat > /work/st2/bc/l.beancount <<'EOB'
2026-01-01 open Assets:Cash
2026-01-01 open Expenses:Food
2026-01-02 * "lunch"
  Expenses:Food   10.00 JPY
  Assets:Cash
2026-01-03 * "coffee"
  Expenses:Food    3.50 JPY
  Assets:Cash
EOB
EOS

########## checker ##########

cat > "$AP/check-ttf.sh" <<'EOC'
#!/bin/sh
f=/work/st2/ft/f.ttf
[ -f "$f" ] || { echo "f.ttf が無い"; exit 1; }
fonttools ttx -q -o /dev/null "$f" > /dev/null 2>&1 || {
  echo "f.ttf を fonttools が読めない（$(wc -c < "$f") bytes）"; exit 1; }
exit 0
EOC

cat > "$AP/check-tar.sh" <<'EOC'
#!/bin/sh
a=/work/st2/ar/a.tar
[ -f "$a" ] || { echo "a.tar が無い"; exit 1; }
list=$(bsdtar -tf "$a" 2>/dev/null) || {
  echo "a.tar を bsdtar が読めない（$(wc -c < "$a") bytes）"; exit 1; }
for n in f1.txt f2.txt; do
  echo "$list" | grep -qx "$n" || {
    echo "a.tar から元のエントリ $n が消えた"; exit 1; }
done
exit 0
EOC

cat > "$AP/check-bean.sh" <<'EOC'
#!/bin/sh
f=/work/st2/bc/l.beancount
[ -f "$f" ] || { echo "l.beancount が無い"; exit 1; }
bean-check "$f" > /dev/null 2>&1 || {
  echo "l.beancount を bean-check が通せない（$(wc -c < "$f") bytes）"; exit 1; }
for t in lunch coffee; do
  grep -q "\"$t\"" "$f" || { echo "元の取引 $t が消えた"; exit 1; }
done
exit 0
EOC

chmod 755 "$AP"/*.sh
mkdir -p /work/st2/ft /work/st2/ar /work/st2/bc

pf() {  # pf <名前> <state> <setup> <operation>
  name=$1; state=$2; setup=$3; op=$4
  echo "-------- preflight: $name --------"
  mkdir -p "/work/wk2-pf/$name"
  "$SE" preflight --state "$state" --setup "$setup" --operation "$op" \
    --shim "$SHIM" --work "/work/wk2-pf/$name" > "$OUTP/$name.txt" 2>&1
  echo "raw rc=$?"
  grep -E "^PREFLIGHT|^UNKNOWN|state-changing|atomicity" "$OUTP/$name.txt" | head -4
}

ex() {  # ex <名前> <state> <setup> <operation> <check>
  name=$1; state=$2; setup=$3; op=$4; chk=$5
  echo "==================== explore: $name ===================="
  mkdir -p "/work/wk2-ex/$name"
  "$SE" explore --state "$state" --setup "$setup" --operation "$op" --check "$chk" \
    --shim "$SHIM" --oracle /usr/bin/strace \
    --work "/work/wk2-ex/$name" --json "$OUTE/$name.json" > "$OUTE/$name.txt" 2>&1
  echo "raw rc=$?   (0=PASS 1=FAIL 2=UNKNOWN 3=setup error)"
  head -16 "$OUTE/$name.txt"
  echo
}

FT_OP='fonttools subset /work/st2/ft/f.ttf --output-file=/work/st2/ft/f.ttf --unicodes=U+0041-005A'
AR_OP='bsdtar -uf /work/st2/ar/a.tar -C /tmp/tsrc f3.txt'
BC_OP='bean-format -o /work/st2/bc/l.beancount /work/st2/bc/l.beancount'

pf fonttools /work/st2/ft "$AP/setup-ttf.sh"  "$FT_OP"
pf bsdtar    /work/st2/ar "$AP/setup-tar.sh"  "$AR_OP"
pf beanfmt   /work/st2/bc "$AP/setup-bean.sh" "$BC_OP"
echo

ex fonttools /work/st2/ft "$AP/setup-ttf.sh"  "$FT_OP" "$AP/check-ttf.sh"
ex bsdtar    /work/st2/ar "$AP/setup-tar.sh"  "$AR_OP" "$AP/check-tar.sh"
ex beanfmt   /work/st2/bc "$AP/setup-bean.sh" "$BC_OP" "$AP/check-bean.sh"
