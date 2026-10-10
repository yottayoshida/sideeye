#!/bin/sh
# Host side: each target in a box of its own (run.sh), then the reader over every refused run's
# capture, then transcripts/order.tsv from the per-run readings. The run of 2026-10-10 was:
#
#   sh apparatus/measure.sh ctl-ordered ctl-condvar jj tofu doctl codex notesmd
#   docker run --rm --privileged --cgroupns=private --network none -e OUT_NAME=doctl-30 \
#       -v "$PWD/apparatus":/ap:ro -v "$PWD/transcripts":/out sideeye-to-1010 sh /ap/run.sh doctl 30
#   sh apparatus/measure.sh --summarise          (reads doctl-30 too)
#
# The second doctl run — 35 attempts, 30 of them refused — was taken after the first five refusals
# showed one `all-ordered` run, to count how often that happens. Captures not kept in the repository were read where they lay
# (RESULTS.md); a reading is kept as order-<n>.json either way, and the summary is built from those.
here="$(cd "$(dirname "$0")" && pwd)"; run="$(dirname "$here")"; tr="$run/transcripts"
mkdir -p "$tr"
if [ "${1:-}" != "--summarise" ]; then
  for t in "$@"; do
    echo "=== $t $(date -u +%FT%TZ)"
    docker run --rm --privileged --cgroupns=private --network none -v "$here":/ap:ro -v "$tr":/out sideeye-to-1010 sh /ap/run.sh "$t"
  done
fi
for d in "$tr"/*/; do
  t=$(basename "$d"); def=${t%-30}
  state=$(sed -n 's/^state *= *"\(.*\)"/\1/p' "$here/defines/$def/sideeye.toml" 2>/dev/null)
  [ -n "$state" ] || continue
  for c in "$d"oracle-*.txt; do
    [ -f "$c" ] || continue
    n=${c##*/oracle-}; n=${n%.txt}
    python3 -I "$here/order.py" "$c" "$state" > "$d/order-$n.json"
  done
done
python3 -I - "$tr" <<'PY'
import json, os, re, sys
T = sys.argv[1]
with open(os.path.join(T, "order.tsv"), "w") as o:
    o.write("target\tattempt\tverdict\twrites\thandovers\tby_creation\tby_exit\tunordered\tcapture_kept\n")
    for t in sorted(os.listdir(T)):
        d = os.path.join(T, t)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d), key=lambda s: int(re.sub(r"\D", "", s) or 0)):
            m = re.fullmatch(r"order-(\d+)\.json", f)
            if not m:
                continue
            j = json.load(open(os.path.join(d, f)))
            kept = "yes" if os.path.exists(os.path.join(d, f"oracle-{m.group(1)}.txt")) else "no"
            o.write("\t".join([t, m.group(1), j["verdict"]] + [str(j[k]) for k in ("writes", "handovers", "ordered_by_creation", "ordered_by_exit", "unordered")] + [kept]) + "\n")
PY
cat "$tr/order.tsv"
