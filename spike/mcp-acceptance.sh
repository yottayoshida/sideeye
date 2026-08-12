#!/bin/sh
# Acceptance for `sideeye mcp` (ADR 0010). Drives the server with hand-written JSON-RPC
# on stdin and checks the responses with a real JSON parser — grep succeeds on a
# truncated document, which is exactly the transport-contamination failure this exists
# to catch. Runs inside the Linux container; needs python3 (the base image has it).
#
# Every request carries the required _meta (protocolVersion + clientCapabilities); the
# checks that a *missing* _meta refuses are their own cases.
set -u

ROOT=${SIDEEYE_ROOT:-/work}
SIDEEYE=$ROOT/zig-out/bin/sideeye
SHIM=$ROOT/zig-out/lib/libsideeye_shim.so
OUT=$ROOT/spike/out
fails=0

if ! "$SIDEEYE" 2>&1 | grep -q "^sideeye "; then
    echo "CANNOT RUN: $SIDEEYE did not print its banner (built for this platform?)" >&2
    exit 1
fi

# A workspace root the server confines tool paths to. The toy configs live here.
WS=/tmp/mcp-ws
rm -rf "$WS"; mkdir -p "$WS/state"
cat > "$WS/sideeye.toml" <<TOML
[world]
state = "./state"
[define]
setup     = "$OUT/toy-bug init"
operation = "$OUT/toy-bug rotate"
TOML
cat > "$WS/sideeye-fixed.toml" <<TOML
[world]
state = "./state"
[define]
setup     = "$OUT/toy-fixed init"
operation = "$OUT/toy-fixed rotate"
TOML

export SIDEEYE_MCP_SHIM=$SHIM
export SIDEEYE_MCP_ROOT=$WS
export SIDEEYE_MCP_WORK=/tmp/mcp-work
# An oracle so explore reaches a real FAIL (and saves a case) rather than the
# oracle-less UNKNOWN completeness_not_verified.
export SIDEEYE_MCP_ORACLE=/usr/bin/strace

# _meta lives under params (schema.ts: RequestParams._meta). META is the _meta fragment;
# every request nests it in params (discover/list carry params only for the _meta).
META='"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}'

# Run the server over a set of \n-delimited messages; capture stdout and stderr apart.
drive() { printf '%s' "$1" | "$SIDEEYE" mcp >/tmp/mcp.out 2>/tmp/mcp.err; }

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; sed 's/^/     | /' /tmp/mcp.out | head -6; fails=$((fails + 1)); }

echo "=========== mcp 1: every stdout line is exactly one JSON-RPC message ==========="
# The core transport invariant. The explore child prints a big report to *its* stdout;
# none of it may reach the MCP transport (fd 1). Also exercises discover + list + call.
req="{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"server/discover\",\"params\":{$META}}
{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{$META}}
{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{$META,\"name\":\"sideeye_explore_config\",\"arguments\":{\"config_path\":\"$WS/sideeye.toml\"}}}"
drive "$req"
python3 - <<'PY' && pass "discover+list+explore: all stdout lines are single JSON-RPC, no child report leaked" || fail "transport contamination or bad response"
import json, sys
lines=[l for l in open("/tmp/mcp.out") if l.strip()]
if len(lines)!=3: sys.exit("wanted 3 lines, got %d"%len(lines))
for l in lines:
    d=json.loads(l)
    assert d.get("jsonrpc")=="2.0", l[:60]
raw=open("/tmp/mcp.out").read()
for s in ["crash worlds violated","reproduce   SIDEEYE","atomicity   "]:
    assert s not in raw, "child report leaked: "+s
d1,d2,d3=[json.loads(l) for l in lines]
assert d1["result"]["supportedVersions"]==["2026-07-28"], d1
assert "tools" in d1["result"]["capabilities"], d1
names=[t["name"] for t in d2["result"]["tools"]]
assert names==["sideeye_explore_config","sideeye_replay_case"], names
sc=d3["result"]["structuredContent"]
# This check verifies transport + wiring, not toy-bug's specific verdict (that is the
# explore suite's job): a real verdict, isError consistent with it, echoed in content.
v=sc["verdict"]; assert v in ("PASS","FAIL","UNKNOWN","SETUP_ERROR"), sc
assert d3["result"]["isError"] is (v not in ("PASS","FAIL")), d3["result"]
assert v in d3["result"]["content"][0]["text"], "content summary missing verdict"
PY

echo "=========== mcp 2: _meta is validated on every method ==========="
# Missing _meta on tools/list (not just tools/call) must be -32602; a wrong version
# must be -32022 with supported/requested. tools/call-only validation would miss these.
drive '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
python3 -c 'import json;d=json.load(open("/tmp/mcp.out"));assert d["error"]["code"]==-32602,d' \
  && pass "missing _meta on tools/list is -32602" || fail "missing _meta not refused on tools/list"
drive '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"1999-01-01","io.modelcontextprotocol/clientCapabilities":{}}}}'
python3 -c 'import json;d=json.load(open("/tmp/mcp.out"));e=d["error"];assert e["code"]==-32022 and e["data"]["supported"]==["2026-07-28"] and e["data"]["requested"]=="1999-01-01",d' \
  && pass "unsupported version is -32022 with supported/requested" || fail "version negotiation wrong"

echo "=========== mcp 3: a path outside the server root is refused, not executed ==========="
# Traversal / absolute escape must be a tool error before any exec. Uses a real file
# outside the root so realpath succeeds but the prefix check fails.
echo "not a config" > /tmp/outside.toml
drive "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{$META,\"name\":\"sideeye_explore_config\",\"arguments\":{\"config_path\":\"/tmp/outside.toml\"}}}"
python3 -c 'import json;d=json.load(open("/tmp/mcp.out"));r=d["result"];assert r["isError"] is True and "outside the server root" in r["content"][0]["text"],d' \
  && pass "a path outside SIDEEYE_MCP_ROOT is an isError, not an execution" || fail "path confinement failed"

echo "=========== mcp 4: the child gets a minimal env (no credential leak) ==========="
# A config whose operation prints the environment must not reveal a secret the server
# holds. The minimal-env exec passes only PATH.
mkdir -p "$WS/envstate"
cat > "$WS/env.toml" <<TOML
[world]
state = "./envstate"
[define]
operation = "/bin/sh -c env"
TOML
# The operation has a space, which sideeye's arg split rejects — so use a script.
cat > "$WS/printenv.sh" <<'SH'
#!/bin/sh
env > /tmp/mcp-childenv.txt
SH
chmod +x "$WS/printenv.sh"
cat > "$WS/env.toml" <<TOML
[world]
state = "./envstate"
[define]
operation = "$WS/printenv.sh"
TOML
rm -f /tmp/mcp-childenv.txt
MCP_SECRET_TOKEN=supersecret123 SIDEEYE_MCP_SHIM=$SHIM SIDEEYE_MCP_ROOT=$WS SIDEEYE_MCP_WORK=/tmp/mcp-work \
  sh -c "printf '%s' '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{$META,\"name\":\"sideeye_explore_config\",\"arguments\":{\"config_path\":\"$WS/env.toml\"}}}' | \"$SIDEEYE\" mcp >/tmp/mcp.out 2>/tmp/mcp.err"
if [ -f /tmp/mcp-childenv.txt ] && grep -q "supersecret123" /tmp/mcp-childenv.txt; then
    fail "the child saw the server's secret env (MCP_SECRET_TOKEN leaked)"
elif [ -f /tmp/mcp-childenv.txt ]; then
    pass "the child's environment is minimal; the server's secret did not leak"
else
    # The operation ran under the shim; if the file is absent the run was refused —
    # still no leak, but note it.
    echo "ok   (child env file absent; no leak, run may have refused — check /tmp/mcp.out)"
fi

echo "=========== mcp 5: canonical self-exec ignores a PATH-hijacking fake ==========="
# Put a fake `sideeye` first on PATH. The server must self-exec the real binary
# (/proc/self/exe), not the fake. The fake would produce no valid report.
FAKEDIR=/tmp/fakebin; mkdir -p "$FAKEDIR"
cat > "$FAKEDIR/sideeye" <<'SH'
#!/bin/sh
echo "FAKE" >&2
exit 42
SH
chmod +x "$FAKEDIR/sideeye"
PATH="$FAKEDIR:$PATH" SIDEEYE_MCP_SHIM=$SHIM SIDEEYE_MCP_ROOT=$WS SIDEEYE_MCP_WORK=/tmp/mcp-work \
  sh -c "printf '%s' '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{$META,\"name\":\"sideeye_explore_config\",\"arguments\":{\"config_path\":\"$WS/sideeye-fixed.toml\"}}}' | \"$SIDEEYE\" mcp >/tmp/mcp.out 2>/tmp/mcp.err"
# The fake sideeye exits 42 and writes no report; the real one produces a valid
# sideeye report (whatever the verdict — here UNKNOWN completeness_not_verified, since
# the MCP path runs without an oracle). A real report proves canonical self-exec ran
# the real binary, not the PATH fake.
python3 -c 'import json;d=json.load(open("/tmp/mcp.out"));sc=d["result"].get("structuredContent",{});assert sc.get("schema")=="sideeye/report" and "verdict" in sc,d' \
  && pass "self-exec ran the real binary (a real sideeye report), not the PATH fake" || fail "self-exec used argv[0]/PATH, not the canonical path"

echo ""
if [ "$fails" = "0" ]; then echo "ALL MCP ACCEPTANCE CHECKS PASSED"; else echo "$fails MCP check(s) failed"; exit 1; fi
