#!/bin/sh
# Point sideeye at todoman 4.1 — the Python target that surfaced #31, re-run after #34.
#
# The operation is `todo new --list default second` against a list seeded with one todo.
# todoman confirms a new entry with atomicwrites: create the temp with O_EXCL, reopen,
# write, fsync, link(2) to the final name, unlink the temp, fsync the directory — seven
# state-directory operations, and the linkat is the one that made the calibration sweep
# refuse (unsupported_syscall_observed, #31) before #34 made links first-class.
#
# Two explorations run back to back, each in its own home and state directory:
#   (a) no checker        — L0 alone. Measured 2026-08-11: PASS 8/8 crash worlds,
#                           oracle agreed on 7 operations.
#   (b) --check check.sh  — a strict wrapper around `todo list`. The bare command is
#                           NOT a usable checker: on an unreadable entry it prints
#                           "Failed to read entry …" to stderr and exits 0, answering
#                           "nothing wrong" precisely when it could not look, so
#                           falsification rejects it (checker_not_falsified) — measured.
#                           The wrapper fails on the skip message, restoring the
#                           contract. Measured: falsified before the run, then PASS 8/8.
#
# Needs `todo` on PATH. From the spike image:
#   apt-get update && apt-get install -y --no-install-recommends python3-pip
#   python3 -m pip install --break-system-packages \
#     --trusted-host pypi.org --trusted-host files.pythonhosted.org todoman==4.1 pytz
# (--trusted-host: this host's network intercepts TLS with a self-signed chain — the
#  same wall rustup hit. pytz: todoman 4.1 with current icalendar imports it at runtime
#  and neither package declares it.)
set -eu

SIDEEYE_REPO=${SIDEEYE_REPO:-/work}
RUN=${RUN:-/tmp/sideeye-todoman}
SHIM=$SIDEEYE_REPO/zig-out/lib/libsideeye_shim.so

[ -x "$SIDEEYE_REPO/zig-out/bin/sideeye" ] || { echo "build sideeye first: zig build -Dtarget=<arch>-linux-gnu"; exit 1; }
command -v todo >/dev/null || { echo "todo not found; see the header for the install"; exit 1; }

# No recursive delete here. The run directory has to be new, so that nothing from a
# previous attempt can be mistaken for what this one produced — and so this script never
# has to delete anything.
[ -e "$RUN" ] && { echo "$RUN already exists. Remove it yourself, or pass RUN=<new path>."; exit 1; }
mkdir -p "$RUN"

cat > "$RUN/check.sh" <<'CHECK'
#!/bin/sh
# Fails if todo list fails, or if it silently skipped an unreadable entry.
out=$(todo list 2>&1) || exit 1
printf '%s\n' "$out" | grep -q "Failed to read entry" && exit 1
exit 0
CHECK
chmod +x "$RUN/check.sh"

echo "todoman: $(todo --version)"

explore() {
    label=$1; shift
    home=$RUN/$label/home
    state=$RUN/$label/state

    # Everything happens under an isolated per-exploration HOME (todoman's cache is a
    # sqlite file under ~/.cache, outside the state directory), so neither exploration
    # sees the other's files. The config must end in .py — todoman loads it with
    # importlib and refuses any other extension.
    export HOME=$home
    export TODOMAN_CONFIG=$RUN/$label/config.py
    mkdir -p "$home" "$state"
    printf 'path = "%s"\n' "$state/*" > "$TODOMAN_CONFIG"

    # Setup: create the list and seed one todo, so the pre snapshot holds a non-empty
    # file that exists in both pre and post — the standard L0 form has something to judge.
    cat > "$RUN/$label/setup.sh" <<SETUP
#!/bin/sh
set -eu
mkdir -p "$state/default"
todo new --list default seeded >/dev/null 2>&1
SETUP
    chmod +x "$RUN/$label/setup.sh"

    echo ""
    echo "=== ($label) todo new --list default second, killed before each state-changing operation ==="
    # Not guarded by `set -e`: FAIL is exit 1 and is a *result*, not a script error.
    set +e
    "$SIDEEYE_REPO/zig-out/bin/sideeye" explore \
        --state "$state" \
        --setup "$RUN/$label/setup.sh" \
        --operation "todo new --list default second" \
        --shim "$SHIM" \
        --work "$RUN/$label/work" \
        --json "$RUN/$label/report.json" \
        --oracle /usr/bin/strace "$@"
    rc=$?
    set -e
    echo "($label) exit=$rc  (0 PASS / 1 FAIL / 2 UNKNOWN / 3 SETUP ERROR)"
}

explore a
explore b --check "$RUN/check.sh"

echo ""
echo "reports: $RUN/a/report.json $RUN/b/report.json"
