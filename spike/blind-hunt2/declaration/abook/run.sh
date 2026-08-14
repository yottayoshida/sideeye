#!/bin/sh
# Campaign-2 Seal B artifact (ADR 0012 via ADR 0015): the exploration runner
# for abook. Sealed with the declaration so exploration can run FROM the
# Seal B commit in a clean tree — verify-seals R1 audits head/cleanliness,
# and the R3 leg audits that the engine and shim that explore are
# byte-identical to the ones that swept; this runner measures and records
# both digests plus the engine's version string (ADR 0015 field contract —
# the khard round's R1 caught the version string missing, so it is explicit
# here).
#
# Invoked by the phase driver (spike/campaign-driver.sh explore), which
# supplies HEAD, CLEAN, OUT, SIDEEYE and SHIM and runs this inside the pinned
# container. A refused recording is a recorded result feeding #84, not a
# runner failure. No refusal is pre-registered for abook (declaration.md:
# both writers observed byte-deterministic).
set -u

SIDEEYE=${SIDEEYE:-/work/zig-out/bin/sideeye}
SHIM=${SHIM:-/work/zig-out/lib/libsideeye_shim.so}
OUT=${OUT:?the driver supplies OUT}
HEAD=${HEAD:?the driver supplies HEAD}
CLEAN=${CLEAN:?the driver supplies CLEAN}

export HOME=/tmp/blind2/home
mkdir -p "$HOME" "$OUT" || exit 2

here=/work/spike/blind-hunt2/declaration/abook

# The engine's env is the container's; the checker's red-suite seams must not
# leak into a sealed run.
unset CHECK_ABOOK CHECK_TIMEOUT

# Fail-closed (R1 of this declaration): a recorded refusal is a result, but it
# still produces a report — an op whose report is missing or unparsable is an
# APPARATUS failure, and this runner must not exit 0 over one. Each op's exit
# and report state go into the manifest so nothing is swallowed either way.
rows=""
bad=0
for op in import export refused; do
    root=/tmp/blind2/hunt/$op
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
