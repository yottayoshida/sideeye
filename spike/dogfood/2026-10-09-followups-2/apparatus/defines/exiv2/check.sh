#!/bin/sh
# 2026-09-05's checker: each picture is still a picture identify can read.
for n in 1 2 3; do
  f="$SIDEEYE_STATE_DIR/pic$n.jpg"
  [ -f "$f" ] || { echo "pic$n.jpg is missing"; exit 1; }
  identify "$f" > /dev/null 2>&1 || { echo "identify cannot read pic$n.jpg ($(wc -c < "$f") bytes)"; exit 1; }
done
exit 0
