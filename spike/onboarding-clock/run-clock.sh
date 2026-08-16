#!/bin/sh
# Launch the onboarding-clock driver against a running box (PROTOCOL.md).
# One run per run directory; a second attempt needs a fresh name.
#
#   docker build -f spike/onboarding-clock/Dockerfile -t sideeye-onboarding .
#   docker run -d --rm --network=none --name onboarding-box sideeye-onboarding
#   sh spike/onboarding-clock/run-clock.sh run1
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RUN=${1:?usage: run-clock.sh <run name, e.g. run1>}
RESULTS="$SCRIPT_DIR/runs/$RUN"
mkdir -p "$RESULTS"

command -v claude >/dev/null || { echo "claude CLI not found" >&2; exit 1; }
[ -e "$RESULTS/transcript.jsonl" ] && { echo "a transcript already exists in $RESULTS; one run per name" >&2; exit 1; }

# The box's isolation is checked before the run, not assumed after it.
[ "$(docker inspect -f '{{.State.Running}}' onboarding-box 2>/dev/null)" = "true" ] \
    || { echo "onboarding-box is not running" >&2; exit 1; }
[ "$(docker inspect -f '{{.HostConfig.NetworkMode}}' onboarding-box)" = "none" ] \
    || { echo "onboarding-box is not network-off; the protocol requires --network=none" >&2; exit 1; }

CLI_VERSION=$(claude --version 2>&1 | head -1)

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
ALLOWED="Bash,Read,Edit,Write,Glob,Grep"
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
rmdir "$WORKDIR" 2>/dev/null || true

REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
python3 "$SCRIPT_DIR/clock-audit.py" \
    "$RESULTS/transcript.jsonl" "$RESULTS" "$CLI_VERSION" "$PROMPT_SHA" "$agent_rc" "$REPO_ROOT"

echo ""
echo "next: read $RESULTS/meta.json (violations must be empty), pick the qualifying"
echo "      stop candidate, and write RESULTS.md with the derived wall-clock"
