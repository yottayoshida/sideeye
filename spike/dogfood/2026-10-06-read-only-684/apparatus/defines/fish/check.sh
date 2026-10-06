#!/bin/sh
out=$(XDG_CONFIG_HOME="/s/fish/state" fish -c 'echo $MARKER_KEPT' 2>/tmp/e.txt) || {
  echo "fish が起動できない: $(head -1 /tmp/e.txt)"; exit 1; }
[ "$out" = "keep-me" ] || {
  echo "前からあった変数 MARKER_KEPT が消えた（読めた値: '$out'、$(wc -c < "/s/fish/state/fish/fish_variables" 2>/dev/null) bytes）"; exit 1; }
exit 0
