#!/bin/sh
# ラウンド2 の締め: fish は XDG_DATA_HOME を engine の環境に置いてから、composer は
# 出力が変わる操作（--optimize で classmap を作る）で測り直す。
set -u
SE=/se/sideeye; SHIM=/se/libsideeye_shim.so
R=/localrun; AP=$R/ap; OUTE=/out/explore
mkdir -p "$AP" "$OUTE" "$R/wk" "$R/st" "$R/aux"
cp /hostap/*.toml "$AP"/ 2>/dev/null
cp /hostap/check-*.sh "$AP"/ 2>/dev/null

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
echo "$out" | grep -q "MARKER-first-entry" || { echo "前からあった履歴 MARKER-first-entry が引けない"; exit 1; }
exit 0
EOC
cat > "$AP/setup-composer.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD/src"
python3 -c "
import shutil,sys,os,glob
d=sys.argv[1]
for p in glob.glob(os.path.join(d,'*')):
    shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) and not os.path.islink(p) else os.unlink(p)
" "$SD"
mkdir -p "$SD/src"
printf '{"name":"probe/probe","autoload":{"psr-4":{"Probe\\\\":"src/"}}}' > "$SD/composer.json"
printf '<?php namespace Probe; class A { const MARKER = "keep-me"; }\n' > "$SD/src/A.php"
printf '<?php namespace Probe; class B { const MARKER = "keep-me-too"; }\n' > "$SD/src/B.php"
composer --working-dir="$SD" --no-interaction -q dump-autoload >/dev/null 2>&1
EOS
chmod 755 "$AP"/*.sh

ex() { name=$1; state=$2; setup=$3; op=$4; chk=$5; shift 5
  echo "==================== explore: $name ===================="; mkdir -p "$R/wk/ex-$name" "$state"
  SD="$state" "$SE" explore --state "$state" --setup "$setup" --operation "$op" --check "$chk" \
    --shim "$SHIM" --oracle /usr/bin/strace --work "$R/wk/ex-$name" --json "$OUTE/$name.json" "$@" > "$OUTE/$name.txt" 2>&1
  echo "raw rc=$?"; head -12 "$OUTE/$name.txt"; echo; }
exc() { name=$1; cfg=$2; shift 2
  echo "==================== explore(config): $name ===================="; mkdir -p "$R/wk/ex-$name"
  "$SE" explore --config "$cfg" --shim "$SHIM" --oracle /usr/bin/strace \
    --work "$R/wk/ex-$name" --json "$OUTE/$name.json" "$@" > "$OUTE/$name.txt" 2>&1
  echo "raw rc=$?"; head -12 "$OUTE/$name.txt"; echo; }

XDG_DATA_HOME=/localrun/st/fi; export XDG_DATA_HOME
SD=/localrun/st/fi exc fish3 "$AP/fish.toml"
unset XDG_DATA_HOME

CO=$R/st/co; COMPOSER_HOME=$R/aux/composer; export COMPOSER_HOME; mkdir -p "$COMPOSER_HOME"
ex composer3 "$CO" "$AP/setup-composer.sh" "composer --working-dir=$CO --no-interaction -q --optimize dump-autoload" "$AP/check-composer.sh"
