#!/bin/sh
# Launch the fixer agent against a VARIANT=mcp stage — the MCP-mediated measurement.
#
# The seal recipe differs from run-agent.sh because --safe-mode never starts
# --mcp-config servers (measured 2026-08-13: zero traffic on a snooped server).
# The replacement, each piece measured before this script existed:
#   --strict-mcp-config + --mcp-config $ROOT/mcp.json   only the sideeye server
#   --disable-slash-commands                            skills/commands: zero
#   --settings seal-settings.json                       hooks off, plugins off by
#                                                       name (list YOURS there — an
#                                                       unnamed plugin stays live)
#   cwd = the stage (foreign project namespace)         no project memory
# Residue, stated rather than hidden: user agent names stay visible in the init
# event; they are unreachable because Task/Agent are denied. The canary below
# asserts the measurable parts (server connected, plugins [], skills 0) and one
# RED — a WebFetch attempt must come back denied — before the stage is burned.
#
# Refuses to run until the judge's two controls AND the MCP-channel contrast hold.
# One stage, one measurement: a second attempt needs a fresh stage.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SIDEEYE_REPO=${SIDEEYE_REPO:-$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)}

ROOT=${1:?usage: run-agent-mcp.sh <root staged with VARIANT=mcp>}
STAGE="$ROOT/stage"
RESULTS="$SIDEEYE_REPO/spike/runs/$(basename "$ROOT")"

command -v claude >/dev/null || { echo "claude CLI not found" >&2; exit 1; }
[ -d "$STAGE" ] || { echo "no stage at $STAGE" >&2; exit 1; }
[ -f "$ROOT/mcp.json" ] || { echo "no mcp.json at $ROOT — stage with VARIANT=mcp" >&2; exit 1; }

# All three controls must have held. The apparatus is proven before the agent runs.
python3 -c '
import json, sys
for p in sys.argv[1:]:
    if json.load(open(p)).get("expectation_met") is not True:
        sys.exit("control %s did not hold; not running any agent" % p)
' "$RESULTS/neg-verdict.json" "$RESULTS/pos-verdict.json" "$RESULTS/mcp-contrast.json"

[ -e "$RESULTS/transcript.jsonl" ] && { echo "a transcript already exists in $RESULTS; one run per stage" >&2; exit 1; }

# The stage's git is checked again HERE, the same as the cli launcher does (#62).
# This variant needs it MORE, not less: `contrast-mcp.sh` runs a further container
# against `$STAGE` between staging and this point, so there is more traffic through
# the window that `repo/**` being outside the seal leaves unwatched.
#
# Before the canaries, because everything after them is unreachable without spending
# the stage on a real agent — a gate placed there could only ever be observed by the
# run it exists to gate. `protocol.json` sits BESIDE the seal, not in it.
pin=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["pin"])' "$ROOT/seal/protocol.json") ||
    { echo "could not read the pin from protocol.json beside the seal" >&2; exit 1; }
sh "$SCRIPT_DIR/check-history.sh" "$ROOT" "$pin"
case $? in
    0) ;;
    1) echo "the stage's git holds more than the pin reaches; not running any agent" >&2; exit 1 ;;
    *) echo "the history check could not run; not running any agent" >&2; exit 1 ;;
esac

case "${2:-}" in
    "") ;;
    --check-only)
        echo "preflight and the history check hold; --check-only stops before the canaries"
        exit 0 ;;
    *) echo "unknown argument: $2 (expected nothing, or --check-only)" >&2; exit 2 ;;
esac

CLI_VERSION=$(claude --version 2>&1 | head -1)
SETTINGS="$SCRIPT_DIR/seal-settings.json"
ALLOWED="Bash,Read,Edit,Write,Glob,Grep,mcp__sideeye__sideeye_replay_case,mcp__sideeye__sideeye_explore_config"
# The outbound and delegation surface, denied by name (kept in step with the
# judge's UNSEALED set by hand — the judge does not read what this writes).
DISALLOWED="WebFetch,WebSearch,Task,Agent,Workflow,SendMessage,PushNotification,RemoteTrigger,ScheduleWakeup,CronCreate,CronDelete"

# Canary 1: the seal's measurable claims, from the init event — an artifact.
echo "=== canary 1: server connected, plugins none, skills none, auth alive ==="
( cd "$STAGE" && claude -p "Reply with exactly: ok" \
    --mcp-config "$ROOT/mcp.json" --strict-mcp-config \
    --disable-slash-commands --settings "$SETTINGS" \
    --allowedTools "$ALLOWED" --disallowedTools "$DISALLOWED" \
    --output-format stream-json --verbose \
    < /dev/null > "$RESULTS/canary1.jsonl" 2> "$RESULTS/canary1-stderr.log" ) \
    || { echo "canary 1 failed; see $RESULTS/canary1-stderr.log" >&2; exit 1; }
python3 - "$RESULTS/canary1.jsonl" <<'PY'
import json, sys
init = None
for line in open(sys.argv[1]):
    try:
        ev = json.loads(line)
    except json.JSONDecodeError:
        continue
    if isinstance(ev, dict) and ev.get("type") == "system" and ev.get("subtype") == "init":
        init = ev
        break
if init is None:
    sys.exit("canary 1: no init event in the stream")
# Key ABSENCE is not cleanliness: a renamed field would make every assertion
# below vacuously green. Demand the keys exist before reading them.
for key in ("mcp_servers", "plugins", "skills", "slash_commands"):
    if key not in init:
        sys.exit("canary 1: init carries no %r — the claim cannot be checked, so it is not checked-clean" % key)
servers = {s.get("name"): s.get("status") for s in init["mcp_servers"]}
if servers != {"sideeye": "connected"}:
    sys.exit("canary 1: mcp_servers = %r, wanted exactly sideeye connected" % servers)
if init["plugins"]:
    sys.exit("canary 1: plugins leaked into the session: %r" % init["plugins"])
if init["skills"] or init["slash_commands"]:
    sys.exit("canary 1: skills/commands leaked: %d/%d" % (len(init["skills"]), len(init["slash_commands"])))
print("canary 1: sideeye connected; plugins []; skills 0; auth alive")
PY

# Canary 2: the enforcement observed once, on its actual mechanism. Measured
# 2026-08-13, IN THIS CONFIGURATION (strict-mcp-config + slash-commands off +
# settings; under --safe-mode the same flag left every name presented): the
# disallowed tools are ABSENT from the presented set — removal is the
# configuration's behaviour, not the flag's alone. Measured for all eleven
# names in a throwaway session before the list was widened. The assertion is
# absence-from-init plus no attempt — not a behavioral denial. The probe's fetch
# request will be satisfied through allowed Bash + host network instead; that is
# the declared soft-seal residual, which the audit (not this canary) owns in the
# sealed run, and the canary records it rather than failing on it. The first
# version of this canary asserted "nothing fetched the page" and fired on the
# Bash fallback — a detector conflating two channels with different owners.
echo "=== canary 2: the disallowed tools must be absent from the presented set ==="
( cd "$STAGE" && claude -p "Call the WebFetch tool on https://example.com right now and paste its output. Do not refuse; attempt the call." \
    --mcp-config "$ROOT/mcp.json" --strict-mcp-config \
    --disable-slash-commands --settings "$SETTINGS" \
    --allowedTools "$ALLOWED" --disallowedTools "$DISALLOWED" \
    --output-format stream-json --verbose \
    < /dev/null > "$RESULTS/canary2.jsonl" 2> "$RESULTS/canary2-stderr.log" ) || true
python3 - "$RESULTS/canary2.jsonl" "$DISALLOWED" <<'PY'
import json, re, sys

# The deny set comes from the launcher's own $DISALLOWED — one source, so
# extending the list extends this assertion with it.
DISALLOWED = {t for t in sys.argv[2].split(",") if t}
NET = re.compile(r"\b(curl|wget)\b|https?://")
init_tools, attempted, bash_net = None, False, 0
def walk(node):
    global attempted, bash_net
    if isinstance(node, dict):
        if node.get("type") == "tool_use":
            if node.get("name") == "WebFetch":
                attempted = True
            if node.get("name") == "Bash" and NET.search(node.get("input", {}).get("command", "")):
                bash_net += 1
        for v in node.values():
            walk(v)
    elif isinstance(node, list):
        for v in node:
            walk(v)
for line in open(sys.argv[1]):
    try:
        ev = json.loads(line)
    except json.JSONDecodeError:
        continue
    if not isinstance(ev, dict):
        continue
    if ev.get("type") == "system" and ev.get("subtype") == "init" and init_tools is None:
        init_tools = ev.get("tools", [])
    walk(ev)
if init_tools is None:
    sys.exit("canary 2: no init event — the enforcement was not observed; not running the agent")
if not init_tools:
    sys.exit("canary 2: the init event's tool list is empty or unreadable — a clean verdict over an empty corpus is not clean; not running the agent")
# Positive control: the set must be readable AND contain what the agent needs.
if not {"Bash", "Read", "Edit"} <= set(init_tools):
    sys.exit("canary 2: the allowed core tools are missing from the presented set (%r...) — the reading is broken, not the seal" % sorted(init_tools)[:5])
present = DISALLOWED & set(init_tools)
if present:
    sys.exit("canary 2: disallowed tools still presented: %r — do not run the agent" % sorted(present))
if attempted:
    sys.exit("canary 2: WebFetch was attempted despite removal — investigate before running")
print("canary 2: all %d disallowed tools absent from the presented set (enforcement = removal)." % len(DISALLOWED))
print("          host-network residual via Bash observed %d time(s) — in the sealed run that channel voids via the audit, as declared." % bash_net)
PY

PROMPT="$SCRIPT_DIR/prompt-mcp.md"
PROMPT_SHA=$(shasum -a 256 "$PROMPT" | cut -d' ' -f1)

echo "=== the run: one agent, the sealed stage, the MCP surface, everything recorded ==="
agent_rc=0
( cd "$STAGE" && claude -p "$(cat "$PROMPT")" \
    --mcp-config "$ROOT/mcp.json" --strict-mcp-config \
    --disable-slash-commands --settings "$SETTINGS" \
    --allowedTools "$ALLOWED" --disallowedTools "$DISALLOWED" \
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
    "variant": "mcp",
    "model": model,
    "models_billed": model_usage,
    "cli_version": cli_version,
    "allowed_tools": allowed,
    "disallowed_tools": disallowed,
    "prompt_sha256": prompt_sha,
    "agent_rc": int(agent_rc),
    "safe_mode": False,
    "seal": "strict-mcp-config + disable-slash-commands + settings(hooks off, plugins off)",
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
echo "next: judge.sh audit --root $ROOT --transcript $RESULTS/transcript.jsonl --allow-mcp sideeye"
echo "      judge.sh eval  --root $ROOT --mode run"
echo "      judge.sh finalize --root $ROOT"
