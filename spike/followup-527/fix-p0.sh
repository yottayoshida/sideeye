#!/bin/sh
# R1 の P0: 最初の followup.sh は preflight --twice に --observe を渡していなかったので、
# 「両モードで測った」は嘘だった（出力2本がバイト同一）。ここで両モードを本当に測る。
# あわせて engine の同一性（version 行 + sha256）を artifact に残す（R1 の P2-1）。
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
R=/localrun
AP=$R/ap
OUT=$R/out
mkdir -p "$AP" "$OUT" "$R/wk"

{
  echo "# engine identity, recorded inside the box that ran the measurement"
  echo "## sideeye --version"
  "$SE" --version 2>&1 | head -1
  echo "## sha256"
  sha256sum "$SE" "$SHIM" 2>/dev/null || (cd / && shasum -a 256 "$SE" "$SHIM")
  echo "## uname"
  uname -m
} > "$OUT/engine-identity.txt"
cat "$OUT/engine-identity.txt"

cat > "$AP/setup-img.sh" <<'EOS'
#!/bin/sh
mkdir -p "$SD"
for n in 1 2 3; do
  ffmpeg -loglevel error -f lavfi -i color=c=red:s=128x128 -frames:v 1 -y "$SD/img$n.png"
done
EOS
chmod 755 "$AP"/*.sh

for mode in wrappers syscalls; do
  SD="$R/tw2/$mode/mogrify"; export SD
  mkdir -p "$SD" "$R/wk/tw2-$mode"
  echo "---- preflight --twice --observe $mode ----"
  "$SE" preflight --state "$SD" --setup "$AP/setup-img.sh" \
    --operation "/usr/bin/mogrify -resize 50% $SD/img1.png $SD/img2.png $SD/img3.png" \
    --shim "$SHIM" --observe "$mode" --work "$R/wk/tw2-$mode" --twice \
    > "$OUT/tw2-mogrify.$mode.txt" 2>&1
  echo "raw rc=$?"
  grep -nE "^PREFLIGHT|difference|repeatability|observe" "$OUT/tw2-mogrify.$mode.txt" | head -7
done
echo "=== are the two outputs distinguishable now?"
if cmp -s "$OUT/tw2-mogrify.wrappers.txt" "$OUT/tw2-mogrify.syscalls.txt"; then
  echo "IDENTICAL — preflight prints nothing about the mode; state that instead of claiming two measurements"
else
  echo "DIFFER — diff follows"
  diff "$OUT/tw2-mogrify.wrappers.txt" "$OUT/tw2-mogrify.syscalls.txt" | head -12
fi
mkdir -p /hostout; cp "$OUT/tw2-mogrify."*.txt "$OUT/engine-identity.txt" /hostout/
