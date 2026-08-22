#!/bin/sh
# Pre-define trials for the papis define (cohort 3, target 5), run
# before the define exists and committed beside it: feed each damaged
# library state to papis's own reader and to its documented repair
# (`papis doctor`, whose `--fix` is the auto-fixer and whose `files`
# check verifies that a document's files exist), and record what each
# one actually does. The poetry define's R1 caught wrong-leg
# declarations that intuition had produced; these trials are how the
# papis declaration gets its legs from measurement instead.
#
# Engine-free: normal executions and file surgery only. Fixtures and
# config are the accepted probe's, byte-for-byte.
set -u
WS=/tmp/trials-papis
rm -rf "$WS"; mkdir -p "$WS"

echo "== papis pre-define trials — $(papis --version 2>&1 | tr -d '\n') — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "python3 yaml module: $(python3 -c 'import yaml; print(yaml.__version__)' 2>&1)"

printf 'existing document, fixed bytes' > "$WS/existing.txt"
printf 'probe document, fixed bytes'    > "$WS/fixture.txt"
cat > "$WS/existing-meta.yaml" <<'EOF'
title: Existing
author: Probe Author
papis_id: existing0001
EOF
cat > "$WS/probe-meta.yaml" <<'EOF'
title: Probe
author: Probe Author
year: 2026
papis_id: probe0001
EOF

export HOME="$WS/home"; mkdir -p "$HOME"
export PAPIS_NP=0

write_config() { # xdg-dir lib-dir
    mkdir -p "$1/papis"
    cat > "$1/papis/config" <<EOF
[settings]
time-stamp = False
use-cache = False
default-library = probe


[probe]
dir = $2
EOF
}

# ---- the two engine-reachable states, built by normal runs -----------------
mkdir -p "$WS/pre/lib"
write_config "$WS/xdg-setup" "$WS/pre/lib"
mkdir -p "$WS/cache-setup"
XDG_CONFIG_HOME="$WS/xdg-setup" XDG_CACHE_HOME="$WS/cache-setup" \
    papis add --batch --from yaml "$WS/existing-meta.yaml" \
    --folder-name existing-doc "$WS/existing.txt" > /dev/null 2>&1
echo "setup: the pre-state (one existing document) rc=$?"
cp -a "$WS/pre/lib" "$WS/new"
write_config "$WS/xdg-new" "$WS/new"
mkdir -p "$WS/cache-new"
XDG_CONFIG_HOME="$WS/xdg-new" XDG_CACHE_HOME="$WS/cache-new" \
    papis add --batch --from yaml "$WS/probe-meta.yaml" \
    --folder-name probe-doc "$WS/fixture.txt" > /dev/null 2>&1
echo "setup: the completed-add state rc=$?"

trial() { # label lib-dir
    lbl=$1; lib=$2
    xdg="$WS/xdg-t"; cache="$WS/cache-t"
    rm -rf "$xdg" "$cache"; write_config "$xdg" "$lib"; mkdir -p "$cache"
    echo "---- $lbl"
    echo "  library contents:"
    find "$lib" -mindepth 1 | sed "s|$WS|WS|" | sort | sed 's/^/    /'
    out=$(XDG_CONFIG_HOME="$xdg" XDG_CACHE_HOME="$cache" papis list --all --format '{doc[title]} {doc[papis_id]}' 2>&1); rc=$?
    echo "  papis list rc=$rc, output:"
    printf '%s\n' "$out" | sed 's/^/    | /'
    dout=$(XDG_CONFIG_HOME="$xdg" XDG_CACHE_HOME="$cache" papis doctor --all-checks 2>&1); drc=$?
    echo "  papis doctor --all-checks rc=$drc, output:"
    printf '%s\n' "$dout" | sed 's/^/    | /'
    fout=$(XDG_CONFIG_HOME="$xdg" XDG_CACHE_HOME="$cache" papis doctor --all-checks --fix 2>&1); frc=$?
    echo "  papis doctor --all-checks --fix rc=$frc, output:"
    printf '%s\n' "$fout" | sed 's/^/    | /'
    out2=$(XDG_CONFIG_HOME="$xdg" XDG_CACHE_HOME="$cache" papis list --all --format '{doc[title]} {doc[papis_id]}' 2>&1); rc2=$?
    echo "  papis list AFTER the fix rc=$rc2, output:"
    printf '%s\n' "$out2" | sed 's/^/    | /'
    echo "  library contents AFTER the fix:"
    find "$lib" -mindepth 1 | sed "s|$WS|WS|" | sort | sed 's/^/    /'
    if [ -f "$lib/probe-doc/info.yaml" ]; then
        echo "  probe-doc/info.yaml AFTER the fix:"
        sed 's/^/    | /' "$lib/probe-doc/info.yaml"
    fi
}

# A: the old state (engine-reachable: kill before the rename)
cp -a "$WS/pre/lib" "$WS/lA"; trial "A: old state (engine-reachable)" "$WS/lA"

# B: the completed add (engine-reachable: the baseline)
cp -a "$WS/new" "$WS/lB"; trial "B: completed add (engine-reachable)" "$WS/lB"

# C: a document directory present but EMPTY (surgery; the shape a
# non-atomic mkdir-then-fill would leave)
cp -a "$WS/pre/lib" "$WS/lC"; mkdir -p "$WS/lC/probe-doc"
trial "C: probe-doc present but empty (surgery)" "$WS/lC"

# D: info.yaml missing, attachment present (surgery)
cp -a "$WS/new" "$WS/lD"; rm "$WS/lD/probe-doc/info.yaml"
trial "D: probe-doc without info.yaml (surgery)" "$WS/lD"

# E: attachment missing, info.yaml intact (surgery; the shape papis's
# own `files` doctor check is written for)
cp -a "$WS/new" "$WS/lE"; rm "$WS/lE/probe-doc/fixture.txt"
trial "E: probe-doc without its attachment (surgery)" "$WS/lE"

# F: info.yaml torn mid-line (surgery)
cp -a "$WS/new" "$WS/lF"; head -c 40 "$WS/new/probe-doc/info.yaml" > "$WS/lF/probe-doc/info.yaml"
trial "F: torn info.yaml (surgery)" "$WS/lF"

# G: attachment truncated (surgery)
cp -a "$WS/new" "$WS/lG"; head -c 5 "$WS/new/probe-doc/fixture.txt" > "$WS/lG/probe-doc/fixture.txt"
trial "G: truncated attachment (surgery)" "$WS/lG"

echo "== trials done (this script judges nothing; the readings feed the define's declaration)"
