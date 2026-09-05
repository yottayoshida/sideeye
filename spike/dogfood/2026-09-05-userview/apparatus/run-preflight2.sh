#!/bin/sh
# 第2ラウンド: 1回目に出た壁を、外せるものは外して測り直す。
# 外し方は測る前にここに書いてある（rule 16 の作法）。
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
OUT=/work/out
mkdir -p "$OUT"

run() {
  name=$1; shift
  echo "==================== $name ===================="
  "$SE" preflight "$@" --shim "$SHIM" > "$OUT/$name.txt" 2>&1
  rc=$?
  echo "raw rc=$rc"
  head -6 "$OUT/$name.txt"
  echo
}

########## 1. chezmoi: operation をフルパスにする ##########
# 1回目の refusal は「1語目がパスを名乗らないので PATH 解決になった」と言った。
# 静的リンクが本当の理由かどうかを、この1点だけ変えて確かめる。
mkdir -p /work/cz/src /work/cz/dest
printf 'hello from chezmoi\n' > /work/cz/src/dot_testrc
printf 'second file\n'        > /work/cz/src/dot_second
echo "chezmoi の実体: $(command -v chezmoi)"
run chezmoi-fullpath \
  --state /work/cz/dest \
  --operation "/usr/local/bin/chezmoi apply --source /work/cz/src --destination /work/cz/dest --no-tty"

########## 2. beets: threaded: no でスレッドを止める ##########
mkdir -p /work/bt/lib /work/bt/in1 /work/bt/in2
for n in 1 2; do
  ffmpeg -loglevel error -f lavfi -i anullsrc=r=44100:cl=mono -t 1 \
    -metadata title="Track$n" -metadata artist="Artist$n" -metadata album="Album$n" \
    "/work/bt/in$n/track$n.mp3"
done
cat > /work/bt/config.yaml <<'CFG'
directory: /work/bt/lib
library: /work/bt/lib/library.db
threaded: no
import:
  copy: yes
  write: yes
  quiet: yes
  autotag: no
CFG
beet -c /work/bt/config.yaml import -q /work/bt/in1 > "$OUT/beets2-setup.txt" 2>&1
echo "beets setup raw rc=$?"
run beets-nothread \
  --state /work/bt/lib \
  --operation "$(command -v beet) -c /work/bt/config.yaml import -q /work/bt/in2"

########## 3. gopass: pinentry を通さずに age の鍵を使えるか ##########
export GOPASS_HOMEDIR=/work/gp2
mkdir -p /work/gp2
echo "--- 環境変数で pinentry を回避できるか（gopass の age 実装を探る）---"
gopass --help 2>&1 | grep -iE "age|passphrase|pinentry" | head -5
export GOPASS_AGE_PASSWORD=testpassphrase
gopass --yes setup --crypto age --storage fs --name tester --email tester@example.com \
  > "$OUT/gopass2-setup.txt" 2>&1
echo "gopass setup raw rc=$?"
tail -6 "$OUT/gopass2-setup.txt"
printf 'hunter2\n' | gopass insert -f test/entry1 > "$OUT/gopass2-insert.txt" 2>&1
echo "gopass insert raw rc=$?"
tail -3 "$OUT/gopass2-insert.txt"
find /work/gp2 -type f 2>/dev/null | sort | sed 's/^/  /' | head -10
