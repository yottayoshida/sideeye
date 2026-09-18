#!/bin/sh
# The `observe` parameter is carried on macOS too — to a named refusal (#617, ADR 0074).
#
# Usage: check-mcp-observe-macos.sh <sideeye> <shim> <workdir> <toy>
#
# `--observe syscalls` installs a seccomp filter and macOS has no equivalent, so the
# engine answers `platform_unsupported` (src/main.zig, the check at the head of the
# recording phase). What this holds is that the MCP surface **carries the argument to
# that answer** rather than dropping it: a server that ignored the parameter on this
# platform would reach the default mode's outcome instead, and an agent would be told the
# mode had been tried when it had not.
#
# This is not the property of #617 — that one is Linux's, and it is
# `spike/mcp-acceptance.sh` mcp 19. Here there is not even a `next_step` naming the mode:
# `missedOperationNext` (src/boundary.zig) returns the class wall off Linux. What is
# asserted is narrower and worth its own leg: the argument reaches the engine, and the
# refusal that comes back is the engine's own, named.
#
# A separate script for the reason `check-readme-mcp-call.sh` gives: the macOS job runs it
# without the rest of the MCP suite, which is Linux-shaped, and the leg can be pointed at
# a mutated tree to be seen red.
set -u

SIDEEYE=${1:?usage: check-mcp-observe-macos.sh <sideeye> <shim> <workdir> <toy>}
SHIM=${2:?shim}
WS=${3:?workdir}
TOY=${4:?toy}

[ -x "$SIDEEYE" ] || { echo "FAIL: no sideeye at $SIDEEYE"; exit 1; }
[ -f "$SHIM" ] || { echo "FAIL: no shim at $SHIM"; exit 1; }
[ -x "$TOY" ] || { echo "FAIL: no toy at $TOY"; exit 1; }

# The workspace is this script's to make; the state directory inside it is not. The engine
# reaches this refusal in its recording phase, after `--setup` has run against the state
# directory (src/main.zig), and a config naming a directory that does not exist gets one —
# measured at the command line, where such a config reaches the oracle refusal rather than
# a missing-state one.
mkdir -p "$WS" || exit 1
cat > "$WS/observe.toml" <<TOML
[world]
state = "./obsstate"
[define]
setup     = "$TOY init"
operation = "$TOY rotate"
TOML

META='"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}'
req="{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{$META,\"name\":\"sideeye_explore_config\",\"arguments\":{\"config_path\":\"$WS/observe.toml\",\"observe\":\"syscalls\"}}}"

out=$WS/observe-macos.out
SIDEEYE_MCP_SHIM=$SHIM SIDEEYE_MCP_ROOT=$WS SIDEEYE_MCP_WORK=$WS/work \
    sh -c "printf '%s' '$req' | '$SIDEEYE' mcp" > "$out" 2>"$WS/observe-macos.err"

python3 - "$out" <<'PY'
import json, sys
lines = [l for l in open(sys.argv[1]) if l.strip()]
if not lines:
    sys.exit("FAIL: the server answered nothing")
d = json.loads(lines[-1])
if "error" in d:
    sys.exit("FAIL: a protocol error, not the engine's answer: %s" % d["error"])
r = d["result"]
sc = r.get("structuredContent") or {}
if sc.get("verdict") != "SETUP_ERROR":
    sys.exit("FAIL: verdict %r, wanted SETUP_ERROR — the argument did not reach the engine"
             % sc.get("verdict"))
if sc.get("setup_error_reason") != "platform_unsupported":
    sys.exit("FAIL: setup_error_reason %r, wanted platform_unsupported" % sc.get("setup_error_reason"))
if "--observe syscalls" not in (sc.get("message") or ""):
    sys.exit("FAIL: the message does not name the mode that was asked for: %r" % sc.get("message"))
if r.get("isError") is not True:
    sys.exit("FAIL: a SETUP_ERROR is isError true (ADR 0010), got %r" % r.get("isError"))
print("ok   observe=syscalls reaches the engine on macOS and comes back platform_unsupported, named")
PY
