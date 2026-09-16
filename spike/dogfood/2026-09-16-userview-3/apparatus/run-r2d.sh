#!/bin/sh
set -u
SE=/se/sideeye; SHIM=/se/libsideeye_shim.so
R=/localrun; AP=$R/ap; OUTE=/out/explore
mkdir -p "$AP" "$OUTE" "$R/wk" "$R/st" "$R/aux"

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
cat > "$AP/fish.toml" <<'EOT'
[world]
state = "/localrun/st/fi"
[define]
setup = "/localrun/ap/setup-fish.sh"
operation = ["fish", "-c", "echo MARKER-third-entry"]
check = "/localrun/ap/check-fish.sh"
EOT
cat > "$AP/setup-composer.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
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
cat > "$AP/check-composer.sh" <<'EOC'
#!/bin/sh
[ -f "$SD/vendor/autoload.php" ] || { echo "vendor/autoload.php が無い"; exit 1; }
php -d error_reporting=0 -r "require '$SD/vendor/autoload.php'; \$a = new Probe\\A(); \$b = new Probe\\B(); if (Probe\\A::MARKER !== 'keep-me' || Probe\\B::MARKER !== 'keep-me-too') { exit(3); } exit(0);" 2>/tmp/e.txt
rc=$?
[ $rc -eq 0 ] || { echo "autoload から Probe\\A / Probe\\B が読めない（rc=$rc）: $(head -2 /tmp/e.txt | tr '\n' ' ' | cut -c1-140)"; exit 1; }
exit 0
EOC
chmod 755 "$AP"/*.sh

ex() { name=$1; state=$2; setup=$3; op=$4; chk=$5; shift 5
  mkdir -p "$R/wk/ex-$name" "$state"
  echo "==================== explore: $name ===================="
  SD="$state" "$SE" explore --state "$state" --setup "$setup" --operation "$op" --check "$chk" \
    --shim "$SHIM" --oracle /usr/bin/strace --work "$R/wk/ex-$name" --json "$OUTE/$name.json" "$@" > "$OUTE/$name.txt" 2>&1
  echo "raw rc=$?"; head -13 "$OUTE/$name.txt"; echo; }
exc() { name=$1; cfg=$2; shift 2
  mkdir -p "$R/wk/ex-$name"
  echo "==================== explore(config): $name ===================="
  "$SE" explore --config "$cfg" --shim "$SHIM" --oracle /usr/bin/strace \
    --work "$R/wk/ex-$name" --json "$OUTE/$name.json" "$@" > "$OUTE/$name.txt" 2>&1
  echo "raw rc=$?"; head -13 "$OUTE/$name.txt"; echo; }

XDG_DATA_HOME=/localrun/st/fi; export XDG_DATA_HOME
SD=/localrun/st/fi exc fish3 "$AP/fish.toml"
unset XDG_DATA_HOME

# まず checker が baseline を通るかを、engine の外で確かめる
CO=$R/st/co; COMPOSER_HOME=$R/aux/composer; export COMPOSER_HOME; mkdir -p "$COMPOSER_HOME" "$CO"
SD="$CO" sh "$AP/setup-composer.sh"
composer --working-dir="$CO" --no-interaction -q --optimize dump-autoload
SD="$CO" sh "$AP/check-composer.sh"; echo "checker を手で回した rc=$?"
ex composer3 "$CO" "$AP/setup-composer.sh" "composer --working-dir=$CO --no-interaction -q --optimize dump-autoload" "$AP/check-composer.sh"
