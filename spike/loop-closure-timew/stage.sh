#!/bin/sh
# Assemble the sealed stage for the loop-closure experiment (DESIGN §17, second
# criterion): a coding agent receives a counterexample and the repository, and must
# produce a fix that makes the replay pass — no human translation.
#
# What the agent receives (the input set, declared here and in the BUILDLOG so the
# result is never overclaimed as "the report alone"):
#   report.json                 the FAIL report from a fresh exploration
#   work/cases/000001.json      the saved case the report names (its real path)
#   define/setup.sh, check.sh   the declared invariant the case's define points at
#   repo/                       timewarrior at the pinned commit, unpatched, and
#                               narrowed to it: the history up to the pin is there,
#                               nothing after it is, and `check-history.sh` asserts
#                               that against the object store rather than the refs
#                               (#62). Its submodule is narrowed the same way.
#   replay.sh | build.sh        the re-check button, by VARIANT: cli bakes
#                               replay.sh (rebuild + replay in one script), mcp
#                               bakes build.sh (rebuild + install; the replay is
#                               the sideeye_replay_case tool)
#   .harness/                   the sideeye binary and shim the plumbing runs
#
# What the agent does not receive: this repository (the buildlog, the known patch,
# the dogfood scripts), the upstream issue, network access, and — since #62 — any git
# object the pin cannot reach. The experiment's text
# outputs (exploration console, control verdicts, transcripts) go to
# spike/runs/<root-name>/ in this repository — outside the stage — so nothing in
# the agent's world names the finding.
#
# What sits inside the pin's own snapshot is a separate question, and this file makes
# no claim to have audited it. What WAS read, and all that was read: `ChangeLog`'s two
# `undo` entries at this pin, #416 (an encode/decode failure) and #9 (the feature's
# introduction), neither of which is the finding. Review then found `test/write-failure.t`
# in the same snapshot — a committed fault-injection harness whose comment names "tags,
# undo, datafiles, configs" — which is exactly why the first version of this paragraph,
# claiming an audit of the snapshot on the strength of one file and one keyword, was
# wrong. The snapshot is NOT filtered: filtering it would make "the repository" false in
# a different way. It is also not cleared.
#
# Sealing: every staged file except repo/** is copied to <root>/seal/files and
# hashed into <root>/seal/manifest.sha256. The judge restores from the seal before
# judging, so edits outside repo/ cannot change the verdict.
#
# Runs on the macOS host; every container run uses --network none (the clone
# happens here on the host, where the corporate TLS interception is trusted).
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SIDEEYE_REPO=${SIDEEYE_REPO:-$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)}
# Full 40-hex pin, verified with `git rev-parse HEAD` after checkout — a content
# address, not a lookup convenience (same discipline as dogfood-timew-replay.sh).
PIN=${PIN:-db7751cb12aa3b1d52161a9e2457be8539644e56}
TIMEW_GIT=${TIMEW_GIT:-https://github.com/GothenburgBitFactory/timewarrior.git}
IMAGE=${IMAGE:-sideeye-loop-timew:latest}
# The define's operation, written once: the explore records it into the case,
# and protocol.json carries it to the judge so the functional gate drives the
# same command (space-separated words only — sideeye's own operation parsing).
OPERATION="timew track 2020-01-02T10:00 - 2020-01-02T11:00 beta :yes"
# VARIANT selects the agent's re-check button. cli (default): a baked replay.sh.
# mcp: a baked build.sh plus an mcp.json at the root — the agent rebuilds with
# the script and replays through the sideeye MCP server (ADR 0011). The seal
# stays seven files either way; only the button swaps.
VARIANT=${VARIANT:-cli}
case "$VARIANT" in cli|mcp) ;; *) echo "VARIANT must be cli or mcp" >&2; exit 1 ;; esac

ROOT=${1:?usage: stage.sh <new absolute root dir, e.g. \$HOME/sideeye-loop-1>}
case "$ROOT" in /*) ;; *) echo "root must be an absolute path" >&2; exit 1 ;; esac
case "$ROOT" in *" "*) echo "root must not contain spaces" >&2; exit 1 ;; esac
# The stage must be fresh, and nothing here deletes recursively: pick a new path.
[ -e "$ROOT" ] && { echo "$ROOT already exists. Choose a new path." >&2; exit 1; }

STAGE="$ROOT/stage"
SEAL="$ROOT/seal"
RESULTS="$SIDEEYE_REPO/spike/runs/$(basename "$ROOT")"
[ -e "$RESULTS" ] && { echo "$RESULTS already exists. Choose a new root name." >&2; exit 1; }

for tool in docker git python3 shasum tar; do
    command -v "$tool" >/dev/null || { echo "$tool not found" >&2; exit 1; }
done

# zig-out holds one platform at a time; a host (Mach-O) build here would ride the
# mount into the container and fail confusingly. Check the magic, not the filename.
SIDEEYE_BIN="$SIDEEYE_REPO/zig-out/bin/sideeye"
SHIM_LIB="$SIDEEYE_REPO/zig-out/lib/libsideeye_shim.so"
for f in "$SIDEEYE_BIN" "$SHIM_LIB"; do
    [ -f "$f" ] || { echo "$f not found; build first: zig build -Dtarget=aarch64-linux-gnu" >&2; exit 1; }
    python3 -c 'import sys; sys.exit(0 if open(sys.argv[1],"rb").read(4)==b"\x7fELF" else 1)' "$f" \
        || { echo "$f is not a Linux ELF; rebuild: zig build -Dtarget=aarch64-linux-gnu" >&2; exit 1; }
done

docker image inspect "$IMAGE" >/dev/null 2>&1 || docker build -t "$IMAGE" "$SCRIPT_DIR"

mkdir -p "$STAGE/.harness" "$STAGE/define" "$SEAL/files" "$RESULTS"
cp "$SIDEEYE_BIN" "$STAGE/.harness/sideeye"
cp "$SHIM_LIB" "$STAGE/.harness/libsideeye_shim.so"
cp "$SCRIPT_DIR/define/setup.sh" "$SCRIPT_DIR/define/check.sh" "$STAGE/define/"
chmod +x "$STAGE/define/setup.sh" "$STAGE/define/check.sh" "$STAGE/.harness/sideeye"

echo "=== clone at the pin, then remove everything the pin cannot reach ==="
# The clone is still a full one, and the history up to the pin is still here on
# purpose (#62). A `--depth 1` fetch would seal harder and was rejected: the agent
# would receive a repository with ONE commit, and this experiment declares that it
# hands over "the repository" — a checkout that cannot be blamed or logged is a
# different object to work in, and changing it changes what is measured.
#
# What is removed is the future. A full clone carries every upstream branch and every
# commit made since the pin, so with an older pin upstream's own fix for the finding
# would be sitting in the stage, one `git log --all` away. The recorded run has a
# witness: the agent's `git branch -a` printed an upstream issue branch.
#
# Deleting refs is not enough — the objects outlive them until a prune. So: detach at
# the pin, drop every ref, drop the remote (and with it the fetch refspec that would
# bring them back), drop the fetch bookkeeping, expire the reflog, and collect. The
# assertion afterwards is what this rests on, not the completeness of this list.
git clone --quiet "$TIMEW_GIT" "$STAGE/repo"
git -C "$STAGE/repo" checkout --quiet --detach "$PIN"
got=$(git -C "$STAGE/repo" rev-parse HEAD)
[ "$got" = "$PIN" ] || { echo "checkout mismatch: wanted $PIN, got $got" >&2; exit 1; }
git -C "$STAGE/repo" submodule update --init --quiet

narrow_to_head() { # $1 = a git work tree whose HEAD is already where it should be
    # Resolved, never assembled as "$1/.git": a submodule's `.git` is a FILE pointing
    # into `repo/.git/modules/…`, so a path built by hand would name nothing and the
    # `rm -f` below would succeed against it silently.
    gitdir=$(git -C "$1" rev-parse --absolute-git-dir) ||
        { echo "not a git work tree: $1" >&2; exit 1; }
    # One transaction, one process, one exit status. The first version piped
    # `for-each-ref` into a `while` loop, whose status is the loop's: if the listing
    # died the loop read nothing and reported success, the refs survived, and the
    # failure surfaced later as the history check saying the stage carries a future —
    # a true verdict with the wrong cause attached.
    # `--no-deref` is not decoration: a clone leaves `refs/remotes/origin/HEAD` as a
    # symref to `refs/remotes/origin/main`, and a batch that deletes both is refused
    # outright ("multiple updates … including one via symref … are not allowed").
    # Without it this whole function fails and the refs survive — measured, on a
    # two-submodule scratch, while writing the batching that this comment explains.
    git -C "$1" for-each-ref --format='delete %(refname)' |
        git -C "$1" update-ref --no-deref --stdin ||
        { echo "could not delete refs in $1" >&2; exit 1; }
    for remote in $(git -C "$1" remote); do
        git -C "$1" remote remove "$remote"
    done
    rm -f "$gitdir/FETCH_HEAD" "$gitdir/ORIG_HEAD"
    git -C "$1" reflog expire --expire=now --expire-unreachable=now --all
    git -C "$1" gc --prune=now --quiet
}
narrow_to_head "$STAGE/repo"
# Each submodule is a repository of its own: its objects live under
# `repo/.git/modules/`, where the superproject's own refs and rev-list cannot see
# them. Stripping only the top level would leave a submodule's whole history in place
# while every top-level assertion still passed.
#
# The set is DERIVED from the pin's tree, never written down here. A hard-coded
# `src/libshared` was the first version, and review demonstrated the failure: a
# superproject with a second submodule narrowed clean, checked green, and still
# carried that submodule's future. `PIN` and `TIMEW_GIT` are both overridable, so
# "timewarrior has one submodule today" is not a property of this script.
sm_list=$(mktemp) || { echo "cannot create a scratch file" >&2; exit 1; }
git -C "$STAGE/repo" ls-tree -r HEAD > "$sm_list"
[ -s "$sm_list" ] || { echo "ls-tree produced nothing; the pin has no tree" >&2; exit 1; }
# A file rather than a pipe: `narrow_to_head` exits on failure, and inside a pipeline
# that would end a subshell while the script carried on.
while read -r _mode type _oid sm_path; do
    [ "$type" = commit ] || continue
    narrow_to_head "$STAGE/repo/$sm_path"
done < "$sm_list"
rm -f "$sm_list"

# Three-valued, because check-history.sh is: 1 is "the statement is false", 2 is "the
# check could not make it". Collapsing them would print the false-statement sentence
# for a missing repository or a configured alternate.
sh "$SCRIPT_DIR/check-history.sh" "$ROOT" "$PIN"
case $? in
    0) ;;
    1) echo "the staged repository carries git the pin cannot reach; refusing to stage" >&2; exit 1 ;;
    *) echo "the history check could not run; refusing to stage" >&2; exit 1 ;;
esac

echo "=== explore: the counterexample is recorded fresh, in the container ==="
# The work dir lives IN the stage (mounted at the identical absolute path) so the
# report's `case` and `replay` fields name paths that exist in the agent's world.
# The state dir stays container-local: it is the directory under observation, and
# its syscall semantics must not ride a virtiofs mount. The controls verify this
# wiring empirically before any agent runs.
set +e
docker run --rm --network none \
    -v "$STAGE:$STAGE" \
    -e STAGE="$STAGE" \
    -e OPERATION="$OPERATION" \
    -e TIMEWARRIORDB=/tmp/loop-state \
    "$IMAGE" sh -eu -c '
        cp -r "$STAGE/repo" /tmp/src
        cmake -S /tmp/src -B /tmp/build -DCMAKE_BUILD_TYPE=Release >/dev/null
        cmake --build /tmp/build -j"$(nproc)" >/dev/null
        mkdir -p /tmp/loop-bin /tmp/loop-state
        cp /tmp/build/src/timew /tmp/loop-bin/timew
        export PATH="/tmp/loop-bin:$PATH"
        exec "$STAGE/.harness/sideeye" explore \
            --state /tmp/loop-state \
            --setup "$STAGE/define/setup.sh" \
            --operation "$OPERATION" \
            --check "$STAGE/define/check.sh" \
            --shim "$STAGE/.harness/libsideeye_shim.so" \
            --work "$STAGE/work" \
            --json "$STAGE/report.json" \
            --oracle /usr/bin/strace
    ' > "$RESULTS/explore.txt" 2>&1
rc=$?
set -e

CASE="$STAGE/work/cases/000001.json"
# Explicit checks, not assert (assert vanishes under PYTHONOPTIMIZE).
if python3 -c '
import json, sys
r = json.load(open(sys.argv[1])); c = json.load(open(sys.argv[2]))
if r["verdict"] != "FAIL": sys.exit("verdict: %s" % r["verdict"])
if c.get("schema") != "sideeye/case" or c.get("ops_total", 0) <= 0: sys.exit("bad case")
# The wiring the whole experiment rests on: the report must name the case at a path
# that is real in the agent world (the identical-path mount), and carry a replay command.
if r.get("case") != sys.argv[2]: sys.exit("report names case %r, staged at %r" % (r.get("case"), sys.argv[2]))
if not r.get("replay", "").startswith("sideeye replay "): sys.exit("report carries no replay command: %r" % r.get("replay"))
' "$STAGE/report.json" "$CASE" && [ "$rc" = "1" ]; then
    echo "ok   explore: FAIL (exit 1), case saved, report names in-stage paths"
else
    echo "FAIL explore: expected exit 1 + verdict FAIL + a saved case (got exit $rc)" >&2
    sed 's/^/     | /' "$RESULTS/explore.txt" | tail -12 >&2
    exit 1
fi
K=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["k"])' "$CASE")
OPS=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["ops_total"])' "$CASE")
echo "case: k=$K of $OPS operations"

# The exploration's console output and working artifacts stay out of the agent's
# world: the input set is the report, not the trace. Only the case survives in place.
mv "$STAGE/work" "$RESULTS/explore-work"
mkdir -p "$STAGE/work/cases"
cp "$RESULTS/explore-work/cases/000001.json" "$CASE"

echo "=== bake the re-check button ($VARIANT) and seal the stage ==="
if [ "$VARIANT" = "mcp" ]; then
    BUTTON="$STAGE/build.sh"
    sed -e "s|@STAGE@|$STAGE|g" -e "s|@IMAGE@|$IMAGE|g" "$SCRIPT_DIR/build.sh.in" > "$BUTTON"
    # The client-side server config lives at the ROOT, outside the stage: the agent
    # never needs to read it, and it is not part of the sealed input set.
    python3 - "$STAGE" "$IMAGE" "$ROOT/mcp.json" <<'PY'
import json, sys
stage, image, out = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = {"mcpServers": {"sideeye": {"command": "docker", "args": [
    "run", "-i", "--rm", "--network", "none",
    "-v", "%s:%s" % (stage, stage),
    "-e", "SIDEEYE_MCP_ROOT=%s" % stage,
    "-e", "SIDEEYE_MCP_SHIM=%s/.harness/libsideeye_shim.so" % stage,
    "-e", "SIDEEYE_MCP_ORACLE=/usr/bin/strace",
    "-e", "SIDEEYE_MCP_WORK=/tmp/mcp-work",
    # #266: the staged cases carry define.state=/tmp/loop-state, which is outside
    # the stage root. Replay confines the case's state to SIDEEYE_MCP_STATE_ROOT
    # (default: the root), so the destruction range is widened to /tmp explicitly —
    # the root itself stays narrow.
    "-e", "SIDEEYE_MCP_STATE_ROOT=/tmp",
    "-e", "SIDEEYE_MCP_CHILD_ENV=TIMEWARRIORDB",
    "-e", "TIMEWARRIORDB=/tmp/loop-state",
    "-e", "PATH=%s/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" % stage,
    image, "%s/.harness/sideeye" % stage, "mcp"]}}}
json.dump(cfg, open(out, "w"), indent=1)
PY
else
    BUTTON="$STAGE/replay.sh"
    sed -e "s|@STAGE@|$STAGE|g" -e "s|@IMAGE@|$IMAGE|g" "$SCRIPT_DIR/replay.sh.in" > "$BUTTON"
fi
chmod +x "$BUTTON"
# The plumbing must stay bug-blind. Scanned: the generated button script (the
# checker legitimately names undo — it IS the declared invariant; mcp.json is
# generated too but lives outside the stage and carries only wiring). Not
# scanned: the prompt files, which are committed and reviewed as text, and whose
# word "order" (as in "in order to") would false-positive here.
if grep -qiE 'undo|rename|order' "$BUTTON"; then
    echo "$BUTTON contains finding vocabulary; refusing to stage it" >&2
    exit 1
fi

# The protocol facts finalize will cite, kept beside the seal (not agent-visible,
# not secret — the seal holds only copies of what the stage already shows).
# `history` is here so a run's own record says which shape of stage produced it. The
# #62 witness run — the one whose `git branch -a` motivated the narrowing — was
# recorded before this existed, and without the key a run from either side of the
# change reads identically. The apparatus alters what the agent works in, so results
# across it are not obviously commensurable.
python3 -c '
import json, sys
json.dump({"pin": sys.argv[1], "image": sys.argv[2], "case_k": int(sys.argv[3]),
           "case_ops_total": int(sys.argv[4]), "operation": sys.argv[6],
           "history": "narrowed-to-pin"},
          open(sys.argv[5], "w"), indent=1)
' "$PIN" "$IMAGE" "$K" "$OPS" "$SEAL/protocol.json" "$OPERATION"

(cd "$STAGE" && find . -type f ! -path "./repo/*" | LC_ALL=C sort) > "$SEAL/filelist"
(cd "$STAGE" && tar cf - -T "$SEAL/filelist") | (cd "$SEAL/files" && tar xf -)
(cd "$STAGE" && xargs shasum -a 256 < "$SEAL/filelist") > "$SEAL/manifest.sha256"
# A seal over nothing would verify anything — and a count alone admits a
# one-in-one-out swap. Pin the exact expected inventory, not its size.
if [ "$VARIANT" = "mcp" ]; then
expected_filelist='./.harness/libsideeye_shim.so
./.harness/sideeye
./build.sh
./define/check.sh
./define/setup.sh
./report.json
./work/cases/000001.json'
else
expected_filelist='./.harness/libsideeye_shim.so
./.harness/sideeye
./define/check.sh
./define/setup.sh
./replay.sh
./report.json
./work/cases/000001.json'
fi
if [ "$(cat "$SEAL/filelist")" != "$expected_filelist" ]; then
    echo "sealed inventory drifted from the expected seven files:" >&2
    printf '%s\n' "$expected_filelist" | diff - "$SEAL/filelist" >&2 || true
    exit 1
fi
n_sealed=$(grep -c . "$SEAL/manifest.sha256")

echo ""
echo "staged: $STAGE ($VARIANT variant)"
echo "sealed: $n_sealed files -> $SEAL/manifest.sha256"
echo "results will land in: $RESULTS"
if [ "$VARIANT" = "mcp" ]; then
    echo "next: judge.sh eval --root $ROOT --mode neg   (control: unfixed must FAIL)"
    echo "      judge.sh eval --root $ROOT --mode pos   (control: known patch must PASS)"
    echo "      contrast-mcp.sh $ROOT                   (control: the MCP channel itself)"
    echo "      run-agent-mcp.sh $ROOT                  (only after all three hold)"
else
    echo "next: judge.sh eval --root $ROOT --mode neg   (control: unfixed must FAIL)"
    echo "      judge.sh eval --root $ROOT --mode pos   (control: known patch must PASS)"
    echo "      run-agent.sh $ROOT                      (only after both controls hold)"
fi
