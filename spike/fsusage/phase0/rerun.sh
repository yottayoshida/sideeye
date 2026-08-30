#!/bin/bash
# 初回で「装置のミス」と判明した2本を直して再測定する。
# 1回目の失敗理由:
#   git-apple: state が git repo でなかった（git init を書いていなかった）→ recording_run_failed
#   abook:     ldif に objectclass/sn が無く abook が入力を拒否 → recording_run_failed
# どちらも sideeye の壁ではなく、こちらの段取りミス。
#
# state は削除しない（omamori が rm -rf を止め、trash も AppleScript で失敗するため）。
# 代わりに連番の新しいディレクトリを使う。
set -u
BASE="$(cd "$(dirname "$0")" && pwd)"
RUNS="$BASE/runs"; mkdir -p "$RUNS"
SIDEEYE=/opt/homebrew/bin/sideeye
GEN=2

emit() {
    local name="$1" role="$2" out="$3" rc="$4"
    local wall; wall=$(grep -oE '^UNKNOWN  [a-z_]+' "$out" | head -1 | awk '{print $2}')
    [ -z "$wall" ] && wall="-"
    local reached="no"; grep -q 'recording accepted' "$out" && reached="yes"
    printf '%s|%s|%s|%s|%s\n' "$name" "$role" "$rc" "$reached" "$wall"
}

echo "name|role|exit|reached|wall"

# --- git-apple: 対照。repo を先に作ってから測る（peer と同じ形） ---
GITDIR="$BASE/state/git-apple-g$GEN"
mkdir -p "$GITDIR"
GIT=/Library/Developer/CommandLineTools/usr/bin/git
"$GIT" init -q "$GITDIR" 2>&1 | head -2
export GIT_AUTHOR_NAME=probe GIT_AUTHOR_EMAIL=probe@example.invalid
export GIT_COMMITTER_NAME=probe GIT_COMMITTER_EMAIL=probe@example.invalid
# 前提を先に確認: repo として成立していること
"$GIT" -C "$GITDIR" rev-parse --git-dir >/dev/null 2>&1 || { echo "APPARATUS FAIL: git repo not created"; exit 1; }
out="$RUNS/git-apple-g$GEN.txt"
{ echo "=== git-apple gen$GEN (role=control-wall) ==="
  echo "operation: $GIT -C $GITDIR commit --allow-empty -m dogfood"
  echo "setup: git init was run before preflight; rev-parse confirmed"
  echo "--- output ---"; } > "$out"
"$SIDEEYE" preflight --state "$GITDIR" --operation "$GIT -C $GITDIR commit --allow-empty -m dogfood" >> "$out" 2>&1
rc=$?; echo "--- exit=$rc ---" >> "$out"
emit git-apple control-wall "$out" "$rc"

# --- abook: subject。ldif を正した形（直接実行で rc=0 を確認済み） ---
ABDIR="$BASE/state/abook-g$GEN"
mkdir -p "$ABDIR"
# 前提を先に確認: 同じ操作が素で通ること
/opt/homebrew/bin/abook --convert --informat ldif --infile "$BASE/in2.ldif" \
    --outformat abook --outfile "$BASE/probe-abook/precheck" >/dev/null 2>&1 \
    || { echo "APPARATUS FAIL: abook conversion does not work bare"; exit 1; }
out="$RUNS/abook-g$GEN.txt"
{ echo "=== abook gen$GEN (role=subject) ==="
  echo "operation: abook --convert --informat ldif --infile $BASE/in2.ldif --outformat abook --outfile $ABDIR/out"
  echo "precheck: same conversion succeeds bare (rc=0)"
  echo "--- output ---"; } > "$out"
"$SIDEEYE" preflight --state "$ABDIR" \
    --operation "/opt/homebrew/bin/abook --convert --informat ldif --infile $BASE/in2.ldif --outformat abook --outfile $ABDIR/out" >> "$out" 2>&1
rc=$?; echo "--- exit=$rc ---" >> "$out"
emit abook subject "$out" "$rc"
