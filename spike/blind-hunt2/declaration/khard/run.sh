#!/bin/sh
# Campaign-2 Seal B artifact (ADR 0012 via ADR 0015): the exploration runner.
# Sealed with the declaration so exploration can run FROM the Seal B commit in a
# clean tree — verify-seals R1 audits head/cleanliness, and campaign 2's R3 leg
# additionally audits that the engine and shim that explored are byte-identical
# to the ones that swept, so this runner measures and records both digests.
#
# Invoked by the phase driver (spike/campaign-driver.sh explore), which supplies
# HEAD, CLEAN, OUT, SIDEEYE and SHIM and runs this inside the pinned container.
# A refused operation is a recorded result feeding #84, not a runner failure —
# and for khard two of the four declared operations carry a pre-registered
# refusal expectation (random UIDs; declaration.md).
set -u

SIDEEYE=${SIDEEYE:-/work/zig-out/bin/sideeye}
SHIM=${SHIM:-/work/zig-out/lib/libsideeye_shim.so}
OUT=${OUT:?the driver supplies OUT}
HEAD=${HEAD:?the driver supplies HEAD}
CLEAN=${CLEAN:?the driver supplies CLEAN}

export HOME=/tmp/blind2/home
mkdir -p "$HOME" "$OUT" || exit 2

here=/work/spike/blind-hunt2/declaration/khard

for op in new remove move copy; do
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
    echo "$op exit=$?"

    if [ -d "$root/work/cases" ]; then
        mkdir -p "$OUT/cases-$op" && cp "$root/work/cases/"*.json "$OUT/cases-$op/" 2>/dev/null
    fi
done

esha=$(sha256sum "$SIDEEYE" | cut -d' ' -f1)
ssha=$(sha256sum "$SHIM" | cut -d' ' -f1)
printf '{\n  "head": "%s",\n  "worktree_clean": %s,\n  "engine_sha256": "%s",\n  "shim_sha256": "%s"\n}\n' \
    "$HEAD" "$CLEAN" "$esha" "$ssha" > "$OUT/run-manifest.json"
echo "run: manifest written to $OUT/run-manifest.json"
