#!/bin/sh
# mogrify's checker, as spike/followup-527's check-img.sh: each image is there and ImageMagick
# can read it.
for n in 1 2 3; do
  f="$SIDEEYE_STATE_DIR/img$n.png"
  [ -f "$f" ] || { echo "img$n.png is missing"; exit 1; }
  identify "$f" > /dev/null 2>&1 || { echo "identify cannot read img$n.png ($(wc -c < "$f") bytes)"; exit 1; }
done
exit 0
