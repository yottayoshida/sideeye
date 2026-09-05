#!/bin/sh
# 第3ラウンド: gopass の壁を測り、beets のスレッドがどこから来るかを切り分ける。
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
  head -5 "$OUT/$name.txt"
  echo
}

########## gopass: 非対話で書けるようになったので壁を測る ##########
export GOPASS_HOMEDIR=/work/gp3
export GOPASS_AGE_PASSWORD=testpassphrase
mkdir -p /work/gp3
gopass --yes setup --crypto age --storage fs --name tester --email tester@example.com \
  > "$OUT/gopass3-setup.txt" 2>&1
echo "gopass setup raw rc=$?"
printf 'first\n' | gopass insert -f seed/entry0 > /dev/null 2>&1
echo "seed insert raw rc=$?"
find /work/gp3/.local/share/gopass -type f | sort | sed 's/^/  /'

# 非対話の書き込みを1つ。stdin は engine が閉じるので --password 相当の形にする
cat > /work/gp3-op.sh <<'OP'
#!/bin/sh
export GOPASS_HOMEDIR=/work/gp3
export GOPASS_AGE_PASSWORD=testpassphrase
printf 'hunter2\n' | /usr/local/bin/gopass insert -f test/entry1
OP
chmod 755 /work/gp3-op.sh
run gopass \
  --state /work/gp3/.local/share/gopass/stores/root \
  --operation "/work/gp3-op.sh"

########## beets: スレッドの出所を切り分ける ##########
mkdir -p /work/bt/lib /work/bt/in1 /work/bt/in3
for n in 1 3; do
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
beet -c /work/bt/config.yaml import -q /work/bt/in1 > /dev/null 2>&1
echo "beets setup raw rc=$?"

# (a) 読むだけの操作でもスレッドが出るか → 出れば beets/Python 全体の話
echo "--- (a) beet ls（読むだけ）でスレッドが出るか ---"
run beets-ls \
  --state /work/bt/lib \
  --operation "$(command -v beet) -c /work/bt/config.yaml ls"

# (b) 書き込みだが import ではない操作
echo "--- (b) beet modify（書くが import ではない）---"
run beets-modify \
  --state /work/bt/lib \
  --operation "$(command -v beet) -c /work/bt/config.yaml modify -y -a album:Album1 comments=touched"

# (c) スレッドを実際に作っているのは誰か（strace で clone を数える）
echo "--- (c) import 中の clone/CLONE_THREAD を数える ---"
strace -f -e trace=clone,clone3 -o /work/out/beets-clone.txt \
  beet -c /work/bt/config.yaml import -q /work/bt/in3 > /dev/null 2>&1
echo "strace raw rc=$?"
echo "clone 行数: $(grep -c clone /work/out/beets-clone.txt 2>/dev/null)"
grep -m5 "CLONE_THREAD" /work/out/beets-clone.txt 2>/dev/null | cut -c1-160
