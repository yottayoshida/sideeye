#!/bin/sh
# Campaign-3 Seal B artifact (ADR 0012 via ADR 0015/0016): the exploration
# runner for khal. Sealed with the declaration so exploration runs FROM the
# Seal B commit in a clean tree — verify-seals R1 audits head/cleanliness,
# R3 audits that the engine and shim that explore are byte-identical to the
# ones that swept; this runner records both digests plus the engine's
# version string (ADR 0016 requirement 6), fails closed on a missing or
# unparsable report, and records per-op exit + report state in the manifest.
#
# Invoked by the phase driver (spike/campaign-driver.sh explore), which
# supplies HEAD, CLEAN, OUT, SIDEEYE and SHIM and runs this inside the
# pinned container. Two of the three declared operations carry a
# pre-registered refusal expectation (update, new — declaration.md); a
# refused recording is a recorded result feeding #84, not a runner failure.
set -u

SIDEEYE=${SIDEEYE:-/work/zig-out/bin/sideeye}
SHIM=${SHIM:-/work/zig-out/lib/libsideeye_shim.so}
OUT=${OUT:?the driver supplies OUT}
HEAD=${HEAD:?the driver supplies HEAD}
CLEAN=${CLEAN:?the driver supplies CLEAN}

export HOME=/tmp/blind3/home
mkdir -p "$HOME" "$OUT" || exit 2

here=/work/spike/blind-hunt3/declaration/khal

# The engine's env is the container's; the checker's red-suite seams must
# not leak into a sealed run.
unset CHECK_KHAL CHECK_TIMEOUT

rows=""
bad=0
for op in import update new; do
    root=/tmp/blind3/hunt/$op
    if [ -e "$root" ]; then
        echo "run: state root already exists: $root — start a fresh container" >&2
        exit 2
    fi
    mkdir -p "$root/state" || exit 2

    "$SIDEEYE" explore --config "$here/ops/$op.toml" \
        --shim "$SHIM" --oracle /usr/bin/strace \
        --work "$root/work" --json "$OUT/$op.report.json" \
        > "$OUT/$op.out" 2>&1
    rc=$?
    echo "$op exit=$rc"

    if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$OUT/$op.report.json" 2>/dev/null; then
        report=true
    else
        report=false
        bad=$((bad + 1))
        echo "run: $op report missing or unparsable — apparatus failure" >&2
    fi
    rows="$rows    {\"op\": \"$op\", \"exit\": $rc, \"report_parses\": $report},\n"

    if [ -d "$root/work/cases" ]; then
        mkdir -p "$OUT/cases-$op" && cp "$root/work/cases/"*.json "$OUT/cases-$op/" 2>/dev/null
    fi
done
rows=$(printf "$rows" | sed '$s/,$//')

eversion=$("$SIDEEYE" version 2>&1 | head -1)
esha=$(sha256sum "$SIDEEYE" | cut -d' ' -f1)
ssha=$(sha256sum "$SHIM" | cut -d' ' -f1)
{
    printf '{\n  "head": "%s",\n  "worktree_clean": %s,\n' "$HEAD" "$CLEAN"
    printf '  "engine_version": "%s",\n  "engine_sha256": "%s",\n  "shim_sha256": "%s",\n' \
        "$eversion" "$esha" "$ssha"
    printf '  "ops": [\n%s\n  ]\n}\n' "$rows"
} > "$OUT/run-manifest.json"
echo "run: manifest written to $OUT/run-manifest.json"
[ "$bad" -eq 0 ] || { echo "run: $bad op(s) without a parsable report" >&2; exit 1; }
