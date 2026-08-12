#!/bin/sh
# The v0.4 surface evidence (PRD v0.4): the enumeration of omamori's state-changing
# surfaces (BUILDLOG, same date) leaves four subcommands writing file state without a
# guard in the way — `install`, `setup --non-interactive`, plain `init` (the AI guard
# fires on `init --force` only; creating a config where none exists is deliberately
# unguarded), and `audit verify` (it re-creates a missing high-water mark: a bootstrap
# write, measured by hand before this script pinned it). This script drives each as a
# sideeye operation, L0-only, with the strace oracle, in a disposable HOME inside the
# state directory.
#
# Each probe PINS the outcome the enumeration reports as evidence. "Any honest
# refusal" would be a check that cannot fail — a rerun that hit a different wall
# would still print green while the BUILDLOG kept citing the old reason. The pin has
# already earned its keep once: the first version of this script wrapped the
# operation in a shell script whose `exec "$OMAMORI"` replaced the recorded process's
# image, and all probes answered child_process_detected ("the target replaced its own
# image") — a harness artifact about to be documented as omamori's structure. The
# pinned PASS prediction for `audit verify` failed, which is what exposed it. The
# operation is now the omamori command line directly; HOME/SHELL reach the child by
# inheritance from the engine's environment (the same wiring dogfood-timew.sh uses
# for TIMEWARRIORDB).
#
# The guarded surfaces (config add/enable/disable, override, init --force, uninstall,
# audit key rotate, break-glass clear) are out of scope on discipline: driving them
# needs break-glass, which removes the defence under test (#12). The append-path
# writes (audit chain, hwm, retention prune, throttle, quarantine) belong to
# exec/shim/hook and are analyzed in the BUILDLOG entry — the prune rewrite needs
# clock control to drive and is recorded there, not here.
#
# Needs (Linux container): python3, strace, and an omamori release binary. Build it
# from a tracked-files copy of the omamori repo:
#   git -C <omamori> archive HEAD | docker exec -i <c> sh -c 'mkdir -p /omamori-src && tar -x -C /omamori-src'
#   docker exec <c> sh -c 'cd /omamori-src && cargo build --release'
set -eu

SIDEEYE_REPO=${SIDEEYE_REPO:-/work}
RUN=${RUN:-/tmp/sideeye-omamori-surface}
SIDEEYE=$SIDEEYE_REPO/zig-out/bin/sideeye
SHIM=$SIDEEYE_REPO/zig-out/lib/libsideeye_shim.so
OMAMORI=${OMAMORI:-/omamori-src/target/release/omamori}

[ "$(uname -s)" = "Linux" ] || { echo "Linux container only"; exit 1; }
[ -x "$SIDEEYE" ] || { echo "build sideeye first: zig build -Dtarget=<arch>-linux-gnu"; exit 1; }
[ -f "$SHIM" ] || { echo "shim not found: $SHIM"; exit 1; }
[ -x "$OMAMORI" ] || { echo "omamori binary not found: $OMAMORI (see header)"; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found"; exit 1; }
command -v strace >/dev/null || { echo "strace not found"; exit 1; }
[ -e "$RUN" ] && { echo "$RUN already exists. Remove it yourself, or pass RUN=<new path>."; exit 1; }
mkdir -p "$RUN"

fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

# One explore per unguarded writer, with the expected outcome pinned.
#   $1 label   $2 expected verdict   $3 expected unknown_reason ("-" = must be absent)
#   $4 expected message fragment ("-" = none)   $5 minimum crash_points
#   $6 the operation, verbatim (split on spaces by the engine; no shell)
surface() {
    label=$1; want_v=$2; want_r=$3; want_m=$4; min_cp=$5; op=$6
    state=$RUN/$label/state
    mkdir -p "$state"

    cat > "$RUN/$label/setup.sh" <<'SETUP'
#!/bin/sh
set -eu
mkdir -p "$HOME"
SETUP
    if [ "$label" = "verify" ]; then
        # A chain with no high-water mark: one real append mints chain + mark, then
        # the mark is removed, so the operation's bootstrap re-write is the one write
        # under measurement.
        cat >> "$RUN/$label/setup.sh" <<SETUP
"$OMAMORI" exec -- /bin/true >/dev/null 2>&1
rm -f "\$HOME/.local/share/omamori/audit.jsonl.hwm"
SETUP
    fi
    chmod +x "$RUN/$label/setup.sh"

    echo ""
    echo "=========== $op — expecting $want_v${want_r:+ ($want_r)} ==========="
    set +e
    HOME="$state/home" SHELL=/bin/bash "$SIDEEYE" explore \
        --state "$state" --setup "$RUN/$label/setup.sh" \
        --operation "$op" \
        --shim "$SHIM" --work "$RUN/$label/work" \
        --json "$RUN/$label/report.json" --oracle /usr/bin/strace \
        > "$RUN/$label/report.txt" 2>&1
    rc=$?
    set -e
    if WANT_V="$want_v" WANT_R="$want_r" WANT_M="$want_m" MIN_CP="$min_cp" python3 -c '
import json, os, sys
r = json.load(open(sys.argv[1]))
got = "%s (%s)" % (r.get("verdict"), r.get("unknown_reason"))
if r.get("verdict") != os.environ["WANT_V"]: sys.exit("got " + got)
want_r = os.environ["WANT_R"]
if want_r == "-":
    if "unknown_reason" in r: sys.exit("got " + got)
elif r.get("unknown_reason") != want_r: sys.exit("got " + got)
want_m = os.environ["WANT_M"]
if want_m != "-" and want_m not in r.get("message", ""):
    sys.exit("message does not contain %r: %s" % (want_m, r.get("message")))
if r.get("crash_points", 0) < int(os.environ["MIN_CP"]):
    sys.exit("crash_points %s below the pinned minimum %s — a vacuous pass, not a measurement"
             % (r.get("crash_points"), os.environ["MIN_CP"]))
print("%s  crash_points=%s explored=%s" % (got, r.get("crash_points"), r.get("explored")))
' "$RUN/$label/report.json"; then
        pass "$label: the pinned outcome (exit $rc)"
    else
        fail "$label: outcome moved — remeasure, and update the BUILDLOG entry that cites this"
        sed 's/^/     | /' "$RUN/$label/report.txt" | tail -8
    fi
}

# install and setup die on the same wall: the installer creates the PATH shims as
# SYMLINKS, and symlinkat is outside the trace contract — the oracle sees an
# operation the shim cannot record, and the account refuses (the #39/#5 wall family,
# named). init dies one step earlier on fchmodat (the config dir/file permissions).
surface install UNKNOWN unsupported_syscall_observed symlinkat 0 "$OMAMORI install"
# --source: without it, setup's own safety guard refuses a cargo build artifact as
# the hook source and the recording run exits non-zero before hooks are touched
# (measured both ways; that refusal is an install-time defence doing its job).
surface setup UNKNOWN unsupported_syscall_observed symlinkat 0 "$OMAMORI setup --non-interactive --source $OMAMORI"
surface init UNKNOWN unsupported_syscall_observed fchmodat 0 "$OMAMORI init"
# audit verify's bootstrap hwm re-write is the one unguarded surface sideeye can
# fully explore — and it holds: the mark is published by temp + create_new + rename,
# and every crash world keeps a database that is pre or post, never torn.
surface verify PASS - - 1 "$OMAMORI audit verify"

echo ""
if [ "$fails" = "0" ]; then echo "ALL SURFACE PROBES MATCH THE PINNED OUTCOMES"; else echo "$fails probe(s) failed"; exit 1; fi
