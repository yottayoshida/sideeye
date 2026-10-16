#!/bin/sh
# run-subject.sh <shape>: one authoring session for the shape's selected target (#873).
# Writes runs/<package>/: meta.json, transcript.jsonl, session-stderr.log, normalisation.txt,
# revisions/ (the watcher's), final/ (the define directory as the session left it), box.txt.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
SHAPE=${1:?usage: run-subject.sh <shape 1|2|3>}
BOX_NAME=${BOX_NAME:-authoring-box}

sh "$here/check-sealed.sh" > /dev/null || { echo "run-subject: the seal is not intact; nothing was run" >&2; exit 1; }
row=$(awk -F'\t' -v s="$SHAPE" '$1 == s' "$here/selection.tsv")
[ -n "$row" ] || { echo "run-subject: no selected target for shape $SHAPE" >&2; exit 1; }
pkg=$(printf '%s' "$row" | cut -f2); name=${pkg%%=*}; version=${pkg#*=}
target=$(printf '%s' "$row" | cut -f3); operation=$(printf '%s' "$row" | cut -f4); shape_text=$(printf '%s' "$row" | cut -f5)
out="$here/runs/$name"
[ -e "$out" ] && { echo "run-subject: $out already exists" >&2; exit 1; }
command -v claude > /dev/null && command -v docker > /dev/null || { echo "run-subject: claude and docker are needed" >&2; exit 1; }
seal=$(python3 -I "$here/tally.py" --seal-line)

image=$(sh "$here/apparatus/build.sh" "$pkg" | tail -1)
mkdir -p "$out/revisions" "$out/final"
BOX_NAME="$BOX_NAME" sh "$here/box.sh" "$image" > "$out/box.txt" || { cat "$out/box.txt" >&2; exit 1; }
target_version=$(docker exec "$BOX_NAME" cat /target-version.txt)

work=$(mktemp -d "$HOME/.cctmp/subject-XXXXXX")
prompt="$work/../$(basename "$work").prompt"
python3 -I - "$here/prompt.md" "$prompt" "$seal" "$BOX_NAME" "$target" "$version" "$operation" "$shape_text" <<'PY'
import sys
src, dst, seal, box, target, version, operation, shape = sys.argv[1:9]
text = open(src).read()
for k, v in (("SEAL_LINE", seal), ("BOX_NAME", box), ("TARGET_NAME", target), ("TARGET_VERSION", version), ("OPERATION", operation), ("CONTRACT_SHAPE", shape)):
    text = text.replace(k, v)
open(dst, "w").write(text)
PY
raw="$work.raw"; raw_err="$work.err"
cli_version=$(claude --version 2>&1 | head -1)
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
set +e
# In an empty directory outside every repository: no CLAUDE.md, no project memory, no checkout to read.
( cd "$work" && claude --safe-mode --permission-mode auto -p "$(cat "$prompt")" --output-format stream-json --verbose < /dev/null ) > "$raw" 2> "$raw_err"
rc=$?
set -e
ended=$(date -u +%Y-%m-%dT%H:%M:%SZ)

docker cp "$BOX_NAME:/home/user/revisions/." "$out/revisions/" 2> /dev/null || true
docker cp "$BOX_NAME:/home/user/authoring/define/." "$out/final/" 2> /dev/null || true
python3 -I "$here/normalise.py" "$raw" "$out/transcript.jsonl" "$HOME" "$root" "$out/normalisation.txt" "$raw_err" "$out/session-stderr.log"
subject_model=$(sed -n 's/.*\\"model\\":[[:space:]]*\\"\([^\\]*\)\\".*/\1/p' "$out/transcript.jsonl" | head -1)
python3 -I - "$out/meta.json" <<PY
import json, sys
json.dump({"target": "$name", "package": "$target_version", "seal": "$seal", "started": "$started", "ended": "$ended",
           "session_exit": $rc, "claude_cli": "$cli_version", "subject_model": "${subject_model:-unknown}",
           "image": "$image", "disposition": "pending"}, open(sys.argv[1], "w"), indent=2)
PY
docker rm -f "$BOX_NAME" > /dev/null 2>&1 || true
/usr/bin/trash "$work" "$prompt" "$raw" "$raw_err" 2> /dev/null || true
echo "wrote $out"
