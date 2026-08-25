#!/bin/sh
# Launch the onboarding-clock driver against a running box (PROTOCOL.md).
# One run per run directory; a second attempt needs a fresh name.
#
#   docker build -f spike/onboarding-clock/Dockerfile -t sideeye-onboarding .
#   docker run -d --rm --network=none --name onboarding-box sideeye-onboarding
#   sh spike/onboarding-clock/run-clock.sh run2      # the next unused name
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RUN=${1:?usage: run-clock.sh <run name; the next unused one, e.g. run2>}
RESULTS="$SCRIPT_DIR/runs/$RUN"

# The permission scope this launcher declares is only meaningful from a
# plain terminal. Launched from inside another Claude session (measured
# 2026-08-25), nothing refused the escape shapes the scope names, and the
# one denial that occurred names that session's auto-mode classifier — it
# blocked a legitimate in-box author command — so a nested launch measures
# the wrong regime entirely and is refused before it creates anything.
[ -n "${CLAUDECODE+x}" ] && {
    echo "refusing to launch from inside a Claude session: the declared allowlist" >&2
    echo "did not gate there when measured (PROTOCOL.md Amendments 2026-08-25)." >&2
    echo "Run from a plain terminal." >&2
    exit 1
}

mkdir -p "$RESULTS"

command -v claude >/dev/null || { echo "claude CLI not found" >&2; exit 1; }
# One run per name, keyed on whatever survives a clone. Keying on the
# transcript could not hold: it is gitignored, so on any fresh checkout the
# guard passed for a name whose committed meta.json and timeline.tsv were
# sitting right there, and `mkdir -p` above would have sent the new run into
# that directory to overwrite them.
[ -n "$(ls -A "$RESULTS" 2>/dev/null)" ] && { echo "$RESULTS already holds a run; one run per name" >&2; exit 1; }

# The extractor checks itself before anything burns a box: a predicate
# regression stops the launch, not the adjudication three files later.
python3 "$SCRIPT_DIR/clock-audit.py" --selftest >/dev/null \
    || { echo "clock-audit.py --selftest failed; fix the instrument before running" >&2; exit 1; }

# The box's isolation is checked before the run, not assumed after it.
[ "$(docker inspect -f '{{.State.Running}}' onboarding-box 2>/dev/null)" = "true" ] \
    || { echo "onboarding-box is not running" >&2; exit 1; }
[ "$(docker inspect -f '{{.HostConfig.NetworkMode}}' onboarding-box)" = "none" ] \
    || { echo "onboarding-box is not network-off; the protocol requires --network=none" >&2; exit 1; }

CLI_VERSION=$(claude --version 2>&1 | head -1)

# The target's installed version, read from the box before the clock starts
# (PROTOCOL.md deviation 2 promised it recorded; the extractor stores the
# first line as meta.target_version). No pipe: a pipe would hand back the
# tail command's exit code and turn a dead box into an empty string.
TARGET_VERSION=$(docker exec onboarding-box jrnl --version 2>&1) \
    || { echo "could not read the target's version from the box" >&2; exit 1; }

# Canary: safe mode must authenticate before the run burns the box.
canary_out=$(claude --safe-mode -p "Reply with exactly: ok" < /dev/null 2>"$RESULTS/canary-stderr.log") \
    || { echo "canary failed — see $RESULTS/canary-stderr.log" >&2; exit 1; }
case "$canary_out" in
    *ok*) echo "canary: safe mode authenticates" ;;
    *) echo "canary returned unexpected output: $canary_out" >&2; exit 1 ;;
esac

PROMPT="$SCRIPT_DIR/prompt.md"
PROMPT_SHA=$(shasum -a 256 "$PROMPT" | cut -d' ' -f1)
# Kept in step with clock-audit.py's denied set by hand (the loop-closure shape).
# Bash is scoped to the box (PROTOCOL.md Amendments 2026-08-25). The docs say
# this pattern refuses a non-box command before it runs — unprobed, and only
# meaningful from the plain terminal the nested-session guard above enforces.
# The audit keeps its own independent read of the transcript either way.
ALLOWED="Bash(docker exec onboarding-box *),Read,Edit,Write,Glob,Grep"
DISALLOWED="WebFetch,WebSearch,Task,Agent,Workflow,SendMessage,PushNotification,RemoteTrigger,ScheduleWakeup,CronCreate,CronDelete"

# An empty cwd: the driver has nothing on the host worth reading, and the audit
# still checks it read nothing anyway.
WORKDIR=$(mktemp -d "$HOME/onboarding-clock-XXXXXX")

echo "=== the run: one driver, one box, the transcript records everything ==="
agent_rc=0
( cd "$WORKDIR" && claude --safe-mode -p "$(cat "$PROMPT")" \
    --allowedTools "$ALLOWED" \
    --disallowedTools "$DISALLOWED" \
    --output-format stream-json --verbose \
    < /dev/null \
    > "$RESULTS/transcript.jsonl" 2> "$RESULTS/agent-stderr.log" ) || agent_rc=$?
echo "driver exited: $agent_rc"

# The scratch is actually removed. Run 1's `rmdir || true` failed silently
# the moment the driver wrote a file, and left its scratch on the host; the
# contents are already recorded in the transcript's Write events, so nothing
# is lost — but the names are echoed first so the run log says what existed.
leftovers=$(ls -A "$WORKDIR" 2>/dev/null || true)
[ -n "$leftovers" ] && echo "driver scratch held files (recorded above, removed now): $leftovers"
if command -v trash >/dev/null 2>&1; then
    trash "$WORKDIR" || rm -rf -- "$WORKDIR"
else
    rm -rf -- "$WORKDIR"
fi

REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
python3 "$SCRIPT_DIR/clock-audit.py" \
    "$RESULTS/transcript.jsonl" "$RESULTS" "$CLI_VERSION" "$PROMPT_SHA" "$agent_rc" "$REPO_ROOT" "$TARGET_VERSION"

echo ""
echo "next: read $RESULTS/meta.json and adjudicate every flagged command against"
echo "      PROTOCOL.md (run 1's precedent: transfer of driver-authored files into"
echo "      the box is inside the seal; anything else voids), pick the qualifying"
echo "      stop candidate, and write RESULTS.md with the derived wall-clock"
