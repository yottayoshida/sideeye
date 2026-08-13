#!/bin/sh
# Launch the fixer agent against the sealed stage — the measurement itself.
#
# The seal here is soft and the void is hard (the BUILDLOG carries the protocol):
# the agent is a fresh Claude Code headless session started with --safe-mode,
# which disables every customization (CLAUDE.md, hooks, MCP servers, skills,
# plugins) while auth and built-in tools work normally. cwd is the stage, whose
# project namespace holds no memory. Tools: a six-tool allowlist plus an
# explicit deny of the network/delegation tools — an allowlist is not a menu,
# the harness still presents its full tool set, so the audit reads every call
# in the stream-json transcript: one network reach or one read into this
# workspace voids the run. This is not a network namespace; it is a measurement
# whose invalidation condition is declared before it runs.
#
# Why not a scratch CLAUDE_CONFIG_DIR: measured 2026-08-13 — a scratch config
# dir is "Not logged in" even with ~/.claude.json's account keys copied in; the
# keychain credential is keyed to the config dir, and copying keychain items is
# off-limits by workspace rule. --safe-mode gives the same isolation with auth
# intact. The isolation evidence is the transcript's init event (mcp_servers
# empty, default output style, built-in agents only) — an artifact; the canary
# below proves auth and nothing more, and its reply is kept in the results.
#
# Refuses to run until both controls hold, and refuses to run twice: one stage,
# one measurement. A second attempt needs a fresh stage.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SIDEEYE_REPO=${SIDEEYE_REPO:-$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)}

ROOT=${1:?usage: run-agent.sh <root dir staged by stage.sh>}
STAGE="$ROOT/stage"
RESULTS="$SIDEEYE_REPO/spike/runs/$(basename "$ROOT")"

command -v claude >/dev/null || { echo "claude CLI not found" >&2; exit 1; }
[ -d "$STAGE" ] || { echo "no stage at $STAGE" >&2; exit 1; }

# Both controls must have held. The apparatus is proven before the agent runs.
python3 -c '
import json, sys
for p in sys.argv[1:]:
    if json.load(open(p)).get("expectation_met") is not True:
        sys.exit("control %s did not hold; not running any agent" % p)
' "$RESULTS/neg-verdict.json" "$RESULTS/pos-verdict.json"

[ -e "$RESULTS/transcript.jsonl" ] && { echo "a transcript already exists in $RESULTS; one run per stage" >&2; exit 1; }

CLI_VERSION=$(claude --version 2>&1 | head -1)

# Canary: safe mode must authenticate before the real run burns the stage.
canary_out=$( cd "$STAGE" && claude --safe-mode -p "Reply with exactly: ok" < /dev/null 2>"$RESULTS/canary-stderr.log" ) \
    || { echo "canary failed — safe mode did not authenticate; see $RESULTS/canary-stderr.log" >&2; exit 1; }
case "$canary_out" in
    *ok*) echo "canary: safe mode authenticates" ;;
    *) echo "canary returned unexpected output: $canary_out" >&2; exit 1 ;;
esac
printf '%s\n' "$canary_out" > "$RESULTS/canary-out.txt"

PROMPT="$SCRIPT_DIR/prompt.md"
PROMPT_SHA=$(shasum -a 256 "$PROMPT" | cut -d' ' -f1)
# NOTE: judge.sh's audit keeps its own copies of these sets (ALLOWED/UNSEALED)
# on purpose — the judge trusts nothing this script writes. Change both or the
# audit's classification silently drifts.
ALLOWED="Bash,Read,Edit,Write,Glob,Grep"
# Deny the network-by-construction and delegation tools by name. This flag's
# enforcement has not been seen red yet — before trusting it, the next staging
# must probe the seal once (a WebFetch attempt that must come back denied).
# The outbound and delegation surface, denied by name — kept in step with
# run-agent-mcp.sh and the judge's UNSEALED set by hand.
DISALLOWED="WebFetch,WebSearch,Task,Agent,Workflow,SendMessage,PushNotification,RemoteTrigger,ScheduleWakeup,CronCreate,CronDelete"

echo "=== the run: one agent, the sealed stage, the transcript records everything ==="
agent_rc=0
( cd "$STAGE" && claude --safe-mode -p "$(cat "$PROMPT")" \
    --allowedTools "$ALLOWED" \
    --disallowedTools "$DISALLOWED" \
    --output-format stream-json --verbose \
    < /dev/null \
    > "$RESULTS/transcript.jsonl" 2> "$RESULTS/agent-stderr.log" ) || agent_rc=$?
echo "agent exited: $agent_rc"

python3 - "$RESULTS/transcript.jsonl" "$RESULTS/agent-meta.json" \
    "$CLI_VERSION" "$ALLOWED" "$PROMPT_SHA" "$agent_rc" "$DISALLOWED" <<'PY'
import json, sys

transcript, out, cli_version, allowed, prompt_sha, agent_rc, disallowed = sys.argv[1:8]
model, model_usage, result = None, None, {}
with open(transcript) as f:
    for line in f:
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(ev, dict):
            continue
        if model is None and ev.get("model"):
            model = ev["model"]  # the init event: the model the run was asked to use
        if isinstance(ev.get("modelUsage"), dict):
            model_usage = sorted(ev["modelUsage"])  # the result event: every model that billed
        if ev.get("type") == "result":
            result = ev
meta = {
    "model": model,
    "models_billed": model_usage,
    "cli_version": cli_version,
    "allowed_tools": allowed,
    "disallowed_tools": disallowed,
    "prompt_sha256": prompt_sha,
    "agent_rc": int(agent_rc),
    "safe_mode": True,
    # The headline numbers, into an artifact — the run dir is gitignored and a
    # hand-read result event is not a record.
    "num_turns": result.get("num_turns"),
    "duration_ms": result.get("duration_ms"),
    "total_cost_usd": result.get("total_cost_usd"),
}
json.dump(meta, open(out, "w"), indent=1)
print("agent-meta: model=%s cli=%s" % (model, cli_version))
if not model:
    sys.exit("no model id found in the transcript — record it by hand before finalize")
PY

echo ""
echo "next: judge.sh audit --root $ROOT --transcript $RESULTS/transcript.jsonl"
echo "      judge.sh eval  --root $ROOT --mode run"
echo "      judge.sh finalize --root $ROOT"
