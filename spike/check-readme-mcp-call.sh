#!/bin/sh
# Run the README's own MCP first call, from a cleared environment.
#
# Usage: check-readme-mcp-call.sh <README.md> <sideeye> <shim> <workdir> <toy-bug>
#
# #389: driving `sideeye mcp` from the README alone was refused four times on the shipped
# v1.0.0, and three of the four were recoverable only by reading `src/mcp.zig`. The
# sharpest was `SIDEEYE_MCP_SHIM` — required for every `tools/call` and named in no
# operating document, while the section around it explained two other variables in depth
# and so read as complete.
#
# **The environment is cleared, and that is the whole of this check's value.**
# `spike/mcp-acceptance.sh` exports the server's variables before any of its legs run, so
# none of them can observe what a caller starting from nothing has to supply — which is
# exactly the class #389 was in. Run with those exports inherited, this would be a slower
# copy of `mcp 1`.
#
# PATH is the one thing passed through, on the grounds `spike/check-mcp-env.py` records
# for excusing it from the README's table: nobody sets PATH in order to run this, and a
# caller who has a shell has it already. Everything else must come from the page. (An
# earlier version of this comment said the README's table carries that reasoning. It does
# not — the table lists only the six `SIDEEYE_MCP_*` variables, and `PATH` appears nowhere
# in the section.)
#
# A separate script rather than a leg body so that (a) the macOS job can run it without
# the rest of the suite, which is Linux-shaped (a `.so` shim and an strace oracle), and
# (b) the README side can be falsified in isolation by pointing it at a mutated copy —
# the same reason `check-report-schema.py` takes paths.
set -u

if [ $# -ne 5 ]; then
    echo "usage: check-readme-mcp-call.sh <README.md> <sideeye> <shim> <workdir> <toy-bug>" >&2
    exit 2
fi
README=$1
SIDEEYE=$2
SHIM=$3
WORKDIR=$4
# The target is a parameter rather than a name inside the workdir. The first revision
# assumed `$WORKDIR/toy-bug`, which the macOS job builds and the Linux container does not
# — its toys land in `spike/out/`. The Linux leg would have failed on every run, and the
# promise "run on Linux and macOS" would have held only in the sense that one of the two
# was red.
TOY=$5
[ -x "$SIDEEYE" ] || { echo "FAIL $SIDEEYE is not executable" >&2; exit 1; }
# The shim is not substituted into anything any more — the server finds it. It is still a
# precondition: if the build did not produce one, this check would fail for a reason that
# has nothing to do with the README, and saying so here is cheaper than reading the
# server's refusal and guessing.
[ -f "$SHIM" ] || { echo "FAIL $SHIM is missing — the build produced no shim for the server to find" >&2; exit 1; }
[ -x "$TOY" ] || { echo "FAIL $TOY is missing or not executable — the caller must name a built target with a real bug" >&2; exit 1; }

WS=$WORKDIR/readme-ws
rm -rf "$WS"
mkdir -p "$WS/state"
# A target with a real crash-consistency bug, so the call reaches a FAIL. That matters
# beyond convenience: `isError` follows the verdict structure, and without an oracle a
# would-be PASS refuses as `completeness_not_verified` — so a clean target would make this
# check depend on a second witness the README does not require and macOS does not have.
cat > "$WS/sideeye.toml" <<TOML
[world]
state = "./state"
[define]
setup     = "$TOY init"
operation = "$TOY rotate"
TOML

python3 - "$README" "$WS" "$SHIM" "$WORKDIR" <<'PY' || exit 1
import re, sys
readme, ws, shim, workdir = sys.argv[1:5]
lines = open(readme, encoding="utf-8").read().split("\n")

# The section, not the page. The promise is about the README's MCP section, and a fence
# that wandered out of it would still be found by a whole-file scan.
start = next((i for i, l in enumerate(lines)
              if l.strip() == "## Driving it from an agent (MCP)"), None)
if start is None:
    sys.exit("the README has no '## Driving it from an agent (MCP)' heading")
end = next((j for j in range(start + 1, len(lines)) if lines[j].startswith("## ")), len(lines))
section = "\n".join(lines[start:end])

def fence(info):
    blocks = re.findall(r"^```%s\n(.*?)^```$" % info, section, re.M | re.S)
    if len(blocks) != 1:
        sys.exit("wanted exactly one ```%s fence in the MCP section, found %d" % (info, len(blocks)))
    return blocks[0]

sh, rpc = fence("sh"), fence("jsonrpc")

# The page tells the reader which values are theirs, spelled /path/to/…. Substituting by
# token and then requiring that no /path/to/ survive catches a placeholder added later —
# which counting substitutions would not, since a token this script does not know never
# enters the count. There is one token today; there were two before the server learned to
# find its own shim, and the check does not care which.
def fill(text):
    return text.replace("/path/to/your/workspace", ws)

sh, rpc = fill(sh), fill(rpc)
stray = [l for l in (sh + "\n" + rpc).split("\n") if "/path/to/" in l]
if stray:
    sys.exit("a placeholder this check cannot fill survived substitution: %r" % stray[0])

# No byte comparison against a copy of the protocol fragment. The first revision had one
# and claimed it was what separated this check from `mcp 1`; measured, it is not — with
# the assertion removed, a README whose `_meta` has drifted to the short spelling still
# fails, at the server, with `missing params._meta["io.modelcontextprotocol/…"]`. What
# separates this check from `mcp 1` is that the bytes come from the page. The assertion
# only moved the failure earlier, and it needed a second copy of the fragment living here
# — a constant that can itself drift out of step with the suite it was named after.

reqs = [l for l in rpc.split("\n") if l.strip()]
if len(reqs) != 2:
    sys.exit("wanted 2 request lines from the README's exchange, got %d" % len(reqs))

open(workdir + "/readme-env.sh", "w", encoding="utf-8").write(sh)
open(workdir + "/readme-req.txt", "w", encoding="utf-8").write("\n".join(reqs))
PY

[ -s "$WORKDIR/readme-req.txt" ] || { echo "FAIL the extracted request file is empty — nothing would have been measured" >&2; exit 1; }

env -i PATH="$PATH" sh -c ". $WORKDIR/readme-env.sh; exec \"$SIDEEYE\" mcp" \
    < "$WORKDIR/readme-req.txt" > "$WORKDIR/readme-out.txt" 2> "$WORKDIR/readme-err.txt"

python3 - "$WORKDIR/readme-out.txt" <<'PY' || exit 1
import json, sys
out = sys.argv[1]
lines = [l for l in open(out, encoding="utf-8") if l.strip()]
if len(lines) != 2:
    sys.exit("wanted 2 responses from the README's 2 requests, got %d" % len(lines))
listed, called = (json.loads(l) for l in lines)
if "error" in listed:
    sys.exit("the README's tools/list was refused: %r" % listed["error"])
names = sorted(t["name"] for t in listed["result"]["tools"])
if names != ["sideeye_explore_config", "sideeye_replay_case"]:
    sys.exit("tools/list returned %r" % names)
if "error" in called:
    sys.exit("the README's tools/call was refused at the protocol level: %r" % called["error"])
result = called["result"]
if result.get("isError") is not False:
    text = (result.get("content") or [{}])[0].get("text", "")
    sys.exit("the README's first call did not reach a verdict: %s" % text[:200])
verdict = result["structuredContent"].get("verdict")
if verdict not in ("FAIL", "PASS"):
    sys.exit("isError was false without a verdict: %r" % verdict)
print("the README's environment block and exchange reached %s with nothing else set" % verdict)
PY
