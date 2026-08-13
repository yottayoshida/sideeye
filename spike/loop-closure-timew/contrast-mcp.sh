#!/bin/sh
# Prove the MCP channel gives opposite answers on this stage before any agent runs.
# The unpatched tree must replay FAIL at the case's own crash point — TWICE, in one
# server session, because the server is persistent and per-call freshness (#69) is
# part of what is being proven. The known patch must replay PASS. The server is
# started with the exact command the agent's client will use (read from mcp.json),
# driven with hand-written JSON-RPC. Ends with the unpatched binary installed, which
# is the world the agent must start from.
#
# Writes $RESULTS/mcp-contrast.json; exits nonzero when a control does not hold —
# a broken channel stops the experiment before an agent burns the stage.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SIDEEYE_REPO=${SIDEEYE_REPO:-$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)}
PATCH="$SIDEEYE_REPO/spike/timew-undo-ordering.patch"

ROOT=${1:?usage: contrast-mcp.sh <root staged with VARIANT=mcp>}
STAGE="$ROOT/stage"
SEAL="$ROOT/seal"
RESULTS="$SIDEEYE_REPO/spike/runs/$(basename "$ROOT")"
MCPJSON="$ROOT/mcp.json"
[ -f "$MCPJSON" ] || { echo "no mcp.json at $ROOT — stage with VARIANT=mcp first" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "known patch not found: $PATCH" >&2; exit 1; }
mkdir -p "$RESULTS"

# The image sits two positions before the "mcp" subcommand in the generated
# args — located by anchor, not by tail offset, so config edits fail loudly.
IMAGE=$(python3 -c 'import json,sys;a=json.load(open(sys.argv[1]))["mcpServers"]["sideeye"]["args"];print(a[a.index("mcp")-2])' "$MCPJSON")
CASE="$STAGE/work/cases/000001.json"

build_into_bin() { # $1 = plain|patch
    docker run --rm --network none -v "$STAGE:$STAGE" -v "$PATCH:/tmp/fix.patch" \
        -e STAGE="$STAGE" -e WHICH="$1" "$IMAGE" sh -eu -c '
            cp -r "$STAGE/repo" /tmp/src
            if [ "$WHICH" = "patch" ]; then git -C /tmp/src apply /tmp/fix.patch; fi
            cmake -S /tmp/src -B /tmp/build -DCMAKE_BUILD_TYPE=Release >/dev/null
            cmake --build /tmp/build -j"$(nproc)" >/dev/null
            mkdir -p "$STAGE/bin"
            cp /tmp/build/src/timew "$STAGE/bin/timew"
        '
}

# Drive the exact server command the client will start, sending N identical replay
# calls in one server session. Prints one "verdict explored crash_point" line each.
replay_calls() { # $1 = how many
    python3 - "$MCPJSON" "$CASE" "$1" <<'PY'
import json, subprocess, sys

cfg = json.load(open(sys.argv[1]))["mcpServers"]["sideeye"]
case, n = sys.argv[2], int(sys.argv[3])
meta = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {}}
reqs = "".join(json.dumps({"jsonrpc": "2.0", "id": i + 1, "method": "tools/call",
                           "params": {"_meta": meta, "name": "sideeye_replay_case",
                                      "arguments": {"case_path": case}}}) + "\n"
               for i in range(n))
out = subprocess.run([cfg["command"]] + cfg["args"], input=reqs.encode(),
                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout
for line in out.decode().splitlines():
    line = line.strip()
    if not line:
        continue
    sc = json.loads(line).get("result", {}).get("structuredContent", {})
    print("%s %s %s" % (sc.get("verdict"), sc.get("explored"),
                        (sc.get("earliest") or {}).get("crash_point")))
PY
}

CASE_K=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["case_k"])' "$SEAL/protocol.json")

echo "=== contrast-mcp: unpatched tree -> FAIL at k=$CASE_K, twice in one session ==="
build_into_bin plain
neg_out=$(replay_calls 2)
printf '%s\n' "$neg_out"

echo "=== contrast-mcp: known patch -> PASS ==="
build_into_bin patch
pos_out=$(replay_calls 1)
printf '%s\n' "$pos_out"

echo "=== contrast-mcp: reinstall the unpatched binary (the agent's starting world) ==="
build_into_bin plain

NEG_OUT="$neg_out" POS_OUT="$pos_out" CASE_K="$CASE_K" OUT="$RESULTS/mcp-contrast.json" python3 <<'PY'
import json, os, sys

neg = [l.split() for l in os.environ["NEG_OUT"].splitlines() if l.strip()]
pos = [l.split() for l in os.environ["POS_OUT"].splitlines() if l.strip()]
k = os.environ["CASE_K"]
ok = (len(neg) == 2 and all(v[0] == "FAIL" and v[2] == k for v in neg)
      and len(pos) == 1 and pos[0][0] == "PASS" and pos[0][1] == "2")
record = {"neg": neg, "pos": pos, "case_k": int(k), "expectation_met": ok}
json.dump(record, open(os.environ["OUT"], "w"), indent=1)
print("mcp-contrast: expectation_met=%s" % ok)
if not ok:
    sys.exit("the MCP channel did not give opposite answers — fix the apparatus before running any agent")
PY
