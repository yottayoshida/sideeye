#!/bin/sh
# Prove every selected target can be measured at all, before the selection is sealed (#618).
#
#   sh spike/authoring-cost/probe-selection.sh            probe and write selection-probe.txt
#   sh spike/authoring-cost/probe-selection.sh --check    re-read the committed result only
#
# PROTOCOL.md requires a target to install from the package index and to be usable with **no
# network at run time**. Neither is visible to `select-targets.sh`, which reads text files. A
# target that fails here is removed from its pool with the reason written into the pool file,
# and the selection is re-derived — before any run, so the removal is a recorded property of
# the apparatus rather than a post-hoc swap of a target that behaved inconveniently.
#
# What each probe does: build the image for that target, start it network-off, and run the pool
# row's own smoke command — the shape's actual operation, not `--version`. The first version of
# this script asked only whether some binary answered `--help`, and `apt-file` passed it while
# being unusable without the network; the smoke column exists because of that. It does not run
# Sideeye and does not write a define: that is the run's job, and doing it here would cross the
# rehearsal boundary this study is careful about.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
mode=${1:-probe}
out="$here/selection-probe.txt"

if [ "$mode" = "--check" ]; then
    [ -f "$out" ] || { echo "probe-selection: $out missing — the selection was never probed" >&2; exit 1; }
    if grep -q '^FAIL' "$out"; then
        echo "FAIL: $out records a target that could not be measured:"
        grep '^FAIL' "$out"
        exit 1
    fi
    # `grep -c` exits 1 when it counts zero, so `|| echo 0` would append a SECOND line and make
    # "$rows" the two-line string "0\n0" — the repository's own "a zero that lies" shape.
    rows=$(grep -c '^ok' "$out" || true)
    sel=$(grep -cv '^#' "$here/selection.tsv" || true)
    [ "$rows" = "$sel" ] || { echo "FAIL: $rows probe result(s) for $sel selected target(s)"; exit 1; }
    echo "ok   $rows selected target(s) probed green (from $out)"
    exit 0
fi

# The engine pin, read from the one file that owns it (spike/unknown-rate/engine-pins.tsv, the
# `g3` row). Passing it to the build keeps a second copy of the digest out of the Dockerfile,
# where it would go stale in silence the first time the pin moved.
engine_build_args() {
    row=$(grep -v '^#' "$root/spike/unknown-rate/engine-pins.tsv" | awk -F'\t' '$1 == "g3" {print; exit}')
    [ -n "$row" ] || { echo "no g3 row in engine-pins.tsv" >&2; return 1; }
    printf -- '--build-arg ENGINE_TAG=%s --build-arg ENGINE_ASSET=%s --build-arg ENGINE_SHA256=%s' \
        "$(printf '%s' "$row" | cut -f2)" "$(printf '%s' "$row" | cut -f3)" "$(printf '%s' "$row" | cut -f4)"
}

command -v docker >/dev/null || { echo "probe-selection: docker not found" >&2; exit 2; }

: > "$out"
{
    echo "# Can each selected target be measured at all? Written by probe-selection.sh."
    echo "# Probed $(date -u +%Y-%m-%dT%H:%M:%SZ), image built per target, run with --network=none."
} >> "$out"

grep -v '^#' "$here/selection.tsv" | while IFS="$(printf '\t')" read -r shape pkg _hash _why; do
    [ -n "$pkg" ] || continue
    echo "probing $pkg ($shape)" >&2
    if ! image=$(docker build -q -f "$here/Dockerfile" $(engine_build_args) --build-arg "TARGET=$pkg" "$root" 2>"$here/.probe-err"); then
        printf 'FAIL\t%s\t%s\timage build failed: %s\n' "$shape" "$pkg" "$(tail -2 "$here/.probe-err" | tr '\n' ' ')" >> "$out"
        continue
    fi
    name="authoring-probe-$pkg"
    docker rm -f "$name" >/dev/null 2>&1 || true
    docker run -d --name "$name" --network=none "$image" >/dev/null
    ver=$(docker exec "$name" sh -c "dpkg-query -W -f='\${Version}' $pkg" 2>/dev/null || echo unknown)
    bins=$(docker exec "$name" sh -c "dpkg -L $pkg 2>/dev/null | grep -c '^/usr/bin/'" 2>/dev/null || echo 0)
    smoke=$(grep -h "^$pkg	" "$here"/pool-*.txt | head -1 | cut -f3)
    if [ "$bins" = "0" ]; then
        printf 'FAIL\t%s\t%s\tinstalled %s but ships no /usr/bin program to author against\n' "$shape" "$pkg" "$ver" >> "$out"
    elif [ -z "$smoke" ]; then
        printf 'FAIL\t%s\t%s\t%s has no smoke command in its pool row\n' "$shape" "$pkg" "$ver" >> "$out"
    elif docker exec "$name" sh -c "$smoke" >/dev/null 2>&1; then
        printf 'ok\t%s\t%s\t%s\tsmoke passed offline\n' "$shape" "$pkg" "$ver" >> "$out"
    else
        printf 'FAIL\t%s\t%s\t%s: the shape own operation failed offline\n' "$shape" "$pkg" "$ver" >> "$out"
    fi
    docker rm -f "$name" >/dev/null 2>&1 || true
done

rm -f "$here/.probe-err"
cat "$out"
grep -q '^FAIL' "$out" && { echo; echo "one or more targets cannot be measured: fix the pool, re-run select-targets.sh, probe again"; exit 1; }
echo "ok   every selected target installs and answers offline"
