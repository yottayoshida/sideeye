#!/bin/sh
# Point sideeye at omamori — the first real target (DESIGN §17).
#
# The operation is `omamori exec -- /bin/true`: one guarded command, which appends one
# line to the audit chain. The audit line carries a timestamp and an HMAC, so no two
# runs write the same bytes — the exact shape #24 was filed about, and the reason the
# audit log is judged by the history-preservation form (ADR 0004).
#
# Everything happens under an isolated HOME. The real ~/.local/share/omamori and
# ~/.config/omamori are never opened: omamori resolves every path it uses from HOME
# (src/context.rs home_dir/data_dir, src/config.rs).
#
# Two explorations run back to back, in separate homes:
#   (a) no checker      — L0 alone. Expected: PASS, with audit.jsonl named under the
#                         history form in the report.
#   (b) --check "omamori audit verify" — the target's own verifier judges every crash
#                         world, including the ones holding a torn audit line.
#                         Measured 2026-08-11: verify skips a torn tail and exits 0,
#                         so the expectation is PASS — a deviation is a finding.
set -eu

SIDEEYE_REPO=${SIDEEYE_REPO:-$HOME/claude_workspace/sideeye}
OMA=${OMA:-$(command -v omamori)}
RUN=${RUN:-/tmp/sideeye-omamori}

case $(uname -s) in
    Darwin) SHIM=$SIDEEYE_REPO/zig-out/lib/libsideeye_shim.dylib; ORACLE="--allow-unverified" ;;
    *)      SHIM=$SIDEEYE_REPO/zig-out/lib/libsideeye_shim.so;   ORACLE="--oracle /usr/bin/strace" ;;
esac

[ -x "$SIDEEYE_REPO/zig-out/bin/sideeye" ] || { echo "build sideeye first: (cd $SIDEEYE_REPO && zig build)"; exit 1; }
[ -x "$OMA" ] || { echo "omamori not found; set OMA=/path/to/omamori"; exit 1; }

# No recursive delete here. The run directory has to be new, so that nothing from a
# previous attempt can be mistaken for what this one produced — and so this script never
# has to delete anything.
[ -e "$RUN" ] && { echo "$RUN already exists. Remove it yourself, or pass RUN=<new path>."; exit 1; }
mkdir -p "$RUN"

# The setup: initialise omamori, then run one guarded command so the audit log already
# holds a line. The pre snapshot must contain the log with non-empty content — a file
# absent from pre is outside L0, and one empty in pre stays on the standard rule by
# design (ADR 0004) — so the warm-up is what makes the history form actually engage.
cat > "$RUN/setup.sh" <<SETUP
#!/bin/sh
set -eu
"$OMA" init >/dev/null 2>&1
"$OMA" exec -- /bin/true >/dev/null 2>&1
SETUP
chmod +x "$RUN/setup.sh"

echo "omamori:  $("$OMA" --version 2>&1 | head -1)"

explore() {
    label=$1; home=$2; shift 2
    # Parents included: sideeye creates only the final path component of --state, and
    # a fresh HOME has no .local/share yet.
    mkdir -p "$home/.local/share/omamori"
    echo ""
    echo "=== ($label) omamori exec -- /bin/true, killed before each state-changing operation ==="
    # Not guarded by `set -e`: FAIL is exit 1 and is a *result*, not a script error.
    set +e
    # shellcheck disable=SC2086
    env HOME="$home" "$SIDEEYE_REPO/zig-out/bin/sideeye" explore \
        --state "$home/.local/share/omamori" \
        --setup "$RUN/setup.sh" \
        --operation "$OMA exec -- /bin/true" \
        --shim "$SHIM" \
        --work "$RUN/work-$label" \
        --json "$RUN/report-$label.json" \
        $ORACLE "$@"
    rc=$?
    set -e
    echo "($label) exit=$rc  (0 PASS / 1 FAIL / 2 UNKNOWN / 3 SETUP ERROR)"
}

explore a "$RUN/home-a"
explore b "$RUN/home-b" --check "$OMA audit verify"

echo ""
echo "reports: $RUN/report-a.json $RUN/report-b.json"
