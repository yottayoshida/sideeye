#!/bin/bash
# 測定3: macOS で判定まで到達できる対象の割合
# 生の出力を runs/ に全部残す。要約だけで判断しない。
set -u

BASE="$(cd "$(dirname "$0")" && pwd)"
RUNS="$BASE/runs"
mkdir -p "$RUNS"
SIDEEYE=/opt/homebrew/bin/sideeye

# name|role|env|setup-cmd|operation
# role: apparatus(到達必須) / control-wall(壁必須) / subject
run_one() {
    local name="$1" role="$2" op="$3"
    local state="$BASE/state/$name"
    rm -rf "$state"; mkdir -p "$state"
    local out="$RUNS/$name.txt"
    {
        echo "=== $name (role=$role) ==="
        echo "operation: $op"
        echo "state: $state"
        echo "--- output ---"
    } > "$out"
    # shellcheck disable=SC2086
    "$SIDEEYE" preflight --state "$state" --operation "$op" >> "$out" 2>&1
    local rc=$?
    echo "--- exit=$rc ---" >> "$out"
    # 壁の名前を出力から取る（無ければ '-'）
    local wall
    wall=$(grep -oE '^UNKNOWN  [a-z_]+' "$out" | head -1 | awk '{print $2}')
    [ -z "$wall" ] && wall="-"
    local reached="no"
    grep -q 'recording accepted' "$out" && reached="yes"
    printf '%s|%s|%s|%s|%s\n' "$name" "$role" "$rc" "$reached" "$wall"
}

echo "name|role|exit|reached|wall"

# --- 装置の陽性対照: 自作 toy。到達しなければ測定装置が壊れている ---
if [ -x "$BASE/toy" ]; then
    TOY_STATE="$BASE/state/toy" run_one toy apparatus "$BASE/toy rotate"
fi

# --- 対照: 既知の壁（peer 実測）---
GH_CONFIG_DIR="$BASE/state/gh" run_one gh control-wall "/opt/homebrew/bin/gh config set git_protocol ssh"
run_one git-apple control-wall "/Library/Developer/CommandLineTools/usr/bin/git -C $BASE/state/git-apple commit --allow-empty -m dogfood"

# --- subject: dogfood corpus ---
TIMEWARRIORDB="$BASE/state/timewarrior" run_one timewarrior subject "/opt/homebrew/bin/timew track 2020-01-02T10:00 - 2020-01-02T11:00 beta :yes"
run_one calcurse subject "/opt/homebrew/bin/calcurse -D $BASE/state/calcurse -N -t1"
run_one stow subject "/opt/homebrew/bin/stow -d $BASE/stow-src -t $BASE/state/stow pkg"
run_one abook subject "/opt/homebrew/bin/abook --datafile $BASE/state/abook/addressbook --convert --informat ldif --infile $BASE/in.ldif --outformat abook --outfile $BASE/state/abook/out"

# --- subject: 状態を持つ単一プロセス CLI ---
run_one sqlite3 subject "/opt/homebrew/opt/sqlite/bin/sqlite3 -init $BASE/init.sql $BASE/state/sqlite3/db.sqlite .quit"
run_one gnupg subject "/opt/homebrew/bin/gpg --homedir $BASE/state/gnupg --check-trustdb"
