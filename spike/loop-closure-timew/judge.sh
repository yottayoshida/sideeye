#!/bin/sh
# The judge for the loop-closure experiment. Four subcommands, one discipline:
# nothing the agent can edit is trusted.
#
#   judge.sh eval --root <root> --mode neg|pos|run
#       Verify the stage against the sealed manifest, RESTORE every non-repo file
#       from the seal (recording what differed), rebuild timewarrior from the
#       stage's repo/ tree only, and measure three things in one --network none
#       container: the functional (non-degeneracy) gate, then the replay of the
#       sealed case with a fresh state. Emits <mode>-verdict.json; for the two
#       controls it also enforces the expected outcome and exits nonzero when the
#       control does not hold (so a broken apparatus stops the experiment before
#       any agent runs — the mutual contrast is the red for these checks):
#         neg  unpatched tree  -> replay must FAIL (reproduce), functional must pass
#         pos  known patch     -> replay must PASS (leg-C predicate), functional must pass
#         run  the agent's tree -> no expectation; the verdict is the measurement
#
#   judge.sh secondary --root <root> --mode neg|pos|run
#       The secondary observations DESIGN §17 cites beside the three gates (#64): a
#       full exploration of the tree under the sealed define (every crash world, not
#       only the one the case names) and the four upstream C++ suites run 1 counted
#       (UPSTREAM_SUITES below). Verifies the stage against the seal WITHOUT restoring
#       — restoring is eval's job, and eval's first restore is the only record of what
#       the agent changed outside repo/ — then rebuilds from repo/ as eval does and
#       measures both in one --network none container. Emits <mode>-secondary.json.
#       The two controls carry expectations and exit nonzero when they do not hold;
#       --mode run refuses until both controls have held on this stage. Evidence, not
#       a gate: loop_closed stays the three gates.
#
#   judge.sh audit --root <root> --transcript <stream-json file> [--allow-mcp <server>]
#       Enumerate every tool call the agent made. Network reach or a read into
#       this workspace voids the run (soft seal, hard void — the limitation is
#       documented in the BUILDLOG). --allow-mcp names ONE trusted MCP server
#       (the mcp variant's sideeye server); its mcp__<server>__* tools are the
#       agent's legitimate re-check surface, every other mcp__* stays a void.
#       Emits audit.json; exits nonzero on void.
#
#   judge.sh finalize --root <root>
#       Assemble manifest.json from both control verdicts, the run verdict, the
#       audit, and the agent metadata. Any missing required field makes THIS
#       command exit nonzero — the record's completeness rides the exit code,
#       not the author's diligence.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SIDEEYE_REPO=${SIDEEYE_REPO:-$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)}
IMAGE=${IMAGE:-sideeye-loop-timew:latest}
PATCH="$SIDEEYE_REPO/spike/timew-undo-ordering.patch"
# The upstream suites the secondary observation runs: the four C++ test executables run 1
# counted (BUILDLOG 2026-08-13; the bash launcher test/AtomicFile.t also ran there, errored
# on a path it hardcodes, and was not counted). Built one target at a time: test/ is
# EXCLUDE_FROM_ALL, and the `timew_test` aggregate depends on `doc`, which this image
# cannot build. The other seven C++ suites in test/CMakeLists.txt were not in run 1's count
# either, and the python/bash .t suites (undo.t among them) look for an in-tree src/timew;
# none of those is here. This is the slice run 1 counted, not the target's whole suite.
UPSTREAM_SUITES="AtomicFileTest data.t Datafile.t TagInfoDatabase.t"

usage() { awk 'NR==1{next} /^#/{print;next} {exit}' "$0" >&2; exit 2; }

[ $# -gt 0 ] || usage
CMD=$1; shift
ROOT=""; MODE=""; TRANSCRIPT=""; ALLOW_MCP=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT=$2; shift 2 ;;
        --mode) MODE=$2; shift 2 ;;
        --transcript) TRANSCRIPT=$2; shift 2 ;;
        --allow-mcp) ALLOW_MCP=$2; shift 2 ;;
        *) echo "unknown argument: $1" >&2; usage ;;
    esac
done
[ -n "$ROOT" ] || usage
STAGE="$ROOT/stage"
SEAL="$ROOT/seal"
RESULTS="$SIDEEYE_REPO/spike/runs/$(basename "$ROOT")"
mkdir -p "$RESULTS"

stamp() { # $1 = label; writes $RESULTS/<label>-started, the floor for this run's records
    date -u +%FT%TZ > "$RESULTS/$1-started"
}

restore_and_diff() { # $1 = mode, $2 = restore|check; writes $RESULTS/<mode>-stage-diff.json
                     # (restore) or $RESULTS/<mode>-stage-check.json (check)
    # `check` compares and records but never copies: the secondary observation uses it, because
    # the first restore of a stage is the only record of what the agent changed outside repo/,
    # and that record belongs to eval (#64). Its record has its own name and no `restored`
    # field, so nothing reading *-stage-diff.json can mistake it for a restore that found nothing.
    out="$RESULTS/$1-stage-diff.json"
    [ "$2" = check ] && out="$RESULTS/$1-stage-check.json"
    python3 - "$STAGE" "$SEAL" "$out" "$2" <<'PY'
import hashlib, json, os, shutil, sys

stage, seal, out_path, action = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
if action not in ("restore", "check"):
    sys.exit("restore_and_diff: action must be restore or check, got %r" % action)

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

manifest = {}
with open(os.path.join(seal, "manifest.sha256")) as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        digest, rel = line.split(None, 1)
        manifest[rel.lstrip("*")] = digest  # shasum may mark binary mode with *

modified, missing, restored = [], [], []
for rel, digest in sorted(manifest.items()):
    cur = os.path.join(stage, rel)
    pristine = os.path.join(seal, "files", rel)
    if not os.path.exists(cur):
        missing.append(rel)
    elif sha256(cur) != digest:
        modified.append(rel)
    else:
        continue
    if action == "check":
        continue
    # Restore from the seal, then re-verify: a restore that silently failed would
    # let a doctored checker decide the verdict.
    os.makedirs(os.path.dirname(cur), exist_ok=True)
    shutil.copy2(pristine, cur)
    if sha256(cur) != digest:
        sys.exit("restore failed for %s: hash still differs from the seal" % rel)
    restored.append(rel)

extra = []
for dirpath, dirnames, filenames in os.walk(stage):
    rel_dir = os.path.relpath(dirpath, stage)
    if rel_dir == "repo" or rel_dir.startswith("repo" + os.sep):
        dirnames[:] = []
        continue
    for name in filenames:
        rel = os.path.join(".", os.path.relpath(os.path.join(dirpath, name), stage))
        if rel not in manifest:
            extra.append(rel)

diff = {"modified": modified, "missing": missing, "extra": sorted(extra)}
if action == "restore":
    diff["restored"] = restored
json.dump(diff, open(out_path, "w"), indent=1)
print(json.dumps(diff))
PY
}

cmd_eval() {
    case "$MODE" in neg|pos|run) ;; *) echo "--mode must be neg, pos or run" >&2; exit 2 ;; esac
    [ -f "$SEAL/manifest.sha256" ] || { echo "no seal at $SEAL — run stage.sh first" >&2; exit 1; }
    # The replay gate is imported after the container has built and replayed; a missing
    # file would cost those minutes before an ImportError. Refuse here instead (#65).
    [ -f "$SIDEEYE_REPO/spike/replay_gate.py" ] || { echo "replay gate not found: $SIDEEYE_REPO/spike/replay_gate.py" >&2; exit 1; }
    if [ "$MODE" = "pos" ]; then
        [ -f "$PATCH" ] || { echo "known patch not found: $PATCH" >&2; exit 1; }
    fi

    echo "=== $MODE: verify against the seal, restore what differs ==="
    restore_and_diff "$MODE" restore
    if [ "$MODE" != "run" ]; then
        python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
if d["modified"] or d["missing"] or d["extra"]:
    sys.exit("controls must run on a pristine stage; found %r" % d)
' "$RESULTS/$MODE-stage-diff.json"
    fi

    echo "=== $MODE: rebuild from repo/ only; functional gate; replay the sealed case ==="
    # The operation comes from the seal, not a second hand-written copy: the
    # functional gate must drive the same command the case records.
    OPERATION=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["operation"])' "$SEAL/protocol.json")
    set -- run --rm --network none \
        -v "$STAGE:$STAGE" -v "$RESULTS:$RESULTS" \
        -e STAGE="$STAGE" -e RESULTS="$RESULTS" -e MODE="$MODE" \
        -e OPERATION="$OPERATION"
    if [ "$MODE" = "pos" ]; then
        set -- "$@" -v "$PATCH:/tmp/fix.patch:ro"
    fi
    # A record older than this stamp is not this run's (#64 review): the container runs
    # under `sh -eu`, so a build that fails writes nothing, and the verdict below would
    # otherwise read the previous run's files and call a broken apparatus green.
    stamp "$MODE-eval"
    set +e
    docker "$@" "$IMAGE" sh -eu -c '
        cp -r "$STAGE/repo" /tmp/src
        if [ "$MODE" = "pos" ]; then git -C /tmp/src apply /tmp/fix.patch; fi
        cmake -S /tmp/src -B /tmp/build -DCMAKE_BUILD_TYPE=Release >/dev/null
        cmake --build /tmp/build -j"$(nproc)" >/dev/null
        mkdir -p /tmp/loop-bin
        cp /tmp/build/src/timew /tmp/loop-bin/timew
        export PATH="/tmp/loop-bin:$PATH"

        # Non-degeneracy gate, in a normal (crash-free) world: seed, add, undo.
        # A fix that lobotomizes the feature to silence the checker fails here.
        fstatus=fail
        if ( export TIMEWARRIORDB=/tmp/func-state && mkdir -p /tmp/func-state \
             && sh "$STAGE/define/setup.sh" \
             && $OPERATION >/dev/null \
             && timew undo >/dev/null \
             && timew export > "$RESULTS/$MODE-func-export.json" ); then fstatus=ran; fi
        printf "%s\n" "$fstatus" > "$RESULTS/$MODE-func-status"

        # The replay, from a fresh state at the path the case pins.
        export TIMEWARRIORDB=/tmp/loop-state
        mkdir -p /tmp/loop-state
        rrc=0
        "$STAGE/.harness/sideeye" replay "$STAGE/work/cases/000001.json" \
            --shim "$STAGE/.harness/libsideeye_shim.so" \
            --work /tmp/judge-work \
            --oracle /usr/bin/strace \
            --json "$RESULTS/$MODE-replay.json" \
            > "$RESULTS/$MODE-replay.txt" 2>&1 || rrc=$?
        printf "%s\n" "$rrc" > "$RESULTS/$MODE-replay-rc"
    ' > "$RESULTS/$MODE-container.log" 2>&1
    container_rc=$?
    set -e

    python3 - "$RESULTS" "$MODE" "$SEAL/protocol.json" "$container_rc" "$SIDEEYE_REPO/spike" <<'PY'
import json, os, sys

results, mode, proto_path, container_rc = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
# The replay gate is spike/replay_gate.py, shared with dogfood-timew-replay.sh's leg C
# (#65). stdin-fed python has '' as sys.path[0], so the directory is passed in.
sys.path.insert(0, sys.argv[5])
from replay_gate import gate
proto = json.load(open(proto_path))
started = os.path.getmtime(os.path.join(results, "%s-eval-started" % mode))

def read(name, parse=False):
    # A file from before this run's stamp is a previous run's: absent, for this verdict.
    p = os.path.join(results, "%s-%s" % (mode, name))
    if not os.path.exists(p) or os.path.getmtime(p) < started:
        return None
    with open(p) as f:
        return json.load(f) if parse else f.read().strip()

rrc = read("replay-rc")
verdict = {
    "mode": mode,
    "container_rc": container_rc,
    "stage_diff": json.load(open(os.path.join(results, "%s-stage-diff.json" % mode))),
    # Differs from replay.gate == "build_failed" in one corner only: the build
    # finished but sideeye wrote no JSON. Kept to name that corner.
    "build_ok": rrc is not None,
}

replay = {"gate": "build_failed"}
rj = read("replay.json", parse=True)
if rj is not None and rrc is not None:
    rrc = int(rrc)
    replay = {
        "rc": rrc,
        "verdict": rj.get("verdict"),
        "unknown_reason": rj.get("unknown_reason"),
        "explored": rj.get("explored"),
        "crash_points": rj.get("crash_points"),
        "ops_total": proto["case_ops_total"],
        "crash_point": (rj.get("earliest") or {}).get("crash_point"),
    }
    replay["gate"], _ = gate(rj, rrc, proto["case_ops_total"])
verdict["replay"] = replay

func = {"gate": "fail", "detail": "functional sequence did not complete"}
if read("func-status") == "ran":
    intervals = read("func-export.json", parse=True) or []
    tags = [set(iv.get("tags", [])) for iv in intervals]
    beta_gone = not any("beta" in t for t in tags)
    alpha_kept = sum(1 for t in tags if "alpha" in t) == 1
    if beta_gone and alpha_kept and len(intervals) == 1:
        func = {"gate": "pass"}
    else:
        func = {"gate": "fail",
                "detail": "after undo, export was %r" % [sorted(t) for t in tags]}
verdict["func"] = func

expected = None
if mode == "neg":
    # Not any FAIL: THE failure. A checker broken for an unrelated reason also
    # exits FAIL; pinning the reproduced crash point to the case's k keeps a
    # differently-broken apparatus from opening the agent gate. The container's own
    # exit is part of the expectation: a build that failed wrote nothing this run.
    expected = (container_rc == 0 and replay["gate"] == "fail_reproduced" and func["gate"] == "pass"
                and replay.get("crash_point") == proto["case_k"])
elif mode == "pos":
    expected = container_rc == 0 and replay["gate"] == "pass" and func["gate"] == "pass"
verdict["expectation_met"] = expected

out = os.path.join(results, "%s-verdict.json" % mode)
json.dump(verdict, open(out, "w"), indent=1)
print("%s: replay=%s func=%s%s" % (mode, replay["gate"], func["gate"],
      "" if expected is None else " expectation_met=%s" % expected))
if expected is False:
    sys.exit("control %s did not hold — fix the apparatus before running any agent" % mode)
PY
}

cmd_secondary() {
    case "$MODE" in neg|pos|run) ;; *) echo "--mode must be neg, pos or run" >&2; exit 2 ;; esac
    [ -f "$SEAL/manifest.sha256" ] || { echo "no seal at $SEAL — run stage.sh first" >&2; exit 1; }
    [ -f "$SIDEEYE_REPO/spike/replay_gate.py" ] || { echo "replay gate not found: $SIDEEYE_REPO/spike/replay_gate.py" >&2; exit 1; }
    [ -f "$SIDEEYE_REPO/spike/suite_summary.py" ] || { echo "suite summary not found: $SIDEEYE_REPO/spike/suite_summary.py" >&2; exit 1; }
    if [ "$MODE" = "pos" ]; then
        [ -f "$PATCH" ] || { echo "known patch not found: $PATCH" >&2; exit 1; }
    fi
    if [ "$MODE" = "run" ]; then
        # Controls first, before anything touches the stage or a container: the run's
        # numbers are not read until the unpatched tree has failed and the known patch has
        # passed through this same subcommand (the mirror of run-agent.sh's gate on eval).
        python3 -c '
import json, sys
proto = json.load(open(sys.argv[1]))
for p in sys.argv[2:]:
    try:
        v = json.load(open(p))
    except (OSError, ValueError) as e:
        sys.exit("controls have not held: %s is missing or unreadable (%s) — run judge.sh secondary --mode neg and --mode pos first" % (p, e))
    if v.get("expectation_met") is not True:
        sys.exit("controls have not held: %s has expectation_met %r" % (p, v.get("expectation_met")))
    # "on the same stage" is a claim about the seal, not about a directory name: the
    # control carries the protocol it ran against, and it must be the one this seal names.
    if v.get("protocol") != proto:
        sys.exit("controls have not held: %s was recorded against another stage (its protocol differs from %s)" % (p, sys.argv[1]))
' "$SEAL/protocol.json" "$RESULTS/neg-secondary.json" "$RESULTS/pos-secondary.json"
    fi

    echo "=== $MODE: verify against the seal (read only; eval restores, this never does) ==="
    restore_and_diff "$MODE" check
    python3 -c '
import json, sys
d = json.load(open(sys.argv[1])); mode = sys.argv[2]
if d["modified"] or d["missing"]:
    sys.exit("the stage differs from the seal (%r); run judge.sh eval --mode %s first — it restores, and records what the agent changed" % (d, mode))
if mode != "run" and d["extra"]:
    sys.exit("controls must run on a pristine stage; found extra files %r" % d["extra"])
' "$RESULTS/$MODE-stage-check.json" "$MODE"

    echo "=== $MODE: rebuild from repo/ only; full explore under the sealed define; upstream suites ==="
    OPERATION=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["operation"])' "$SEAL/protocol.json")
    set -- run --rm --network none \
        -v "$STAGE:$STAGE" -v "$RESULTS:$RESULTS" \
        -e STAGE="$STAGE" -e RESULTS="$RESULTS" -e MODE="$MODE" \
        -e OPERATION="$OPERATION" -e UPSTREAM_SUITES="$UPSTREAM_SUITES"
    if [ "$MODE" = "pos" ]; then
        set -- "$@" -v "$PATCH:/tmp/fix.patch:ro"
    fi
    stamp "$MODE-secondary"
    set +e
    docker "$@" "$IMAGE" sh -eu -c '
        cp -r "$STAGE/repo" /tmp/src
        if [ "$MODE" = "pos" ]; then git -C /tmp/src apply /tmp/fix.patch; fi
        cmake -S /tmp/src -B /tmp/build -DCMAKE_BUILD_TYPE=Release >/dev/null
        cmake --build /tmp/build -j"$(nproc)" >/dev/null
        mkdir -p /tmp/loop-bin
        cp /tmp/build/src/timew /tmp/loop-bin/timew
        export PATH="/tmp/loop-bin:$PATH"

        # The full exploration: every crash world under the sealed define, from a fresh
        # state at a container-local path (the state dir must not ride a mount) and a
        # work dir outside the stage (whose work/ is sealed).
        export TIMEWARRIORDB=/tmp/sec-state
        mkdir -p /tmp/sec-state
        erc=0
        "$STAGE/.harness/sideeye" explore \
            --state /tmp/sec-state \
            --setup "$STAGE/define/setup.sh" \
            --operation "$OPERATION" \
            --check "$STAGE/define/check.sh" \
            --shim "$STAGE/.harness/libsideeye_shim.so" \
            --work /tmp/sec-work \
            --json "$RESULTS/$MODE-full-explore.json" \
            --oracle /usr/bin/strace \
            > "$RESULTS/$MODE-full-explore.txt" 2>&1 || erc=$?
        printf "%s\n" "$erc" > "$RESULTS/$MODE-full-explore-rc"

        # The upstream suites, one target at a time, run from the build tree the way run 1
        # ran them. A build failure is recorded as such, never as a suite result.
        for suite in $UPSTREAM_SUITES; do
            if ! cmake --build /tmp/build --target "$suite" > "$RESULTS/$MODE-upstream-$suite-build.log" 2>&1; then
                printf "%s\n" build-failed > "$RESULTS/$MODE-upstream-$suite-rc"
                continue
            fi
            src=0
            (cd /tmp/build/test && "./$suite") > "$RESULTS/$MODE-upstream-$suite.txt" 2>&1 || src=$?
            printf "%s\n" "$src" > "$RESULTS/$MODE-upstream-$suite-rc"
        done
    ' > "$RESULTS/$MODE-secondary-container.log" 2>&1
    container_rc=$?
    set -e

    python3 - "$RESULTS" "$MODE" "$SEAL/protocol.json" "$container_rc" "$SIDEEYE_REPO/spike" "$UPSTREAM_SUITES" <<'PY'
import json, os, sys

results, mode, proto_path, container_rc = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
sys.path.insert(0, sys.argv[5])
from replay_gate import gate
import suite_summary
suites = sys.argv[6].split()
proto = json.load(open(proto_path))
started = os.path.getmtime(os.path.join(results, "%s-secondary-started" % mode))

def read(name, parse=False):
    # A file from before this run's stamp is a previous run's: absent, for this verdict.
    # A file this run wrote but did not finish (a report cut off mid-write) is absent too,
    # not a traceback: the verdict then says no_report or build_failed, which is the truth.
    p = os.path.join(results, "%s-%s" % (mode, name))
    if not os.path.exists(p) or os.path.getmtime(p) < started:
        return None
    with open(p) as f:
        if not parse:
            return f.read().strip()
        try:
            return json.load(f)
        except ValueError:
            return None

verdict = {
    "mode": mode,
    "container_rc": container_rc,
    # The seal this observation ran against; --mode run compares its controls to this.
    "protocol": proto,
    "stage_check": json.load(open(os.path.join(results, "%s-stage-check.json" % mode))),
}

# The full exploration, judged by the same gate as a replay, with the world count a full
# run has: every crash point plus the baseline. crash_points stays pinned to the case's
# ops_total the way eval pins it: a setup that silently did nothing would explore a
# handful of worlds and PASS, and must not read as the fixed tree passing.
erc = read("full-explore-rc")
full = {"gate": "build_failed"}
rj = read("full-explore.json", parse=True)
if erc is not None and rj is None:
    # The exploration ran (its rc is this run's) and wrote no report: named apart from
    # a build that never reached it.
    full = {"gate": "no_report", "rc": int(erc)}
if rj is not None and erc is not None:
    erc = int(erc)
    g, detail = gate(rj, erc, proto["case_ops_total"], proto["case_ops_total"] + 1)
    full = {
        "rc": erc,
        "verdict": rj.get("verdict"),
        "unknown_reason": rj.get("unknown_reason"),
        "explored": rj.get("explored"),
        "crash_points": rj.get("crash_points"),
        "ops_total": proto["case_ops_total"],
        "crash_point": (rj.get("earliest") or {}).get("crash_point"),
        "gate": g,
    }
    if detail:
        full["gate_detail"] = detail
verdict["full_explore"] = full

# The upstream suites, read and judged by spike/suite_summary.py (the summary line, the
# under-run line, the plan recorded and not judged; its --selftest runs in acceptance).
upstream = {}
all_pass = bool(suites)
for suite in suites:
    src = read("upstream-%s-rc" % suite)
    text = read("upstream-%s.txt" % suite)
    entry = {"rc": src}
    if src is None or src == "build-failed" or text is None:
        entry["gate"] = "fail"
        entry["detail"] = "the suite did not build" if src == "build-failed" else "the suite did not run"
        upstream[suite] = entry
        all_pass = False
        continue
    src = int(src)
    entry["rc"] = src
    parsed = suite_summary.parse(text)
    entry.update(parsed)
    g, detail = suite_summary.gate(src, parsed)
    entry["gate"] = g
    if detail:
        entry["detail"] = detail
    all_pass = all_pass and g == "pass"
    upstream[suite] = entry
verdict["upstream"] = {"suites": upstream, "gate": "pass" if all_pass else "fail"}

expected = None
n = proto["case_ops_total"]
if mode == "neg":
    # THE failure, at the case's crash point, over every world (a FAIL still explores
    # them all: 25 of 25 on the witness stage), with the counted suites green — the
    # unpatched tree reproduces the finding and the suites run 1 counted do not catch it.
    # The container's own exit is part of it: a build that failed wrote nothing this run.
    expected = (container_rc == 0 and full["gate"] == "fail_reproduced"
                and full.get("crash_point") == proto["case_k"]
                and full.get("crash_points") == n and full.get("explored") == n + 1
                and verdict["upstream"]["gate"] == "pass")
elif mode == "pos":
    expected = container_rc == 0 and full["gate"] == "pass" and verdict["upstream"]["gate"] == "pass"
verdict["expectation_met"] = expected

out = os.path.join(results, "%s-secondary.json" % mode)
json.dump(verdict, open(out, "w"), indent=1)
print("%s: container_rc=%d full_explore=%s upstream=%s%s" % (mode, container_rc, full["gate"],
      verdict["upstream"]["gate"], "" if expected is None else " expectation_met=%s" % expected))
if expected is False:
    sys.exit("secondary control %s did not hold — fix the apparatus before reading any run" % mode)
PY
}

cmd_audit() {
    [ -n "$TRANSCRIPT" ] || usage
    [ -f "$TRANSCRIPT" ] || { echo "transcript not found: $TRANSCRIPT" >&2; exit 1; }
    python3 - "$TRANSCRIPT" "$RESULTS/audit.json" "$STAGE" "$SIDEEYE_REPO" "$ALLOW_MCP" <<'PY'
import json, re, sys

transcript, out_path, stage, repo = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
# The mcp variant's one trusted server: its tools are the agent's legitimate
# re-check surface. Everything else under mcp__ stays a void by name.
allow_prefix = ("mcp__%s__" % sys.argv[5]) if len(sys.argv) > 5 and sys.argv[5] else None

# The declared void condition — one network reach, or one read into this
# repository's world (the repo holds the answers: buildlog, known patch) — is
# enforced per escape channel, against EVERY tool call, not only Bash:
#   by NAME   tools that reach the network by construction or delegate work to
#             a context this transcript does not record (an allowlist is not a
#             menu: the harness presents its full tool set regardless)
#   by TEXT   network markers in Bash commands (the execution surface; matching
#             file-edit payloads instead would false-positive on URLs inside
#             the target's own source)
#   by PATH   the sideeye repo or the user's config dir in any tool input
#             (Read/Grep/Glob are the read-leak channel)
#   by MOUNT  docker invocations that drop --network none or bind a source
#             outside the stage (a mount makes the filesystem seal moot)
# These sets deliberately duplicate the launchers' ALLOWED / DISALLOWED
# (run-agent.sh and run-agent-mcp.sh): the judge does not read what a launcher
# wrote. Keep them in step by hand.
ALLOWED = {"Bash", "Read", "Edit", "Write", "Glob", "Grep"}
UNSEALED = {"WebFetch", "WebSearch", "Task", "Agent", "Workflow",
            "SendMessage", "PushNotification", "RemoteTrigger",
            "ScheduleWakeup", "CronCreate", "CronDelete"}
NETWORK = re.compile(
    r"\b(curl|wget|nc|ncat|netcat|ssh|scp|sftp|telnet|dig|nslookup|gh)\b"
    r"|\bgit\s+(?:-[^\s]+\s+)*(fetch|pull|push|clone|ls-remote)\b"
    r"|\b(pip3?|npm|apt(-get)?|brew)\s+(install|add|update|upgrade)\b"
    r"|https?://")
DOCKER = re.compile(r"\bdocker\s+(run|exec|create)\b")
MOUNT_SRC = re.compile(r"(?:-v|--volume)[=\s]+([^:\s]+):|--mount[=\s]+\S*?source=([^,\s]+)")

tool_calls = []
def walk(node):
    if isinstance(node, dict):
        if node.get("type") == "tool_use":
            tool_calls.append({"name": node.get("name"), "input": node.get("input", {})})
        for v in node.values():
            walk(v)
    elif isinstance(node, list):
        for v in node:
            walk(v)

with open(transcript) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            walk(json.loads(line))
        except json.JSONDecodeError:
            continue

if not tool_calls:
    json.dump({"verdict": "unauditable", "tool_calls": 0}, open(out_path, "w"), indent=1)
    sys.exit("audit: the transcript holds no tool calls — nothing-to-see is not clean")

network_hits, context_hits, docker_hits, unsealed_hits = [], [], [], []
off_allowlist, unresolved_mounts = [], []
mcp_calls = 0
for call in tool_calls:
    name = call["name"] or ""
    text = json.dumps(call["input"], ensure_ascii=False)
    if name.startswith("mcp__"):
        if allow_prefix and name.startswith(allow_prefix):
            mcp_calls += 1  # the trusted server; its inputs still pass the path checks below
        else:
            unsealed_hits.append({"tool": name, "input": call["input"]})
    elif name in UNSEALED:
        unsealed_hits.append({"tool": name, "input": call["input"]})
    elif name not in ALLOWED:
        off_allowlist.append(name)  # local-only tool outside the allowlist: recorded, not void
    if repo in text or "/.claude/" in text or "~/.claude" in text:
        context_hits.append({"tool": name, "input": call["input"]})
    if name == "Bash":
        cmd = call["input"].get("command", "")
        if NETWORK.search(cmd):
            network_hits.append(cmd)
        if DOCKER.search(cmd):
            # A transcript holds shell TEXT, not resolved paths: an absolute
            # mount source outside the stage is a judged escape; a source that
            # rides a variable ("$PWD") cannot be decided statically and is
            # recorded as unresolved, not voided (the real clean run mounts
            # "$PWD:$PWD" from inside the stage).
            escaped = "--network none" not in cmd
            for m in MOUNT_SRC.finditer(cmd):
                src = (m.group(1) or m.group(2) or "").lstrip("\"'")
                if src.startswith("/") and not src.startswith(stage):
                    escaped = True
                elif "$" in src:
                    unresolved_mounts.append(cmd)
            if escaped:
                docker_hits.append(cmd)

verdict = "clean"
if network_hits or context_hits or docker_hits or unsealed_hits:
    verdict = "void"
audit = {
    "verdict": verdict,
    "tool_calls": len(tool_calls),
    "bash_calls": sum(1 for c in tool_calls if c["name"] == "Bash"),
    "network_hits": network_hits,
    "context_hits": context_hits,
    "docker_hits": docker_hits,
    "unsealed_tool_hits": unsealed_hits,
    "off_allowlist": sorted(set(off_allowlist)),
    "unresolved_mounts": sorted(set(unresolved_mounts)),
    "allowed_mcp_calls": mcp_calls,
}
json.dump(audit, open(out_path, "w"), indent=1)
print("audit: %s (%d tool calls, %d bash)" % (verdict, audit["tool_calls"], audit["bash_calls"]))
if verdict == "void":
    sys.exit("the run is void: the seal was breached (see audit.json)")
PY
}

cmd_finalize() {
    python3 - "$RESULTS" "$SEAL/protocol.json" "$ROOT" <<'PY'
import json, os, sys

results, proto_path, root = sys.argv[1], sys.argv[2], sys.argv[3]

def need(name):
    p = os.path.join(results, name)
    if not os.path.exists(p):
        sys.exit("finalize: missing required record %s — the manifest cannot be assembled" % name)
    return json.load(open(p))

if not os.path.exists(proto_path):
    sys.exit("finalize: missing %s — stage.sh writes it at seal time" % proto_path)
manifest = {
    "protocol": json.load(open(proto_path)),
    "controls": {"neg": need("neg-verdict.json"), "pos": need("pos-verdict.json")},
    "run": need("run-verdict.json"),
    "audit": need("audit.json"),
    "agent": need("agent-meta.json"),
}
# The secondary observation (judge.sh secondary --mode run) is evidence beside the gates,
# not one of them (#64): carried when present, named as absent when not, never required.
secondary_path = os.path.join(results, "run-secondary.json")
if os.path.exists(secondary_path):
    manifest["run"]["secondary"] = json.load(open(secondary_path))
# An mcp-variant root (it carries mcp.json) has a third control: the channel
# itself. Its absence — or a contrast that did not hold — is an incomplete record.
if os.path.exists(os.path.join(root, "mcp.json")):
    manifest["controls"]["mcp_channel"] = need("mcp-contrast.json")

missing = []
if manifest["controls"]["neg"].get("expectation_met") is not True:
    missing.append("neg control did not hold")
if manifest["controls"]["pos"].get("expectation_met") is not True:
    missing.append("pos control did not hold")
if "mcp_channel" in manifest["controls"]:
    if manifest["controls"]["mcp_channel"].get("expectation_met") is not True:
        missing.append("mcp channel contrast did not hold")
    # "Through this surface" must be in the record, not assumed: an mcp-variant
    # run whose agent never called the trusted server would still pass the three
    # gates, and nothing else reads allowed_mcp_calls. Cross-check the variant
    # signals too — the root's mcp.json and the agent-meta must agree.
    if not manifest["audit"].get("allowed_mcp_calls"):
        missing.append("the agent never called the trusted MCP server (allowed_mcp_calls is 0/absent) — the surface did not carry this run")
    if manifest["agent"].get("variant") != "mcp":
        missing.append("root has mcp.json but agent-meta.variant is %r — the two variant signals disagree" % manifest["agent"].get("variant"))
for field in ("model", "cli_version", "prompt_sha256"):
    if not manifest["agent"].get(field):
        missing.append("agent.%s" % field)
if manifest["audit"].get("verdict") not in ("clean", "void"):
    missing.append("audit.verdict")
for field in ("replay", "func", "stage_diff"):
    if field not in manifest["run"]:
        missing.append("run.%s" % field)
if missing:
    sys.exit("finalize: incomplete record: %s" % "; ".join(missing))

closed = (manifest["audit"]["verdict"] == "clean"
          and manifest["run"]["replay"].get("gate") == "pass"
          and manifest["run"]["func"].get("gate") == "pass")
manifest["loop_closed"] = closed
out = os.path.join(results, "manifest.json")
json.dump(manifest, open(out, "w"), indent=1)
print("manifest: %s" % out)
print("loop_closed: %s" % closed)
print("  replay gate: %s" % manifest["run"]["replay"].get("gate"))
print("  func gate:   %s" % manifest["run"]["func"].get("gate"))
print("  audit:       %s" % manifest["audit"]["verdict"])
print("  agent edits outside repo/: %s" % (manifest["run"]["stage_diff"]["restored"] or "none"))
sec = manifest["run"].get("secondary")
print("  secondary:   %s" % ("full explore %s, upstream %s (evidence, not a gate)"
      % (sec["full_explore"].get("gate"), sec["upstream"].get("gate")) if sec
      else "absent (judge.sh secondary --mode run was not run; evidence, not a gate)"))
PY
}

case "$CMD" in
    eval) cmd_eval ;;
    secondary) cmd_secondary ;;
    audit) cmd_audit ;;
    finalize) cmd_finalize ;;
    *) usage ;;
esac
