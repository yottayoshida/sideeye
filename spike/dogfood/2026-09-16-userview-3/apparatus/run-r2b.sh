#!/bin/sh
# ラウンド2 再測定。fish は argv 形式（空白入りの -c 引数）、pip と composer は
# setup で state を作り直してから測る（前の run の残りが operation をスキップさせていた疑い）。
set -u
SE=/se/sideeye; SHIM=/se/libsideeye_shim.so
R=/localrun; AP=$R/ap; OUTE=/out/explore
mkdir -p "$AP" "$OUTE" "$R/wk" "$R/st" "$R/aux"

clean='python3 -c "import shutil,sys,os,glob
d=sys.argv[1]
for p in glob.glob(os.path.join(d,\"*\"))+glob.glob(os.path.join(d,\".*\")):
    if os.path.basename(p) in (\".\",\"..\"): continue
    shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) and not os.path.islink(p) else os.unlink(p)"'

cat > "$AP/setup-fish.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
XDG_DATA_HOME="$SD" fish -c 'echo MARKER-first-entry' >/dev/null
XDG_DATA_HOME="$SD" fish -c 'echo MARKER-second-entry' >/dev/null
EOS
cat > "$AP/check-fish.sh" <<'EOC'
#!/bin/sh
out=$(XDG_DATA_HOME="$SD" fish -c 'history search --contains MARKER-first-entry' 2>/tmp/e.txt) || {
  echo "fish の history 検索が失敗した: $(head -1 /tmp/e.txt)"; exit 1; }
echo "$out" | grep -q "MARKER-first-entry" || {
  echo "前からあった履歴 MARKER-first-entry が引けない"; exit 1; }
exit 0
EOC
cat > "$AP/fish.toml" <<'EOT'
[world]
state = "/localrun/st/fi"
[define]
setup = "/localrun/ap/setup-fish.sh"
operation = ["fish", "-c", "echo MARKER-third-entry"]
check = "/localrun/ap/check-fish.sh"
EOT

cat > "$AP/setup-pip.sh" <<EOS
#!/bin/sh
set -eu
mkdir -p "\$SD"
$clean "\$SD"
W=\$(ls /usr/share/python-wheels/setuptools-*.whl | head -1)
pip3 install -q --no-index --no-deps --no-compile --target "\$SD" "\$W" >/dev/null 2>&1
EOS

cat > "$AP/setup-composer.sh" <<EOS
#!/bin/sh
set -eu
mkdir -p "\$SD"
$clean "\$SD"
mkdir -p "\$SD/src"
printf '{"name":"probe/probe","autoload":{"psr-4":{"Probe\\\\\\\\":"src/"}}}' > "\$SD/composer.json"
printf '<?php namespace Probe; class A { const MARKER = "keep-me"; }\n' > "\$SD/src/A.php"
composer --working-dir="\$SD" --no-interaction -q dump-autoload >/dev/null 2>&1
# 何が書かれたかを残す（この後の operation が本当に書くのかを見るため）
find "\$SD/vendor" -type f | head -20 > /localrun/aux/composer-after-setup.txt
md5sum \$(find "\$SD/vendor" -type f) > /localrun/aux/composer-md5-setup.txt 2>/dev/null || true
EOS
chmod 755 "$AP"/*.sh

exc() { name=$1; cfg=$2; shift 2
  echo "==================== explore(config): $name ===================="; mkdir -p "$R/wk/ex-$name"
  "$SE" explore --config "$cfg" --shim "$SHIM" --oracle /usr/bin/strace \
    --work "$R/wk/ex-$name" --json "$OUTE/$name.json" "$@" > "$OUTE/$name.txt" 2>&1
  echo "raw rc=$?"; head -12 "$OUTE/$name.txt"; echo; }
ex() { name=$1; state=$2; setup=$3; op=$4; chk=$5; shift 5
  echo "==================== explore: $name ===================="; mkdir -p "$R/wk/ex-$name" "$state"
  SD="$state" "$SE" explore --state "$state" --setup "$setup" --operation "$op" --check "$chk" \
    --shim "$SHIM" --oracle /usr/bin/strace --work "$R/wk/ex-$name" --json "$OUTE/$name.json" "$@" > "$OUTE/$name.txt" 2>&1
  echo "raw rc=$?"; head -12 "$OUTE/$name.txt"; echo; }

SD=/localrun/st/fi exc fish2 "$AP/fish.toml"

PI=$R/st/pi; WHL_PIP=$(ls /usr/share/python-wheels/pip-*.whl | head -1)
ex pip2 "$PI" "$AP/setup-pip.sh" "pip3 install --no-index --no-deps --no-compile --target $PI $WHL_PIP" /localrun/ap/check-pip.sh

CO=$R/st/co; COMPOSER_HOME=$R/aux/composer; export COMPOSER_HOME; mkdir -p "$COMPOSER_HOME"
ex composer2 "$CO" "$AP/setup-composer.sh" "composer --working-dir=$CO --no-interaction -q dump-autoload" /localrun/ap/check-composer.sh
echo "--- setup 後に vendor へ書かれていたファイル ---"; cat /localrun/aux/composer-after-setup.txt 2>/dev/null | head -8
echo "--- explore 後の vendor の md5 の差 ---"
md5sum $(find "$CO/vendor" -type f 2>/dev/null) 2>/dev/null | diff - /localrun/aux/composer-md5-setup.txt | head -8 || echo "(差なし)"
