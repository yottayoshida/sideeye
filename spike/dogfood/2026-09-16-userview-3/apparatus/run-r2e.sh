#!/bin/sh
# fish: 履歴は非対話では書かれない。universal variable（fish_variables）なら非対話で書く。
set -u
SE=/se/sideeye; SHIM=/se/libsideeye_shim.so
R=/localrun; AP=$R/ap; OUTE=/out/explore
mkdir -p "$AP" "$OUTE" "$R/wk" "$R/st/fv"
cat > "$AP/setup-fishv.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
XDG_CONFIG_HOME="$SD" fish -c 'set -U MARKER_KEPT keep-me' >/dev/null
XDG_CONFIG_HOME="$SD" fish -c 'set -U MARKER_SECOND also-here' >/dev/null
ls -la "$SD/fish" 2>/dev/null | head -5
EOS
cat > "$AP/check-fishv.sh" <<'EOC'
#!/bin/sh
out=$(XDG_CONFIG_HOME="$SD" fish -c 'echo $MARKER_KEPT' 2>/tmp/e.txt) || {
  echo "fish が起動できない: $(head -1 /tmp/e.txt)"; exit 1; }
[ "$out" = "keep-me" ] || {
  echo "前からあった変数 MARKER_KEPT が消えた（読めた値: '$out'、$(wc -c < "$SD/fish/fish_variables" 2>/dev/null) bytes）"; exit 1; }
exit 0
EOC
cat > "$AP/fishv.toml" <<'EOT'
[world]
state = "/localrun/st/fv"
[define]
setup = "/localrun/ap/setup-fishv.sh"
operation = ["fish", "-c", "set -U MARKER_THIRD third-value"]
check = "/localrun/ap/check-fishv.sh"
EOT
chmod 755 "$AP"/*.sh
XDG_CONFIG_HOME=/localrun/st/fv; export XDG_CONFIG_HOME
SD=/localrun/st/fv sh "$AP/setup-fishv.sh"
echo "--- setup 後の state ---"; find /localrun/st/fv -type f | head -5
mkdir -p "$R/wk/ex-fish4"
SD=/localrun/st/fv "$SE" explore --config "$AP/fishv.toml" --shim "$SHIM" --oracle /usr/bin/strace \
  --work "$R/wk/ex-fish4" --json "$OUTE/fish4.json" > "$OUTE/fish4.txt" 2>&1
echo "raw rc=$?"; head -14 "$OUTE/fish4.txt"
