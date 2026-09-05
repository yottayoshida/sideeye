#!/bin/sh
# 対象ごとに sideeye preflight を回す。rc は必ずパイプに通す前に取る。
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
OUT=/work/out
mkdir -p "$OUT"

run() {  # run <名前> <preflight 引数...>
  name=$1; shift
  echo "==================== $name ===================="
  "$SE" preflight "$@" --shim "$SHIM" > "$OUT/$name.txt" 2>&1
  rc=$?
  echo "raw rc=$rc"
  tail -22 "$OUT/$name.txt"
  echo
}

########## 1. chezmoi（静的リンクの壁を実測する）##########
mkdir -p /work/cz/src /work/cz/dest
printf 'hello from chezmoi\n' > /work/cz/src/dot_testrc
printf 'second file\n'        > /work/cz/src/dot_second
run chezmoi \
  --state /work/cz/dest \
  --operation "chezmoi apply --source /work/cz/src --destination /work/cz/dest --no-tty"

########## 2. beets（反例を狙う枠）##########
mkdir -p /work/bt/lib /work/bt/in1 /work/bt/in2
for n in 1 2; do
  ffmpeg -loglevel error -f lavfi -i anullsrc=r=44100:cl=mono -t 1 \
    -metadata title="Track$n" -metadata artist="Artist$n" -metadata album="Album$n" \
    "/work/bt/in$n/track$n.mp3"
done
cat > /work/bt/config.yaml <<'CFG'
directory: /work/bt/lib
library: /work/bt/lib/library.db
import:
  copy: yes
  write: yes
  quiet: yes
  autotag: no
CFG
# setup で1曲目を入れて lib を作る（DB マイグレーションの .bak もここで済ませる）
beet -c /work/bt/config.yaml import -q /work/bt/in1 > "$OUT/beets-setup.txt" 2>&1
echo "beets setup raw rc=$?"
echo "--- setup 後の lib ---"
find /work/bt/lib -type f | sort | sed 's/^/  /'
run beets \
  --state /work/bt/lib \
  --operation "beet -c /work/bt/config.yaml import -q /work/bt/in2"

########## 3. gopass（age の鍵を非対話で作れるか）##########
export GOPASS_HOMEDIR=/work/gp
mkdir -p /work/gp
gopass --yes setup --crypto age --storage fs --name tester --email tester@example.com > "$OUT/gopass-setup.txt" 2>&1
echo "gopass setup raw rc=$?"
tail -8 "$OUT/gopass-setup.txt"
printf 'hunter2\n' | gopass insert -f test/entry1 > "$OUT/gopass-insert.txt" 2>&1
echo "gopass insert raw rc=$?"
tail -4 "$OUT/gopass-insert.txt"
echo "--- store の中身 ---"
find /work/gp -type f | sort | sed 's/^/  /' | head -12
