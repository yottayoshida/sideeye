#!/bin/sh
# ラウンド2: preflight → explore を 5 対象で。
set -u
SE=/se/sideeye; SHIM=/se/libsideeye_shim.so
R=/localrun; AP=$R/ap; OUTP=/out/preflight; OUTE=/out/explore
mkdir -p "$AP" "$OUTP" "$OUTE" "$R/wk" "$R/st" "$R/aux"
"$SE" version

########## setup ##########
cat > "$AP/setup-fish.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
XDG_DATA_HOME="$SD" fish -c 'echo MARKER-first-entry' >/dev/null
XDG_DATA_HOME="$SD" fish -c 'echo MARKER-second-entry' >/dev/null
EOS

cat > "$AP/setup-pip.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
W=$(ls /usr/share/python-wheels/setuptools-*.whl | head -1)
pip3 install -q --no-index --no-deps --no-compile --target "$SD" "$W" >/dev/null 2>&1
EOS

cat > "$AP/setup-rrd.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
rm -f "$SD/t.rrd"
rrdtool create "$SD/t.rrd" --start 1700000000 --step 60 \
  DS:v:GAUGE:120:U:U RRA:AVERAGE:0.5:1:100 RRA:MAX:0.5:5:50
rrdtool update "$SD/t.rrd" 1700000060:11 1700000120:22
EOS

cat > "$AP/setup-composer.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD/src"
printf '{"name":"probe/probe","autoload":{"psr-4":{"Probe\\\\":"src/"}}}' > "$SD/composer.json"
printf '<?php namespace Probe; class A { const MARKER = "keep-me"; }\n' > "$SD/src/A.php"
composer --working-dir="$SD" --no-interaction -q dump-autoload >/dev/null 2>&1
EOS

cat > "$AP/setup-precommit.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
cd "$SD"
git init -q . 2>/dev/null || true
git config user.email probe@example.invalid; git config user.name probe
printf 'repos:\n- repo: meta\n  hooks:\n  - id: check-useless-excludes\n' > .pre-commit-config.yaml
# 利用者が前から置いていた hook。pre-commit install はこれを .legacy へ退避すると約束している。
printf '#!/bin/sh\n# MARKER-legacy-hook\necho legacy\n' > .git/hooks/pre-commit
chmod 755 .git/hooks/pre-commit
EOS

########## checker ##########
cat > "$AP/check-fish.sh" <<'EOC'
#!/bin/sh
# 履歴に追記している途中で落ちても、前からあったエントリは引ける。
out=$(XDG_DATA_HOME="$SD" fish -c 'history search --contains MARKER-first-entry' 2>/tmp/e.txt) || {
  echo "fish の history 検索が失敗した: $(head -1 /tmp/e.txt)"; exit 1; }
echo "$out" | grep -q "MARKER-first-entry" || {
  echo "前からあった履歴 MARKER-first-entry が引けない（$(wc -c < "$SD/fish/fish_history" 2>/dev/null) bytes）"; exit 1; }
exit 0
EOC

cat > "$AP/check-pip.sh" <<'EOC'
#!/bin/sh
# 追加インストールの途中で落ちても、前から入っていたものは壊れない。
[ -d "$SD/setuptools" ] || { echo "前から入っていた setuptools のディレクトリが無い"; exit 1; }
PYTHONPATH="$SD" python3 -c "import setuptools, sys; sys.exit(0)" 2>/tmp/e.txt || {
  echo "setuptools が import できなくなった: $(tail -1 /tmp/e.txt)"; exit 1; }
d=$(ls -d "$SD"/setuptools-*.dist-info 2>/dev/null | head -1)
[ -n "$d" ] || { echo "setuptools の dist-info が無い"; exit 1; }
[ -f "$d/RECORD" ] || { echo "setuptools の RECORD が無い（インストール記録が消えた）"; exit 1; }
exit 0
EOC

cat > "$AP/check-rrd.sh" <<'EOC'
#!/bin/sh
# 更新の途中で落ちても、RRD は読めて、前に入れた値は残っている。
rrdtool info "$SD/t.rrd" > /tmp/info.txt 2>/tmp/e.txt || {
  echo "rrdtool info が読めない（$(wc -c < "$SD/t.rrd" 2>/dev/null) bytes）: $(head -1 /tmp/e.txt)"; exit 1; }
grep -q "ds\[v\]" /tmp/info.txt || { echo "データソース v が info に出てこない"; exit 1; }
rrdtool fetch "$SD/t.rrd" AVERAGE --start 1700000000 --end 1700000180 > /tmp/f.txt 2>/tmp/e2.txt || {
  echo "rrdtool fetch が失敗した: $(head -1 /tmp/e2.txt)"; exit 1; }
grep -qE '1700000120: 2\.2' /tmp/f.txt || {
  echo "前に入れた 1700000120 の値 22 が消えた（fetch: $(tr '\n' ' ' < /tmp/f.txt | cut -c1-120)）"; exit 1; }
exit 0
EOC

cat > "$AP/check-composer.sh" <<'EOC'
#!/bin/sh
# autoload の作り直しの途中で落ちても、require したら前から在るクラスが読める。
[ -f "$SD/vendor/autoload.php" ] || { echo "vendor/autoload.php が無い"; exit 1; }
php -d error_reporting=0 -r "require '$SD/vendor/autoload.php'; \$a = new Probe\\A(); if (Probe\\A::MARKER !== 'keep-me') { exit(3); } exit(0);" 2>/tmp/e.txt
rc=$?
[ $rc -eq 0 ] || { echo "autoload から Probe\\A が読めない（rc=$rc）: $(head -2 /tmp/e.txt | tr '\n' ' ' | cut -c1-120)"; exit 1; }
exit 0
EOC

cat > "$AP/check-precommit.sh" <<'EOC'
#!/bin/sh
# pre-commit install は、前からあった hook を .legacy へ退避すると文書で約束している。
# 落ちた後に「前の hook も .legacy も無い」なら、利用者は自分の hook を失う。
h="$SD/.git/hooks/pre-commit"
l="$SD/.git/hooks/pre-commit.legacy"
if [ -f "$l" ] && grep -q "MARKER-legacy-hook" "$l"; then exit 0; fi
if [ -f "$h" ] && grep -q "MARKER-legacy-hook" "$h"; then exit 0; fi
echo "前からあった hook が本体にも .legacy にも無い（本体 $( [ -f "$h" ] && wc -c < "$h" || echo なし ) / 退避 $( [ -f "$l" ] && wc -c < "$l" || echo なし )）"
exit 1
EOC

chmod 755 "$AP"/*.sh

pf() { name=$1; state=$2; setup=$3; op=$4; shift 4
  echo "-------- preflight: $name --------"; mkdir -p "$R/wk/pf-$name" "$state"
  SD="$state" "$SE" preflight --state "$state" --setup "$setup" --operation "$op" \
    --shim "$SHIM" --work "$R/wk/pf-$name" "$@" > "$OUTP/$name.txt" 2>&1
  echo "raw rc=$?"; grep -E "^PREFLIGHT|^UNKNOWN|state-changing|^SETUP" "$OUTP/$name.txt" | head -3; }

ex() { name=$1; state=$2; setup=$3; op=$4; chk=$5; shift 5
  echo "==================== explore: $name ===================="; mkdir -p "$R/wk/ex-$name" "$state"
  SD="$state" "$SE" explore --state "$state" --setup "$setup" --operation "$op" --check "$chk" \
    --shim "$SHIM" --oracle /usr/bin/strace --work "$R/wk/ex-$name" --json "$OUTE/$name.json" "$@" > "$OUTE/$name.txt" 2>&1
  echo "raw rc=$?   (0=PASS 1=FAIL 2=UNKNOWN 3=setup error)"; head -12 "$OUTE/$name.txt"; echo; }

FI=$R/st/fi; PI=$R/st/pi; RR=$R/st/rr; CO=$R/st/co; PC=$R/st/pc
WHL_PIP=$(ls /usr/share/python-wheels/pip-*.whl | head -1)

XDG_DATA_HOME=$FI; export XDG_DATA_HOME
pf fish "$FI" "$AP/setup-fish.sh" "fish -c echo_MARKER-third-entry"
ex fish "$FI" "$AP/setup-fish.sh" "fish -c echo_MARKER-third-entry" "$AP/check-fish.sh"
unset XDG_DATA_HOME

pf pip "$PI" "$AP/setup-pip.sh" "pip3 install --no-index --no-deps --no-compile --target $PI $WHL_PIP"
ex pip "$PI" "$AP/setup-pip.sh" "pip3 install --no-index --no-deps --no-compile --target $PI $WHL_PIP" "$AP/check-pip.sh"

pf rrdtool "$RR" "$AP/setup-rrd.sh" "rrdtool update $RR/t.rrd 1700000180:33"
ex rrdtool "$RR" "$AP/setup-rrd.sh" "rrdtool update $RR/t.rrd 1700000180:33" "$AP/check-rrd.sh"

COMPOSER_HOME=$R/aux/composer; export COMPOSER_HOME; mkdir -p "$COMPOSER_HOME"
pf composer "$CO" "$AP/setup-composer.sh" "composer --working-dir=$CO --no-interaction -q dump-autoload"
ex composer "$CO" "$AP/setup-composer.sh" "composer --working-dir=$CO --no-interaction -q dump-autoload" "$AP/check-composer.sh"

PRE_COMMIT_HOME=$R/aux/pc; export PRE_COMMIT_HOME; mkdir -p "$PRE_COMMIT_HOME"
pf precommit "$PC" "$AP/setup-precommit.sh" "pre-commit install" --cwd "$PC"
ex precommit "$PC" "$AP/setup-precommit.sh" "pre-commit install" "$AP/check-precommit.sh" --cwd "$PC"
