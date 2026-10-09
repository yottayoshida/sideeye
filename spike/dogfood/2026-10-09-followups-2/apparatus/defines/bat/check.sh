#!/bin/sh
out=$(BAT_CACHE_PATH="/s/bat/state" batcat --list-themes 2>/tmp/e.txt) || {
  echo "batcat がテーマ一覧を出せない: $(head -1 /tmp/e.txt | tr -d '\033')"; exit 1; }
echo "$out" | grep -q . || { echo "テーマ一覧が空（cache が壊れた）"; exit 1; }
exit 0
