#!/bin/sh
# Usage: set-order.sh <engine dir> <label> [runs, default 30]
E=$1; L=$2
SIDEEYE=$E/bin/sideeye
SHIM=$E/lib/libsideeye_shim.so
R=/tmp/set30; mkdir -p $R
cat > $R/toy.py <<'PY'
import sys, os
state = sys.argv[1]
for n in {"alpha", "beta"}:
    with open(os.path.join(state, n), "w") as f:
        f.write("x\n")
PY
cat > $R/setup.sh <<'SH'
#!/bin/sh
printf 'ok\n' > "$1/marker"
SH
cat > $R/check.sh <<'SH'
#!/bin/sh
S="$1"
[ "$(cat "$S/marker" 2>/dev/null)" = ok ] || { echo "marker corrupted" >&2; exit 1; }
if [ -e "$S/alpha" ] && [ ! -e "$S/beta" ]; then echo "alpha without beta" >&2; exit 1; fi
exit 0
SH
chmod +x $R/setup.sh $R/check.sh
for i in $(seq 1 "${3:-30}"); do
  S=$R/state-$L-$i; W=$R/work-$L-$i; mkdir -p "$S"
  $SIDEEYE explore --state "$S" --setup "$R/setup.sh $S" --operation "/usr/bin/python3 $R/toy.py $S" --check "$R/check.sh $S" \
    --oracle /usr/bin/strace --shim "$SHIM" --work "$W" --json $R/r-$L-$i.json > $R/t-$L-$i.txt 2>&1
  rc=$?
  v=$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r.get("verdict"), r.get("unknown_reason") or "")' $R/r-$L-$i.json 2>/dev/null)
  rec=$($E/bin/trace-ops $W/trace-record.bin 2>/dev/null | awk '$1=="open"{sub(".*/","",$2); printf "%s ", $2}')
  worlds=""
  for t in $W/trace-[0-9]*.bin; do
    [ -e "$t" ] || continue
    worlds="$worlds[$($E/bin/trace-ops $t 2>/dev/null | awk '$1=="open"{sub(".*/","",$2); printf "%s ", $2}')]"
  done
  echo "$L run $i rc=$rc $v | recording: $rec| worlds: $worlds"
done
