#!/bin/bash
# 測定1: fs_usage は高負荷で行を落とすか。
#
# 【yotta の端末で走らせるもの】sudo の資格キャッシュは端末ごとなので、
# Claude の非対話シェルからは fs_usage を起動できない。
#
#   bash /Users/i.yoshida/sideeye-attest-Q6LHdV/measure1.sh
#
# 最初に一度だけパスワードを聞かれる（そのあとはキャッシュで通る）。
#
# 孤児化対策: fs_usage は -t で自分に実行上限を持たせる。親が死んでも
# kdebug を掴んだまま残らない（残ると以後 fs_usage / latency / sc_usage が
# 二度と初期化できなくなる）。終了時に pkill -x でも念のため落とす。
set -u
BASE="$(cd "$(dirname "$0")" && pwd)"
RUNS="$BASE/runs"; mkdir -p "$RUNS"
SIDEEYE=/opt/homebrew/bin/sideeye
FSU_LIMIT=25

sudo -v || { echo "APPARATUS FAIL: sudo が使えない。何も測っていない。"; exit 1; }

cleanup() { sudo -n pkill -x fs_usage 2>/dev/null; }
trap cleanup EXIT

printf '%s\n' "N|shim_ops|kernel_writes_on_state_fd|capture_lines|state_bytes|verdict"

for N in 10 100 1000 10000; do
    d="$BASE/state/drop-$N"; mkdir -p "$d"
    cap="$RUNS/drop-$N.capture"
    out="$RUNS/drop-$N.txt"

    sudo -n /usr/bin/fs_usage -w -t "$FSU_LIMIT" -f filesys loadprobe > "$cap" 2>/dev/null &
    sleep 2   # アタッチ待ち。握手が無いので固定待ち

    { echo "=== loadprobe N=$N (fs_usage 併走) ==="; echo "--- output ---"; } > "$out"
    PROBE_STATE="$d" "$SIDEEYE" preflight --state "$d" --operation "$BASE/loadprobe $N" >> "$out" 2>&1
    echo "--- exit=$? ---" >> "$out"

    sleep 1
    sudo -n pkill -x fs_usage 2>/dev/null
    sleep 1

    shim=$(grep -oE 'accepted — [0-9]+ state-changing' "$out" | grep -oE '[0-9]+')
    lines=$(wc -l < "$cap" | tr -d ' ')
    bytes=$(wc -c < "$d/load" 2>/dev/null | tr -d ' ')

    kw=$(python3 "$BASE/count_writes.py" "$cap" "$d/load")

    verdict="?"
    if [ "${shim:-0}" -ne $((N+1)) ] || [ "${bytes:-0}" -ne "$N" ]; then
        verdict="APPARATUS(shim=${shim:--} bytes=${bytes:--} 期待 shim=$((N+1)) bytes=$N)"
    elif [ "$lines" -eq 0 ]; then
        verdict="APPARATUS(capture が空。アタッチできていない)"
    elif [ "$kw" -eq "$N" ]; then
        verdict="一致"
    elif [ "$kw" -lt "$N" ]; then
        verdict="取りこぼし $((N - kw)) 行"
    else
        verdict="超過 $((kw - N)) 行（要調査）"
    fi
    printf '%s|%s|%s|%s|%s|%s\n' "$N" "${shim:--}" "$kw" "$lines" "${bytes:--}" "$verdict"
done

echo
echo "生の capture: $RUNS/drop-*.capture"
echo "残っている fs_usage: $(pgrep -x fs_usage | wc -l | tr -d ' ') 個（0 であること）"
