#!/bin/sh
# B-group launcher (#84 sweep, extended for B2 by #619): one uniform protocol
# for every mechanically-selected target that reached the define stage. The
# define is a directory under defines-b/<target>/ (the 2026-08-16 group) or
# defines-b2/<target>/ (the post-v1.5 group) — the launcher takes the one that
# exists, so the corpus rows keep the argument they were measured under.
# setup.sh seeds state, reading the engine-provided $TOY_STATE; the operation is
# op.txt (one static command line the engine spawns directly, with the literal
# $TOY_STATE expanded per leg) or op.sh (the ADR 0007 fallback for an invocation
# the space-split contract cannot spell — it names its program by absolute
# path, ADR 0018's amendment); env.sh (sourced here) and expect-status.txt (the
# exit convention the target's documentation states) are optional. Judge config
# is L0-only by design — no checker — plus the strict oracle.
#
# Three legs, each recorded (docs/unknown-rate.md, the B2 run contract):
#   preflight --twice        the funnel instrument, never the verdict
#                            (preflight.txt; exit 0 accepted / 1 the two runs
#                            differ / 2 refused)
#   explore, default mode    report-wrappers.json, transcript-wrappers.txt
#   explore --observe syscalls   only when the first explore refused with the
#                            next_step that asks for that mode: report-syscalls.json
# The verdict is the LAST leg's: report.json and transcript.txt are copies of
# it (the manifest binds report.json by sha256), and legs.tsv beside them
# names each leg's mode, verdict, reason, report and sha256, which count.py
# check recomputes — a second leg without the first asking for it, a missing
# one when it did, or a report.json that is not the last leg's bytes, is
# refused there.
#
# With BGROUP_PREFLIGHT_ONLY set the launcher stops after the first leg and
# exits with preflight's status: that is how a define is tried while it is
# being authored (b2-preflight.sh), through the same reading of the define
# the sweep will use — exploring a candidate before the sweep would pre-empt
# the measurement, so authoring never reaches the second leg.
#
# The B rows of g1 ran preflight once and explore once under the only mode
# that existed; their first leg here is that protocol, and the --twice answer
# and any second leg are additions the tables print beside it.
#
# Usage: bgroup.sh <target> <artifact-dir>
set -u
t=${1:?target}; art=${2:?artifact dir}
SIDEEYE=${SIDEEYE:-/work/zig-out/bin/sideeye}
SHIM=${SHIM:-/work/zig-out/lib/libsideeye_shim.so}
defs=/work/spike/unknown-rate/defines-b/$t
[ -d "$defs" ] || defs=/work/spike/unknown-rate/defines-b2/$t
[ -x "$defs/setup.sh" ] || { echo "bgroup.sh: $t has no executable setup.sh under defines-b or defines-b2" >&2; exit 3; }
optpl=""
if [ -f "$defs/op.txt" ]; then
    [ "$(grep -c . "$defs/op.txt")" = 1 ] || {
        echo "bgroup.sh: $t op.txt must be exactly one non-empty line" >&2; exit 3; }
    optpl=$(head -n 1 "$defs/op.txt")
    [ -n "$optpl" ] || { echo "bgroup.sh: $t op.txt is empty" >&2; exit 3; }
elif [ ! -x "$defs/op.sh" ]; then
    echo "bgroup.sh: $t has neither op.txt nor executable op.sh" >&2; exit 3
fi
op_for() {
    if [ -n "$optpl" ]; then
        printf '%s' "$optpl" | sed "s|\$TOY_STATE|$1|g"
    else
        printf '%s' "$defs/op.sh"
    fi
}
# The exit status that counts as the operation completing. The first group's
# uniform protocol declared 0 for everyone and cookietool (exit 10, its deleted
# count) was refused on that declaration rather than on anything the target
# did; a define may now state its documented convention.
expect=""
if [ -f "$defs/expect-status.txt" ]; then
    expect=$(head -n 1 "$defs/expect-status.txt" | tr -d ' ')
    case "$expect" in ''|*[!0-9]*) echo "bgroup.sh: $t expect-status.txt is not a number" >&2; exit 3 ;; esac
fi
mkdir -p "$art" || exit 3
# Uniform scratch HOME: dotfile writes (hnb's ~/.hnbrc, and whatever a
# fresh target invents) land outside the repo and outside the judged state.
export HOME=/tmp/bgroup-home/$t
mkdir -p "$HOME" || exit 3
[ -f "$defs/env.sh" ] && . "$defs/env.sh"

proot=/tmp/bgroup-pre/$t
root=/tmp/bgroup/$t
root2=/tmp/bgroup-syscalls/$t
if [ -e "$proot" ] || [ -e "$root" ] || [ -e "$root2" ]; then
    echo "bgroup.sh: state root already exists — fresh container required" >&2; exit 3
fi

# run <subcommand> <state root> [flags]: the engine on this define. Everything
# a leg shares — the define, the shim, the oracle, the documented exit
# convention — is spelled once here; the flags are the leg's own.
run() {
    sub=$1; r=$2; shift 2
    "$SIDEEYE" "$sub" "$@" --state "$r/state" --setup "$defs/setup.sh" \
        --operation "$(op_for "$r/state")" --shim "$SHIM" --oracle /usr/bin/strace \
        --work "$r/work" ${expect:+--expect-status "$expect"}
}

# Funnel instrument first, in its own root. --twice observes a second run from
# the restored pre-state and compares: exit 0 equal, 1 differing (named paths),
# 2 refused. Recorded, never the verdict.
mkdir -p "$proot/state" || exit 3
run preflight "$proot" --twice > "$art/preflight.txt" 2>&1
prc=$?
echo "preflight exit=$prc" >> "$art/preflight.txt"
if [ -n "${BGROUP_PREFLIGHT_ONLY:-}" ]; then
    echo "bgroup/$t preflight exit=$prc"
    exit $prc
fi

# A report's verdict, reason and next_step, read as data. python3 is in every
# sweep image; the report is JSON and a grep over it would be a parser too.
read_report() {
    python3 - "$1" <<'PY'
import json, sys
try:
    r = json.load(open(sys.argv[1]))
except Exception:  # a missing or torn report: the leg produced nothing readable
    print("-\t-\t-")
    sys.exit(0)
print("\t".join([str(r.get("verdict", "-")), str(r.get("unknown_reason", "-") or "-"),
                 str(r.get("next_step", "") or "")]))
PY
}
sha_of() { sha256sum "$1" | cut -d' ' -f1; }
TAB=$(printf '\t')

legs=$art/legs.tsv
: > "$legs"

# leg <n> <mode> <state root> [explore flags]: one explore, its report and
# transcript named by mode, and its legs.tsv row. Leaves v / u / nstep (the
# report's verdict, reason, next_step) and rc for the caller; a leg whose
# report never appeared writes no row and says so.
leg() {
    n=$1; mode=$2; r=$3; shift 3
    mkdir -p "$r/state" || exit 3
    run explore "$r" "$@" --json "$art/report-$mode.json" > "$art/transcript-$mode.txt" 2>&1
    rc=$?
    final=$mode
    v=-; u=-; nstep=
    if [ -f "$art/report-$mode.json" ]; then
        IFS=$TAB read -r v u nstep <<EOF
$(read_report "$art/report-$mode.json")
EOF
        printf '%s\t%s\t%s\t%s\treport-%s.json\t%s\n' "$n" "$mode" "$v" "$u" "$mode" \
            "$(sha_of "$art/report-$mode.json")" >> "$legs"
    else
        echo "bgroup.sh: $t leg $n produced no report (exit $rc)" >&2
    fi
}

# Leg 1: the default observation mode.
leg 1 wrappers "$root"

# Leg 2: only when the engine's own next_step for leg 1 asks for the mode —
# matched on the opening of the `observe_syscalls` step (src/contract.zig),
# because the `syscalls_may_have_killed` step names the flag too, in a
# sentence that says the opposite. count.py's SYSCALLS_STEP is the same
# phrase, and spike/acceptance.sh holds all three copies to each other.
case "$v:$nstep" in
  UNKNOWN:*"Run explore or preflight again with --observe syscalls"*)
    leg 2 syscalls "$root2" --observe syscalls ;;
esac

# The verdict is the last leg's; the files the corpus names are copies of it.
[ -f "$art/report-$final.json" ] && cp "$art/report-$final.json" "$art/report.json"
[ -f "$art/transcript-$final.txt" ] && cp "$art/transcript-$final.txt" "$art/transcript.txt"
echo "bgroup/$t exit=$rc final=$final"
exit $rc
