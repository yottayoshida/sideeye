#!/bin/sh
# data.root is scratch under --observe supervised: ROOT writes a fresh random UUID into it in every run, so
# two clean runs differ (2026-10-09 user-data-4). This judges the file through ROOT itself: rootls opens it
# and lists h1 and h3, the histograms the operation does not remove, with or without h2.
export PATH=/opt/root/bin:$PATH
out=$(rootls "$SIDEEYE_STATE_DIR/data.root" 2>&1) || { echo "rootls cannot read data.root: $(echo "$out" | tail -1 | cut -c1-120)"; exit 1; }
for h in h1 h3; do echo "$out" | grep -qw "$h" || { echo "data.root lost $h: $(echo "$out" | tr '\n' ' ' | cut -c1-120)"; exit 1; }; done
exit 0
