#!/bin/sh
# The unprivileged half of the macOS oracle survey (#181).
#
# What this half can measure without root: which candidate observers exist
# on this machine, the EXACT refusal each one gives an unprivileged caller
# (the repository's claim quotes one sentence about one tool, so the
# verbatim refusals are the evidence), the census of where the claim
# lives, and the ground truth the privileged half will judge captures
# against. Everything root-gated is in sudo-survey.sh, run by the owner.
#
# The claim under test, from four sites the issue names: "macOS has no
# usable oracle: dtruss is DTrace-based and SIP refuses it." ADR 0001
# wrote "to be measured" in 2026-08-10 and nothing since has recorded the
# measurement.
set -u
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/se181.XXXXXX")
FAILS=0
bad() { echo "BROKEN: $*"; FAILS=$((FAILS+1)); }

# Guarded run for tools that might block instead of refusing: background,
# bounded, output captured. The bound is generous; an unprivileged refusal
# is expected to be immediate.
guarded() { # outfile cmd...
    out=$1; shift
    "$@" > "$out" 2>&1 &
    pid=$!
    ( sleep 8; kill "$pid" 2>/dev/null ) &
    guard=$!
    wait "$pid"
    rc=$?
    kill "$guard" 2>/dev/null
    wait "$guard" 2>/dev/null
    return $rc
}

echo "== environment"
sw_vers | sed 's/^/   /'
echo "   $(uname -rm)"
echo "   $(csrutil status)"
echo "   invoked as uid $(id -u) (this half is deliberately unprivileged)"

echo ""
echo "== the check this survey trusts, seen red before it judges anything"
python3 "$here/check-capture.py" --selftest || bad "check-capture selftest failed"

echo ""
echo "== the toy, built and self-accounted"
/usr/bin/cc -O0 -o "$W/toy" "$here/toy.c" || bad "toy build failed"
echo "   codesign identity of the fresh build (linker-applied, not ours):"
codesign -dv "$W/toy" 2>&1 | sed -n '1,3p' | sed 's/^/     /'
mkdir -p "$W/state"
"$W/toy" "$W/state" > "$W/ground-truth.txt" 2>&1
rc=$?
echo "   toy rc=$rc; its own account:"
sed 's/^/     /' "$W/ground-truth.txt"
echo "   what it left on disk:"
( cd "$W/state" && find . | LC_ALL=C sort | sed 's/^/     /' )
python3 "$here/check-capture.py" --allow-self-account \
    "$W/ground-truth.txt" "ground-truth (positive control)" \
    || bad "the ground truth itself fails the check, so no capture can pass it"
echo "   (--allow-self-account, because the ground truth IS a self-account;"
echo "    observer legs run without the flag and are rejected if their"
echo "    capture holds nothing but the toy's own words)"

echo ""
echo "== candidate presence"
for t in dtruss dtrace fs_usage ktrace praudit auditd eslogger sc_usage; do
    p=$(command -v "$t" 2>/dev/null || ls "/usr/sbin/$t" 2>/dev/null)
    printf '   %-10s %s\n' "$t" "${p:-ABSENT}"
done

echo ""
echo "== unprivileged refusals, verbatim (each tool asked once, no root)"
echo "-- dtrace (the two-line refusal the issue distinguishes: SIP limits"
echo "   SOME features; the hard stop is PRIVILEGES)"
guarded "$W/r-dtrace.txt" dtrace -n 'BEGIN{trace(0); exit(0);}'
echo "   rc=$?"; sed 's/^/   | /' "$W/r-dtrace.txt"
echo "-- dtruss"
guarded "$W/r-dtruss.txt" dtruss /usr/bin/true
echo "   rc=$?"; head -4 "$W/r-dtruss.txt" | sed 's/^/   | /'
echo "-- fs_usage"
guarded "$W/r-fsusage.txt" fs_usage -t 1
echo "   rc=$?"; head -3 "$W/r-fsusage.txt" | sed 's/^/   | /'
echo "-- ktrace (also capturing its usage text: the privileged invocation"
echo "   is designed from this rather than from memory)"
guarded "$W/r-ktrace.txt" ktrace trace -c "$W/toy" "$W/state"
echo "   rc=$?"; head -4 "$W/r-ktrace.txt" | sed 's/^/   | /'
ktrace trace 2>&1 | head -12 > "$W/ktrace-usage.txt"
sed 's/^/   usage| /' "$W/ktrace-usage.txt"
echo "-- eslogger (Endpoint Security's shipped CLI front end: the ES"
echo "   candidate that needs no entitlement of our own)"
guarded "$W/r-eslogger.txt" eslogger create rename unlink close
echo "   rc=$?"; head -3 "$W/r-eslogger.txt" | sed 's/^/   | /'
echo "-- OpenBSM surface, and its explicit dismissal (no sudo leg needed)"
echo "   auditd running: $(pgrep -x auditd > /dev/null 2>&1 && echo yes || echo no)"
echo "   /dev/auditpipe: $(ls /dev/auditpipe 2>/dev/null || echo ABSENT)"
guarded "$W/r-praudit.txt" praudit /dev/auditpipe
echo "   praudit rc=$?"; head -2 "$W/r-praudit.txt" | sed 's/^/   | /'
echo "   Apple's own stance, from auditd(8) on this machine (the grep is"
echo "   captured to a file first, because a pipeline's fallback branch"
echo "   reads the wrong status):"
man 8 auditd 2>/dev/null | col -b | grep -iA3 '^DEPRECATION' > "$W/bsm-dep.txt"
if [ -s "$W/bsm-dep.txt" ]; then sed 's/^/   | /' "$W/bsm-dep.txt"
else bad "auditd(8) deprecation notice not found; the dismissal below is unsupported"; fi
echo "   reading: deprecated since 11.0, DISABLED since 14.0, removal"
echo "   announced. This machine runs 15.3.1, so no events flow from this"
echo "   subsystem regardless of privileges: dismissed without a sudo leg."

echo ""
echo "== the man-page lines the privileged invocations are designed from"
echo "   (committed here because the sudo half's comment cites them; a"
echo "    design source that is only in a session's memory is not a source)"
echo "-- ktrace: the -f/-c options and the filter grammar"
man ktrace 2>/dev/null | col -b | grep -A4 '^FILTER DESCRIPTIONS' > "$W/man-ktrace.txt"
man ktrace 2>/dev/null | col -b | grep -B1 -A3 '^\s*-c command' >> "$W/man-ktrace.txt"
if [ -s "$W/man-ktrace.txt" ]; then sed 's/^/   | /' "$W/man-ktrace.txt"
else bad "ktrace man excerpts came back empty; the C3 invocation would rest on memory"; fi
echo "-- eslogger: the root + TCC requirement in Apple's words"
man eslogger 2>/dev/null | col -b | grep -B1 -A3 'Full Disk Access' | head -8 > "$W/man-eslogger.txt"
if [ -s "$W/man-eslogger.txt" ]; then sed 's/^/   | /' "$W/man-eslogger.txt"
else bad "eslogger man excerpt came back empty"; fi
echo "-- fs_usage: the synopsis the process-name filter comes from"
man fs_usage 2>/dev/null | col -b | sed -n '/^SYNOPSIS/,/^DESCRIPTION/p' | head -6 > "$W/man-fsusage.txt"
if [ -s "$W/man-fsusage.txt" ]; then sed 's/^/   | /' "$W/man-fsusage.txt"
else bad "fs_usage man excerpt came back empty"; fi

echo ""
echo "== census: where the no-oracle claim lives (tracked files, this spike excluded)"
echo "-- positive control: the dtruss-only claim sites"
git -C "$repo" grep -n 'dtruss' -- ':!spike/' | sed 's/^/   /'
echo "-- the candidates, file counts"
for w in fs_usage ktrace praudit eslogger "Endpoint Security" OpenBSM kdebug; do
    n=$(git -C "$repo" grep -il "$w" -- ':!spike/macos-oracle' | wc -l | tr -d ' ')
    printf '   %-20s %s file(s)\n' "$w" "$n"
done
echo "   (the issue measured all of these at zero on 2026-08-18; the"
echo "    nonzero ones today are docs/freeze-audit.md and BUILDLOG quoting"
echo "    the issue itself, not measurements)"

echo ""
echo "== what this half cannot answer, by construction"
echo "   Every candidate refuses an unprivileged caller, so whether any of"
echo "   them can serve as an oracle is decided entirely by the privileged"
echo "   half (sudo-survey.sh, run by the owner). This half only pins the"
echo "   refusals the claim text paraphrases."

/bin/rm -rf "${W:?}"
echo ""
echo "== BROKEN checks: $FAILS"
[ "$FAILS" -eq 0 ] || exit 1
exit 0
