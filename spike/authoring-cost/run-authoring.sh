#!/bin/sh
# One authoring run, from the sealed manifest to a published record (#618, ADR 0077).
#
#   sh spike/authoring-cost/run-authoring.sh <target-package>
#
# It builds the image, creates the box through box.sh, runs one `claude --safe-mode -p` session
# against prompt.md with the target's name substituted, and copies the evidence out:
#
#   runs/<target>/meta.json          what ran, under which manifest, with which versions
#   runs/<target>/transcript.jsonl   normalised (see PROTOCOL.md, "Evidence")
#   runs/<target>/revisions/         the watcher's snapshots and its index
#
# It refuses before spending a session when the seal is not intact, when a card for the target is
# missing, or when the target is not the one the selection names. Grading is not done here: it
# happens after, from the committed evidence, so that a re-grade never re-runs a subject.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
TARGET=${1:?usage: run-authoring.sh <target-package>}
BOX_NAME=${BOX_NAME:-authoring-box}

# A session started against a broken seal cannot be graded honestly afterwards, so this is the
# first thing and not the last.
sh "$here/check-sealed.sh" >/dev/null || { echo "run-authoring: the seal is not intact; nothing was run" >&2; exit 1; }
[ -f "$here/cards/$TARGET.md" ] || { echo "run-authoring: no sealed card for $TARGET" >&2; exit 1; }
# The package is selection.tsv's SECOND column (shape, package, rank, why). Matching it as the
# first one refused every target, including the four that are selected — measured: the launcher
# could not have run at all.
awk -F'\t' -v t="$TARGET" '$1 !~ /^#/ && $2 == t { found = 1 } END { exit !found }' "$here/selection.tsv" ||
    { echo "run-authoring: $TARGET is not in selection.tsv" >&2; exit 1; }
[ -d "$here/runs/$TARGET" ] && { echo "run-authoring: runs/$TARGET already exists; a second run is a second directory" >&2; exit 1; }

command -v claude >/dev/null || { echo "run-authoring: claude CLI not found" >&2; exit 1; }
# The engine pin, read from the one file that owns it (spike/unknown-rate/engine-pins.tsv, the
# `g3` row). Passing it to the build keeps a second copy of the digest out of the Dockerfile,
# where it would go stale in silence the first time the pin moved.
engine_build_args() {
    row=$(grep -v '^#' "$root/spike/unknown-rate/engine-pins.tsv" | awk -F'\t' '$1 == "g3" {print; exit}')
    [ -n "$row" ] || { echo "no g3 row in engine-pins.tsv" >&2; return 1; }
    printf -- '--build-arg ENGINE_TAG=%s --build-arg ENGINE_ASSET=%s --build-arg ENGINE_SHA256=%s' \
        "$(printf '%s' "$row" | cut -f2)" "$(printf '%s' "$row" | cut -f3)" "$(printf '%s' "$row" | cut -f4)"
}

command -v docker >/dev/null || { echo "run-authoring: docker not found" >&2; exit 1; }

manifest=$(grep -v '^\(#\|$\)' "$here/ledger.md" | tail -1 | cut -f1)
out="$here/runs/$TARGET"
mkdir -p "$out/revisions"

echo "building the box for $TARGET (the build has the network; the run does not)"
image=$(docker build -q -f "$here/Dockerfile" $(engine_build_args) --build-arg "TARGET=$TARGET" "$root")
# NOT piped into `tee`: a pipeline's status is the last command's, so box.sh's refusal to
# inherit an existing container would have been swallowed and the run would have gone on to
# `docker exec` the very box it refused (#383's shape, one layer up).
BOX_NAME="$BOX_NAME" sh "$here/box.sh" "$image" > "$out/box.txt" || {
    echo "run-authoring: box.sh refused; nothing was run" >&2
    cat "$out/box.txt" >&2
    exit 1
}
cat "$out/box.txt"

target_version=$(docker exec "$BOX_NAME" sh -c "dpkg-query -W -f='\${Version}' $TARGET" 2>/dev/null || echo unknown)
cli_version=$(claude --version 2>&1 | head -1)

prompt=$(mktemp)
sed -e "s/TARGET_NAME/$TARGET/g" -e "s/authoring-box/$BOX_NAME/g" "$here/prompt.md" > "$prompt"

started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "running one session; its transcript is the clock"
# In an empty directory, NOT the repository. PROTOCOL.md says the public documentation cannot be
# kept from the subject — an API client cannot be network-isolated — but a local checkout can,
# and this one holds `cards/`: the answer key the run is graded against. What cannot be enforced
# is declared; what can be, is.
workdir=$(mktemp -d)
set +e
( cd "$workdir" && claude --safe-mode -p "$(cat "$prompt")" \
    --output-format stream-json --verbose < /dev/null ) > "$out/raw-transcript.jsonl" 2> "$out/session-stderr.log"
rc=$?
set -e
rmdir "$workdir" 2>/dev/null || true
ended=$(date -u +%Y-%m-%dT%H:%M:%SZ)
rm -f "$prompt"

# The evidence the box holds, before it is torn down.
docker cp "$BOX_NAME:/home/user/revisions/." "$out/revisions/" 2>/dev/null || true

# Normalisation, per PROTOCOL.md: the home directory becomes ~, and anything that looks like a
# credential is removed before the file is written. The raw file is NOT committed.
python3 - "$out/raw-transcript.jsonl" "$out/transcript.jsonl" "$HOME" "$root" "$out/normalisation.txt" <<'PY'
import json, re, sys
from pathlib import Path

src, dst, home, repo, report = sys.argv[1:6]
# `sk-[A-Za-z0-9]{20,}` does not match a real Anthropic key: `sk-ant-api03-…` carries dashes,
# so the class stops at `sk-ant`. Measured on a sample of that shape before this was widened.
SECRET = re.compile(
    r"(sk-ant-[A-Za-z0-9_-]{16,}|sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{36,}|gho_[A-Za-z0-9]{36,}"
    r"|glpat-[A-Za-z0-9_-]{20,}|xox[bp]-[A-Za-z0-9-]{10,}|Bearer\s+[A-Za-z0-9._-]+"
    r"|ANTHROPIC_API_KEY=\S+)"
)
# The home path is rewritten AT A BOUNDARY: a bare replace turns /Users/abc/x into ~c/x when
# home is /Users/ab. spike/onboarding-clock/clock-audit.py records that measurement.
HOME_AT_BOUNDARY = re.compile(re.escape(home) + r"(?=/|\b|$)")

out, rejected, repo_hits = [], 0, 0
with open(src, encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            # Counted, not silently dropped: "rejected: 0" is a measurement; a silent skip is
            # a gap that every later figure inherits.
            rejected += 1
            continue
        raw = json.dumps(obj, ensure_ascii=False)
        # Detection runs on the RAW text and normalisation after it. The repository root lives
        # under the home directory, so normalising first deletes the very string the
        # repository-trace check looks for (clock-audit.py's ordering lesson).
        if repo in raw:
            repo_hits += 1
        text = SECRET.sub("[redacted]", HOME_AT_BOUNDARY.sub("~", raw))
        out.append({"ts": obj.get("timestamp") or obj.get("ts") or "", "text": text})

with open(dst, "w", encoding="utf-8") as fh:
    for obj in out:
        fh.write(json.dumps(obj, ensure_ascii=False) + "\n")
Path(report).write_text(
    f"events\t{len(out)}\njson_lines_rejected\t{rejected}\n"
    f"repo_root_named_before_normalisation\t{repo_hits}\n",
    encoding="utf-8",
)
print(f"normalised {len(out)} event(s); rejected {rejected}; repo root named {repo_hits} time(s)")
PY
rm -f "$out/raw-transcript.jsonl"

# The session's stderr is evidence too, and it was being published raw — host paths and
# anything the CLI printed. Same treatment, or it does not ship.
python3 - "$out/session-stderr.log" "$HOME" <<'PY2'
import re, sys
from pathlib import Path
path, home = Path(sys.argv[1]), sys.argv[2]
if path.exists():
    SECRET = re.compile(
        r"(sk-ant-[A-Za-z0-9_-]{16,}|sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{36,}|gho_[A-Za-z0-9]{36,}"
        r"|glpat-[A-Za-z0-9_-]{20,}|xox[bp]-[A-Za-z0-9-]{10,}|Bearer\s+[A-Za-z0-9._-]+"
        r"|ANTHROPIC_API_KEY=\S+)"
    )
    text = re.sub(re.escape(home) + r"(?=/|\b|$)", "~", path.read_text(encoding="utf-8", errors="replace"))
    path.write_text(SECRET.sub("[redacted]", text), encoding="utf-8")
PY2

# The subject's model, read from the session's own opening event: the protocol records the
# graders' models, and the subject's is the larger variable of the two.
subject_model=$(sed -n 's/.*\\"model\\":[[:space:]]*\\"\([^\\]*\)\\".*/\1/p' "$out/transcript.jsonl" | head -1)
[ -n "$subject_model" ] || subject_model=unknown

cat > "$out/meta.json" <<EOF
{
  "target": "$TARGET",
  "manifest": "$manifest",
  "started": "$started",
  "ended": "$ended",
  "session_exit": $rc,
  "target_version": "$target_version",
  "claude_cli": "$cli_version",
  "subject_model": "$subject_model",
  "image": "$image",
  "disposition": "pending",
  "graders": []
}
EOF

docker rm -f "$BOX_NAME" >/dev/null 2>&1 || true
echo "wrote $out"
python3 "$here/audit.py" "$out" || true
echo "next: read the audit's repository-trace list, write the disposition into meta.json, then grade."
