#!/bin/sh
# Scout measurement for the papis define (cohort 3, target 5), run
# before the define exists. The accepted probe measured **3 in-process
# threads** during `papis add` and recorded "no off switch measured
# yet — to scout at its slot" (RESULTS.md). This is that slot.
#
# The candidate switch is papis's own documented one: `PAPIS_NP`, whose
# docstring in `papis/utils.py::parmap` reads "The number of processes
# can also be controlled using the PAPIS_NP environment variable.
# Setting this variable to 0 will disable the use of multiprocessing on
# all platforms" — an env/config pin, the cohort's free apparatus tier.
#
# Engine-free: normal executions only. Fixtures and config are the
# accepted probe's, byte-for-byte (`../probes/run-papis.sh`), so the two
# transcripts are comparable line for line. Judged by the same cohort-2
# predicates the probe used, sourced in place.
set -u
. "$(dirname "$0")/../../cohort2/probes/lib.sh"

WS=/tmp/scout-papis
OUT=${SCOUT_OUT:-$WS}
rm -rf "$WS"; mkdir -p "$WS"

note "papis thread-off-switch scout — $(papis --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

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

mkdir -p "$WS/pre/lib"
write_config "$WS/xdg-setup" "$WS/pre/lib"
mkdir -p "$WS/cache-setup"
XDG_CONFIG_HOME="$WS/xdg-setup" XDG_CACHE_HOME="$WS/cache-setup" \
    papis add --batch --from yaml "$WS/existing-meta.yaml" \
    --folder-name existing-doc "$WS/existing.txt" > /dev/null 2>&1
echo "setup: papis add (existing doc) rc=$?"

# ---- the clone forecast, per configuration --------------------------------
# Each configuration gets a fresh pre-state copy and fresh ambient, so
# the counts are per-run, not cumulative.
forecast() { # label extra-env-name extra-env-value
    lbl=$1; ev=$2; evv=$3
    rm -rf "$WS/libF" "$WS/xdg-F" "$WS/cache-F"
    cp -a "$WS/pre/lib" "$WS/libF"
    write_config "$WS/xdg-F" "$WS/libF"
    mkdir -p "$WS/cache-F"
    if [ -n "$ev" ]; then
        env "$ev=$evv" XDG_CONFIG_HOME="$WS/xdg-F" XDG_CACHE_HOME="$WS/cache-F" \
            strace -f -o "$WS/forecast.log" -e trace=clone,clone3 \
            papis add --batch --from yaml "$WS/probe-meta.yaml" \
            --folder-name probe-doc "$WS/fixture.txt" > /dev/null 2>&1
    else
        XDG_CONFIG_HOME="$WS/xdg-F" XDG_CACHE_HOME="$WS/cache-F" \
            strace -f -o "$WS/forecast.log" -e trace=clone,clone3 \
            papis add --batch --from yaml "$WS/probe-meta.yaml" \
            --folder-name probe-doc "$WS/fixture.txt" > /dev/null 2>&1
    fi
    rc=$?
    # The run must have DONE something: rc 0 and the document landed.
    # A forecast that only counts clones cannot tell 0-threads from
    # died-at-startup (the cohort's zero-without-a-denominator trap).
    landed=no
    [ -f "$WS/libF/probe-doc/info.yaml" ] && [ -f "$WS/libF/probe-doc/fixture.txt" ] && landed=yes
    echo "  $lbl: rc=$rc, document landed=$landed, threads=$(thread_counts "$WS/forecast.log"), clone lines total=$(grep -c 'clone' "$WS/forecast.log"), distinct pids=$(grep -oE '^[0-9]+' "$WS/forecast.log" | sort -u | wc -l | tr -d ' ')"
    rm -f "$WS/forecast.log"
}

note "clone forecast per configuration (fresh pre-state and ambient each; rc and landing asserted so a zero cannot mean 'did nothing'):"
forecast "default          " "" ""
forecast "PAPIS_NP=0       " PAPIS_NP 0

# ---- the write shape under the define's configuration ---------------------
note "strace pass under PAPIS_NP=0 (fresh copy; raw log kept as papis-np0.strace)"
rm -rf "$WS/libS" "$WS/xdg-S" "$WS/cache-S"
cp -a "$WS/pre/lib" "$WS/libS"
write_config "$WS/xdg-S" "$WS/libS"
mkdir -p "$WS/cache-S"
PAPIS_NP=0 XDG_CONFIG_HOME="$WS/xdg-S" XDG_CACHE_HOME="$WS/cache-S" \
    run_strace "$WS/strace.log" papis add --batch --from yaml "$WS/probe-meta.yaml" \
    --folder-name probe-doc "$WS/fixture.txt" > /dev/null 2>&1
echo "strace'd run rc=$?"
cp "$WS/strace.log" "$OUT/papis-np0.strace" 2>/dev/null || true

note "mutating paths (successful only, deduped):"
closure_paths "$WS/strace.log" "$WS/unattr-count" | sort -u | sed "s|$WS|WS|"
echo "unattributed count: $(cat "$WS/unattr-count" 2>/dev/null || echo '?')"
closure_check "$WS/strace.log" "$WS/libS" "$WS/xdg-S" "$WS/cache-S" "$WS/home" /tmp/
note "thread creations under PAPIS_NP=0 (successful CLONE_THREAD):"
thread_counts "$WS/strace.log"

note "state-root write shape under PAPIS_NP=0 (the syscalls that decide the crash worlds):"
grep "libS" "$WS/strace.log" | grep -E "renameat|rename\(|openat.*(O_WRONLY|O_TRUNC|O_CREAT)|unlinkat|mkdirat|fchmodat|chmod|utimensat|linkat" | grep -v "= -1" | sed "s|$WS|WS|"

# ---- correctness and determinism under the switch --------------------------
note "the document papis wrote under PAPIS_NP=0 (recorded, not predicted):"
cat "$WS/libS/probe-doc/info.yaml"
lst=$(PAPIS_NP=0 XDG_CONFIG_HOME="$WS/xdg-S" XDG_CACHE_HOME="$WS/cache-S" papis list --all --format '{doc[title]} {doc[papis_id]}' 2>/dev/null | grep -c '^Probe probe0001$')
wrong=$(PAPIS_NP=0 XDG_CONFIG_HOME="$WS/xdg-S" XDG_CACHE_HOME="$WS/cache-S" papis list --all --format '{doc[title]} {doc[papis_id]}' 2>/dev/null | grep -c '^Probe probe9999$')
echo "read-back under the switch: 'Probe probe0001' matches $lst line(s); wrong-id drill counts $wrong"

note "determinism under PAPIS_NP=0 (two runs >=2s apart, fresh ambient each):"
for sfx in D1 D2; do
    rm -rf "$WS/lib$sfx" "$WS/xdg-$sfx" "$WS/cache-$sfx"
    cp -a "$WS/pre/lib" "$WS/lib$sfx"
    write_config "$WS/xdg-$sfx" "$WS/lib$sfx"
    mkdir -p "$WS/cache-$sfx"
    PAPIS_NP=0 XDG_CONFIG_HOME="$WS/xdg-$sfx" XDG_CACHE_HOME="$WS/cache-$sfx" \
        papis add --batch --from yaml "$WS/probe-meta.yaml" \
        --folder-name probe-doc "$WS/fixture.txt" > /dev/null 2>&1
    echo "  run $sfx rc=$?"
    [ "$sfx" = D1 ] && sleep 2
done
diff -r "$WS/libD1" "$WS/libD2"; drc=$?
echo "diff -r of the two libraries: rc=$drc (0 = byte-identical)"
note "modes of the new document directory and its contents (the fchmodat question):"
find "$WS/libD1/probe-doc" -exec stat -c '%a %n' {} \; | sed "s|$WS|WS|" | sort -k2

note "scout done (this script judges nothing; the numbers above feed the define's proposals)"
