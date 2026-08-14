#!/bin/sh
# CI entry point for the blind-hunt campaigns' internal consistency.
#
# Why this exists, and why it is not inside any one campaign: campaign 2 sealed
# an apparatus that contradicted itself — two config files named campaign 1's
# state roots while the sealed invocations watched another — and the seal had to
# be voided. The check that catches that class was written afterwards, inside
# campaign 2, where it protects exactly one campaign and only if someone
# remembers to run it. This script is the part that does not depend on
# remembering: it walks EVERY campaign directory present and runs whatever
# consistency checker that campaign sealed.
#
# Contract, deliberately strict in both directions:
#
#   * every spike/blind-hunt*/ directory that has an invocations.tsv MUST carry
#     an executable check-config-paths.sh, and it must pass. A campaign that
#     seals invocations without sealing this check fails CI — that is the
#     forward-carry rule (each campaign copies the tooling; a copy that dropped
#     the check would otherwise be invisible).
#   * a campaign directory without invocations.tsv is pre-sweep and skipped,
#     loudly.
#   * finding no campaign at all is a failure, not a pass. A path typo here
#     would otherwise report success over an empty set — the failure mode this
#     repository keeps meeting.
#
# Campaign 1 predates the check and is exempt by name: its seals are closed and
# adding files to that directory would mark its checkers sighted (ADR 0012).
# The exemption is a literal, so a new campaign cannot inherit it by accident.
set -u

root=${1:-$(cd "$(dirname "$0")/.." && pwd)}
exempt="blind-hunt"

found=0
checked=0
fails=0

for dir in "$root"/spike/blind-hunt*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    found=$((found + 1))

    if [ "$name" = "$exempt" ]; then
        echo "skip  $name: predates the check; its seals are closed (ADR 0012)"
        continue
    fi

    if [ ! -f "$dir/invocations.tsv" ]; then
        echo "skip  $name: no invocations.tsv yet (pre-sweep campaign)"
        continue
    fi

    if [ ! -x "$dir/check-config-paths.sh" ]; then
        echo "FAIL  $name: seals invocations.tsv but carries no executable check-config-paths.sh"
        fails=$((fails + 1))
        continue
    fi

    if sh "$dir/check-config-paths.sh" "$dir"; then
        checked=$((checked + 1))
    else
        echo "FAIL  $name: sealed configs disagree with sealed invocations"
        fails=$((fails + 1))
    fi
done

if [ "$found" = 0 ]; then
    echo "FAIL  no campaign directory found under $root/spike/ — this check could not look" >&2
    exit 1
fi

echo ""
echo "campaigns seen: $found, checked: $checked, failures: $fails"
[ "$fails" = 0 ]
