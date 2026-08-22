#!/bin/sh
# Cohort-3 probe: papis (PROTOCOL.md "Probe plans", target 5 — as amended
# 2026-08-22 before this accepted probe; probes/papis-v1.txt is the failed
# probe of the original plan, whose importer auto-matching phoned
# arxiv.org). Engine-free: normal executions only. State root: the library
# directory. Config: time-stamp False, use-cache False. Metadata rides the
# frozen YAML fixtures through `--from yaml`, which structurally skips URI
# importer matching; papis auto-generates papis_id when missing, and the
# determinism condition judges whether the fixture's value pins it. Raw
# strace log lands in $PROBE_OUT.
set -u
. "$(dirname "$0")/../../cohort2/probes/lib.sh"

WS=/tmp/probe-papis
OUT=${PROBE_OUT:-$WS}
rm -rf "$WS"; mkdir -p "$WS"

note "papis probe — $(papis --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- fixtures, byte-for-byte from the frozen (amended) plan ----------------
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

# Per-run papis config: the library section's dir must point at that run's
# library copy, so the config file is per-run ambient plumbing; its frozen
# CONTENT (time-stamp, use-cache, the library layout) is identical across
# runs and shown here once.
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

note "condition 7 — ambient: XDG_CONFIG_HOME and XDG_CACHE_HOME are created FRESH PER RUN (the reset) with the config above pointing at that run's library copy; HOME=<WS>/home fresh. use-cache=False means no cache layer should exist at all — the cache dir is shown after the runs and the closure pass measures it. The metadata fixtures live outside the state root and are read, not written."

# ---- pre-state, built once: one existing document --------------------------
mkdir -p "$WS/pre/lib"
write_config "$WS/xdg-setup" "$WS/pre/lib"
mkdir -p "$WS/cache-setup"
XDG_CONFIG_HOME="$WS/xdg-setup" XDG_CACHE_HOME="$WS/cache-setup" \
    papis add --batch --from yaml "$WS/existing-meta.yaml" \
    --folder-name existing-doc "$WS/existing.txt" > /dev/null 2>&1
echo "setup: papis add (existing doc, --from yaml) rc=$?"
echo "pre-state library:"
find "$WS/pre/lib" -mindepth 1 | sed "s|$WS|WS|" | sort

run_once() { # suffix
    sfx=$1
    cp -a "$WS/pre/lib" "$WS/lib$sfx"
    write_config "$WS/xdg-$sfx" "$WS/lib$sfx"
    mkdir -p "$WS/cache-$sfx"
    echo "reset: lib$sfx is a fresh copy of the pre-state; xdg-$sfx and cache-$sfx are fresh"
    XDG_CONFIG_HOME="$WS/xdg-$sfx" XDG_CACHE_HOME="$WS/cache-$sfx" \
        papis add --batch --from yaml "$WS/probe-meta.yaml" \
        --folder-name probe-doc "$WS/fixture.txt" 2>&1
}

note "run A"; run_once A; rcA=$?
sleep 2
note "run B (>=2s later)"; run_once B; rcB=$?

[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "run A rc=$rcA, run B rc=$rcB (success convention: 0)"

if diff -r "$WS/pre/lib" "$WS/libA" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "the library after run A differs from the pre-state"

# Exactly one new document directory, named probe-doc, holding info.yaml
# plus the copied file.
dirs=$(ls "$WS/libA" | sort | tr '\n' ' ')
inside=$(ls "$WS/libA/probe-doc" 2>/dev/null | sort | tr '\n' ' ')
[ "$dirs" = "existing-doc probe-doc " ] && [ "$inside" = "fixture.txt info.yaml " ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "library dirs are exactly 'existing-doc probe-doc' (got: '$dirs'); probe-doc holds exactly 'fixture.txt info.yaml' (got: '$inside')"

got=$(cat "$WS/libA/probe-doc/fixture.txt" 2>/dev/null)
# papis's own reading of the new document: title and papis_id through
# `papis list --format` (the bare listing prints folder paths only —
# measured; a path grep would anchor on the harness's own directory
# names, not on what papis read back).
lst=$(XDG_CONFIG_HOME="$WS/xdg-A" XDG_CACHE_HOME="$WS/cache-A" papis list --all --format '{doc[title]} {doc[papis_id]}' 2>/dev/null | grep -c '^Probe probe0001$')
# Falsification of this anchor against its own predicate (R1: the
# corrected check was never seen red in its final form): the same
# read-back matched against a WRONG id must count zero.
wrong=$(XDG_CONFIG_HOME="$WS/xdg-A" XDG_CACHE_HOME="$WS/cache-A" papis list --all --format '{doc[title]} {doc[papis_id]}' 2>/dev/null | grep -c '^Probe probe9999$')
echo "anchor drill: the same read-back against 'Probe probe9999' counts $wrong (a mismatched id goes red)"
[ "$got" = "probe document, fixed bytes" ] && [ "$lst" -eq 1 ] && [ "$wrong" -eq 0 ] && ok=yes || ok=no
verdict "4-round-trip" $ok "the copied file round-trips its bytes; papis reads back 'Probe probe0001' exactly once ($lst matching line(s); wrong-id drill counted $wrong)"
echo "info.yaml, as measured (recorded, not predicted):"
cat "$WS/libA/probe-doc/info.yaml"

note "diff -r of the two library copies (papis_id pinning is judged here):"
diff -r "$WS/libA" "$WS/libB"; drc=$?
[ "$drc" -eq 0 ] && ok=yes || ok=no
verdict "5-determinism" $ok "two runs >=2s apart leave byte-identical libraries (diff rc=$drc)"

note "strace pass (fresh copy; raw log kept as papis.strace)"
cp -a "$WS/pre/lib" "$WS/libS"
write_config "$WS/xdg-S" "$WS/libS"
mkdir -p "$WS/cache-S"
XDG_CONFIG_HOME="$WS/xdg-S" XDG_CACHE_HOME="$WS/cache-S" \
    run_strace "$WS/strace.log" papis add --batch --from yaml "$WS/probe-meta.yaml" \
    --folder-name probe-doc "$WS/fixture.txt" > /dev/null 2>&1
echo "strace'd run rc=$?"
cp "$WS/strace.log" "$OUT/papis.strace" 2>/dev/null || true
note "mutating paths (successful only, deduped):"
closure_paths "$WS/strace.log" "$WS/unattr-count" | sort -u | sed "s|$WS|WS|"
echo "unattributed count: $(cat "$WS/unattr-count" 2>/dev/null || echo '?')"
closure_check "$WS/strace.log" "$WS/libS" "$WS/xdg-S" "$WS/cache-S" "$WS/home" /tmp/
note "thread creations (successful CLONE_THREAD):"
thread_counts "$WS/strace.log"

note "condition 7 evidence — per-run cache dir after run A (use-cache=False: expected no files; the directory skeleton may appear) and HOME; the fixtures are unmutated:"
find "$WS/cache-A" | sed "s|$WS|WS|" | sort
echo "(cache entries above: directories only = no cache file was written)"
find "$HOME" -type f | sed "s|$WS|WS|" | sort
echo "(HOME files above, if any)"
printf 'probe document, fixed bytes' | cmp -s - "$WS/fixture.txt" && echo "fixture.txt: unchanged" || echo "fixture.txt: CHANGED"
printf 'existing document, fixed bytes' | cmp -s - "$WS/existing.txt" && echo "existing.txt: unchanged" || echo "existing.txt: CHANGED"
printf 'title: Probe\nauthor: Probe Author\nyear: 2026\npapis_id: probe0001\n' | cmp -s - "$WS/probe-meta.yaml" && echo "probe-meta.yaml: unchanged" || echo "probe-meta.yaml: CHANGED"
printf 'title: Existing\nauthor: Probe Author\npapis_id: existing0001\n' | cmp -s - "$WS/existing-meta.yaml" && echo "existing-meta.yaml: unchanged" || echo "existing-meta.yaml: CHANGED"

note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
