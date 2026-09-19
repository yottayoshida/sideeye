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
TARGET=${1:?usage: run-authoring.sh <target-package> [run-name]}
# A second run of the same target is a second directory, and this is how it gets one. Without
# it the only way past the "already exists" refusal is to move published evidence, which is the
# temptation this study exists to remove — and `runs/dos2unix/` is already taken by a void run.
RUN_NAME=${2:-$TARGET}
# A run name becomes a path under runs/, so it is held to one component of ordinary characters.
# `..` in it writes outside the directory the study publishes from.
case "$RUN_NAME" in
    */*|*..*|"") echo "run-authoring: run name must be a single plain directory name" >&2; exit 1 ;;
esac
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
[ -d "$here/runs/$RUN_NAME" ] && { echo "run-authoring: runs/$RUN_NAME already exists; pass a run name as the second argument for a second run" >&2; exit 1; }

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
out="$here/runs/$RUN_NAME"
mkdir -p "$out/revisions"

echo "building the box for $TARGET (the build has the network; the run does not)"
build_args=$(engine_build_args) || { echo "run-authoring: could not read the engine pin from engine-pins.tsv" >&2; exit 1; }
image=$(docker build -q -f "$here/Dockerfile" $build_args --build-arg "TARGET=$TARGET" "$root")
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
# The raw transcript is written OUTSIDE the published directory. It is the un-normalised
# file — host paths, and any string shaped like a credential, verbatim — and it used to be
# written into runs/<name>/ and deleted at the end. A session that dies in the middle (or a
# launcher that does) leaves it there, inside the directory the next `git add` sweeps. The
# deletion was never the safeguard; the location was wrong.
raw=$(mktemp)
# The session's stderr is the same case and was left behind when the transcript moved: it is
# written for the whole run and normalised only after the run completes, so a session that dies
# in the middle leaves an un-normalised file inside the published directory. Same fix, because
# it was the same defect — the argument for moving one of them never applied to only one.
raw_err=$(mktemp)
# In an empty directory, NOT the repository. PROTOCOL.md says the public documentation cannot be
# kept from the subject — an API client cannot be network-isolated — but a local checkout can,
# and this one holds `cards/`: the answer key the run is graded against. What cannot be enforced
# is declared; what can be, is.
workdir=$(mktemp -d)
set +e
( cd "$workdir" && claude --safe-mode -p "$(cat "$prompt")" \
    --output-format stream-json --verbose < /dev/null ) > "$raw" 2> "$raw_err"
rc=$?
set -e
rmdir "$workdir" 2>/dev/null || true
ended=$(date -u +%Y-%m-%dT%H:%M:%SZ)
rm -f "$prompt"

# The evidence the box holds, before it is torn down.
docker cp "$BOX_NAME:/home/user/revisions/." "$out/revisions/" 2>/dev/null || true

# Normalisation, per PROTOCOL.md: the home directory becomes ~, and anything that looks like a
# credential is removed before the file is written. The raw files are NOT committed.
#
# Both published files go through ONE invocation. They used to have a redaction list each, in
# two heredocs, and the lists drifted the first time one of them was extended: the
# target-generated password shape was added to the transcript's copy and not to stderr's, so a
# password printed to stderr would have shipped. The same judgement in two places is the shape
# where one of them lies.
python3 - "$raw" "$out/transcript.jsonl" "$HOME" "$root" "$out/normalisation.txt" "$raw_err" "$out/session-stderr.log" <<'PY'
import json, re, sys
from pathlib import Path

src, dst, home, repo, report, err_src, err_dst = sys.argv[1:8]
# `sk-[A-Za-z0-9]{20,}` does not match a real Anthropic key: `sk-ant-api03-…` carries dashes,
# so the class stops at `sk-ant`. Measured on a sample of that shape before this was widened.
SECRET = re.compile(
    r"(sk-ant-[A-Za-z0-9_-]{16,}|sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{36,}|gho_[A-Za-z0-9]{36,}"
    r"|glpat-[A-Za-z0-9_-]{20,}|xox[bp]-[A-Za-z0-9-]{10,}|Bearer\s+[A-Za-z0-9._-]+"
    r"|ANTHROPIC_API_KEY=\S+)"
)
# A password the TARGET generated and printed. `fossil init` announces one — `admin-user: tester
# (initial password is "…")` — and the run 2026-09-19 published it before this existed: the list
# above is a list of *vendors'* token shapes, and nothing in it is about a target inventing a
# credential in the box. It grants nothing (the container is destroyed) but it is a password in a
# public repository, so it goes. Only the VALUE is replaced; `password is` stays, and the target's
# own documentation — `fossil user password ${USER} ${PWD}` — is untouched, because that is the
# manual the subject was told to read and therefore evidence.
#
# Its limits, since a redaction that overreaches is also a change to the evidence: it fires on
# any token of six or more characters starting alphanumeric after `password is`, so prose like
# "a password is required" is redacted while "the password is 12345" is not (both measured),
# and it does NOT catch `Password:` or `password=`. It is deliberately one phrase rather than a guess
# at every shape — the scan before committing is what finds the next one, and that scan is the
# thing that found this one.
GENERATED_PASSWORD = re.compile(r"""(password is\s+[\\"']*)([A-Za-z0-9][A-Za-z0-9._+/=-]{5,})""")
# The home path is rewritten AT A BOUNDARY: a bare replace turns /Users/abc/x into ~c/x when
# home is /Users/ab. spike/onboarding-clock/clock-audit.py records that measurement.
HOME_AT_BOUNDARY = re.compile(re.escape(home) + r"(?=/|\b|$)")


def scrub(text):
    """Every rule, in one place, applied to everything this study publishes."""
    text = SECRET.sub("[redacted]", HOME_AT_BOUNDARY.sub("~", text))
    return GENERATED_PASSWORD.sub(r"\1[redacted]", text)


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
        out.append({"ts": obj.get("timestamp") or obj.get("ts") or "", "text": scrub(raw)})

with open(dst, "w", encoding="utf-8") as fh:
    for obj in out:
        fh.write(json.dumps(obj, ensure_ascii=False) + "\n")
Path(report).write_text(
    f"events\t{len(out)}\njson_lines_rejected\t{rejected}\n"
    f"repo_root_named_before_normalisation\t{repo_hits}\n",
    encoding="utf-8",
)
# The session's stderr is evidence too, through the same `scrub`. It is read from its tempfile
# and only the normalised text is ever written into the published directory.
err = Path(err_src)
Path(err_dst).write_text(
    scrub(err.read_text(encoding="utf-8", errors="replace")) if err.exists() else "",
    encoding="utf-8",
)
print(f"normalised {len(out)} event(s); rejected {rejected}; repo root named {repo_hits} time(s)")
PY
rm -f "$raw" "$raw_err"

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
