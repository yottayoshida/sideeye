#!/bin/sh
# run-grader.sh <package> <1|2>: one grader for one run, writing runs/<package>/grades/g<n>.json
# and the grader's own normalised transcript beside it.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
name=${1:?usage: run-grader.sh <package> <1|2>}; n=${2:?}
run="$here/runs/$name"
sh "$here/check-sealed.sh" > /dev/null || { echo "run-grader: the seal is not intact" >&2; exit 1; }
[ -s "$run/transcript.jsonl" ] || { echo "run-grader: no transcript for $name" >&2; exit 1; }
mkdir -p "$run/grades"
[ -e "$run/grades/g$n.json" ] && { echo "run-grader: g$n.json exists" >&2; exit 1; }

work=$(mktemp -d "$HOME/.cctmp/grader-XXXXXX")
cp "$here/cards/$name.md" "$work/card.md"
cp "$here/rubric.md" "$here/vocabulary.txt" "$work/"
cp -R "$run/final" "$work/final"
cp -R "$run/revisions" "$work/revisions"
# The subject's prompt is left out: it names the contract shape the card grades, and a grader that
# reads the brief grades the brief.
python3 -I - "$run/transcript.jsonl" "$work/transcript.jsonl" <<'PY'
import json, sys
src, dst = sys.argv[1:3]
with open(src) as fh, open(dst, "w") as out:
    for line in fh:
        if "Your task: **write a semantic checker" not in json.loads(line)["text"]:
            out.write(line)
PY
seal=$(python3 -I "$here/tally.py" --seal-line)
target=$(awk -F'\t' -v p="$name" 'split($2, a, "=") && a[1] == p {print $3}' "$here/selection.tsv")
prompt=$(sed -e "s|SEAL_LINE|$seal|" -e "s|TARGET_NAME|$target|g" "$here/grader-prompt.md")
raw="$work.raw"
( cd "$work" && claude --safe-mode --permission-mode auto -p "$prompt" --output-format stream-json --verbose < /dev/null ) > "$raw" 2> "$work.err" || true
python3 -I "$here/normalise.py" "$raw" "$run/grades/g$n.transcript.jsonl" "$HOME" "$root" "$run/grades/g$n.normalisation.txt"
python3 -I - "$raw" "$run/grades/g$n.json" <<'PY'
import json, re, sys
result = ""
for line in open(sys.argv[1]):
    try:
        obj = json.loads(line)
    except ValueError:
        continue
    if obj.get("type") == "result":
        result = obj.get("result", "")
m = re.search(r"\{.*\}", result, re.S)
sheet = json.loads(m.group(0)) if m else {"unparsed": result}
json.dump(sheet, open(sys.argv[2], "w"), indent=2, ensure_ascii=False)
print("grader sheet:", "parsed" if m else "UNPARSED")
PY
/usr/bin/trash "$work" "$raw" "$work.err" 2> /dev/null || true
