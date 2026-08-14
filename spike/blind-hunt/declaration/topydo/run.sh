#!/bin/sh
# Seal B artifact (ADR 0012): the exploration runner. Committed at Seal B so
# that exploration can run FROM the Seal B commit in a clean working tree —
# verify-seals R1 requires the run manifest to pin head == Seal B and a clean
# worktree, so nothing this run needs may be added after the seal.
#
# Runs inside the pinned container (sideeye-blindhunt) with the repo mounted
# at /work. The host wrapper passes HEAD and worktree cleanliness in, because
# git is not in the image:
#
#   docker run --rm -v "$PWD:/work" \
#     -e HEAD="$(git rev-parse HEAD)" \
#     -e CLEAN="$(git status --porcelain | grep -q . && echo false || echo true)" \
#     sideeye-blindhunt sh /work/spike/blind-hunt/declaration/topydo/run.sh
#
# All eleven declared operations are explored, in the inventory's order. An
# operation the engine refuses (UNKNOWN / setup error) is a recorded result,
# not a failure of the runner — refusals feed the UNKNOWN-rate measurement
# (#84). Reports, stdout and any saved cases land in OUT on the mount.
#
# Date note (declaration.md): add/do stamp the current date, so recording and
# baseline must run on the same calendar day — do not start a run that will
# straddle midnight.
set -u

SIDEEYE=${SIDEEYE:-/work/zig-out/bin/sideeye}
SHIM=${SHIM:-/work/zig-out/lib/libsideeye_shim.so}
OUT=${OUT:-/work/spike/runs/blind-hunt-topydo}
HEAD=${HEAD:?pass HEAD=$(git rev-parse HEAD) from the host}
CLEAN=${CLEAN:?pass CLEAN=true|false from the host}

export HOME=/tmp/blind/home
mkdir -p "$HOME" || exit 2

# Refuse a pre-existing output directory, exactly like the state roots below:
# reusing OUT could mix reports and saved cases from different executions under
# one manifest, and a harness that silently overwrites is deciding what to keep.
if [ -e "$OUT" ]; then
    echo "run: output dir already exists: $OUT — give each run a fresh OUT" >&2
    exit 2
fi
mkdir -p "$OUT" || exit 2

here=/work/spike/blind-hunt/declaration/topydo

OPS="add append del dep-add dep-rm depri do ls postpone pri revert sort tag"

for op in $OPS; do
    root=/tmp/blind/hunt/$op
    # Refuse, never delete (the sweep harness precedent): an existing state
    # root belongs to an earlier run — use a fresh container per run.
    if [ -e "$root" ]; then
        echo "run: state root already exists: $root — start a fresh container" >&2
        exit 2
    fi
    mkdir -p "$root/state" || exit 2

    "$SIDEEYE" explore --config "$here/ops/$op.toml" \
        --shim "$SHIM" --oracle /usr/bin/strace \
        --work "$root/work" --json "$OUT/$op.report.json" \
        > "$OUT/$op.out" 2>&1
    echo "$op exit=$?"

    if [ -d "$root/work/cases" ]; then
        mkdir -p "$OUT/cases-$op" && cp "$root/work/cases/"*.json "$OUT/cases-$op/" 2>/dev/null
    fi
done

# The R1 leg of verify-seals audits exactly these two fields.
printf '{\n  "head": "%s",\n  "worktree_clean": %s\n}\n' "$HEAD" "$CLEAN" > "$OUT/run-manifest.json"
echo "run: manifest written to $OUT/run-manifest.json"
