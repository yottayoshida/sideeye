#!/bin/sh
# A-group launcher for campaign-declared defines (#84 sweep). NOT a campaign
# phase: campaigns 1-3 are consumed, and sideeye/CLAUDE.md records that a
# post-campaign open re-measurement runs outside the driver. What this file
# reproduces from each declaration's sealed runner is exactly the part that
# can move a verdict — the HOME the operation child inherits, the CHECK_*
# unsets that keep red-suite seams out of the checker, and the state-root
# layout the sealed tomls point at. What it deliberately does NOT reproduce
# is the seal machinery: no HEAD/CLEAN, no run-manifest.json (that shape
# belongs to verify-seals, and an open sweep must not emit look-alikes).
# The per-launcher divergences are tabulated in docs/unknown-rate.md.
#
# Usage: campaign.sh <bh1|bh2|bh3> <tool> <op> <artifact-dir>
# Runs one declared op; writes report.json + transcript.txt into the
# artifact dir; exits with the engine's verdict code (0/1/2/3).
set -u
camp=${1:?campaign}; tool=${2:?tool}; op=${3:?op}; art=${4:?artifact dir}
SIDEEYE=${SIDEEYE:-/work/zig-out/bin/sideeye}
SHIM=${SHIM:-/work/zig-out/lib/libsideeye_shim.so}

case "$camp" in
  bh1) export HOME=/tmp/blind/home
       root=/tmp/blind/hunt/$op
       decl=/work/spike/blind-hunt/declaration/$tool ;;
  bh2) export HOME=/tmp/blind2/home
       unset CHECK_ABOOK CHECK_TIMEOUT
       root=/tmp/blind2/hunt/$op
       decl=/work/spike/blind-hunt2/declaration/$tool ;;
  bh3) export HOME=/tmp/blind3/home
       unset CHECK_KHAL CHECK_TIMEOUT
       root=/tmp/blind3/hunt/$op
       decl=/work/spike/blind-hunt3/declaration/$tool ;;
  *) echo "campaign.sh: unknown campaign: $camp" >&2; exit 3 ;;
esac

# Same refusal the sealed runners carry: a pre-existing root belongs to an
# earlier run — one fresh container per trial.
if [ -e "$root" ]; then
    echo "campaign.sh: state root already exists: $root — fresh container required" >&2
    exit 3
fi
mkdir -p "$HOME" "$root/state" "$art" || exit 3

"$SIDEEYE" explore --config "$decl/ops/$op.toml" \
    --shim "$SHIM" --oracle /usr/bin/strace \
    --work "$root/work" --json "$art/report.json" \
    > "$art/transcript.txt" 2>&1
rc=$?
echo "$camp/$tool/$op exit=$rc"
exit $rc
