#!/bin/sh
# 第4ラウンド:
#  - gopass を sh で包まずに直接 operation にする（環境は engine 側から渡す）
#  - beets のスレッドが Python 自体か beets かを切り分ける
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

########## gopass: sh を挟まず直接。環境は engine が持っている ##########
# GOPASS_HOMEDIR と GOPASS_AGE_PASSWORD は docker run -e で engine のプロセスに入っている。
# scouting.md の「operation の子は engine の環境を継ぐ。setup script の export ではない」に従う。
echo "engine が持っている環境: GOPASS_HOMEDIR=${GOPASS_HOMEDIR:-未設定}"
mkdir -p "$GOPASS_HOMEDIR"
gopass --yes setup --crypto age --storage fs --name tester --email tester@example.com \
  > "$OUT/gopass4-setup.txt" 2>&1
echo "gopass setup raw rc=$?"
printf 'first\n' | gopass insert -f seed/entry0 > /dev/null 2>&1
echo "seed insert raw rc=$?"

# insert は stdin を読む。engine は stdin を EOF にするので、stdin を使わない書き込みを選ぶ
# gopass generate は自分で値を作るので stdin が要らない
run gopass-direct \
  --state "$GOPASS_HOMEDIR/.local/share/gopass/stores/root" \
  --operation "/usr/local/bin/gopass generate --print=false test/generated 20"

echo "--- oracle 付きでも測る（プロセス境界の説明を得るため）---"
"$SE" preflight --state "$GOPASS_HOMEDIR/.local/share/gopass/stores/root" \
  --operation "/usr/local/bin/gopass generate --print=false test/generated2 20" \
  --shim "$SHIM" --oracle /usr/bin/strace > "$OUT/gopass-oracle.txt" 2>&1
echo "gopass+oracle raw rc=$?"
head -5 "$OUT/gopass-oracle.txt"

########## beets: スレッドは Python 自体か beets か ##########
echo
echo "--- 素の python3（何もしない）でスレッドが出るか ---"
mkdir -p /work/py
cat > /work/py/noop.py <<'PY'
open("/work/py/state/out.txt", "w").write("hello\n")
PY
mkdir -p /work/py/state
run python-noop \
  --state /work/py/state \
  --operation "/usr/bin/python3 /work/py/noop.py"

echo "--- beets を import しただけの python3 ---"
cat > /work/py/withbeets.py <<'PY'
import beets  # noqa
open("/work/py/state2/out.txt", "w").write("hello\n")
PY
mkdir -p /work/py/state2
run python-import-beets \
  --state /work/py/state2 \
  --operation "/usr/bin/python3 /work/py/withbeets.py"
