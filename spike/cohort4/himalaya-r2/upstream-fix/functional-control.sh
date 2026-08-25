#!/bin/sh
# Does the target, un-killed, actually perform the copy?
#
# WHY THIS EXISTS. Neither the frozen checker nor the relaxed instrument pins
# the copy's presence: both accept `copy_present=no` — an empty target folder
# is one of the two states the property allows, and leg R then requires the
# reader to list zero. That is correct for judging a crash world and wrong as
# the only evidence behind "PASS 4/4 means the fix works". A build that
# returned 0 while copying nothing would satisfy the checker in every world.
#
# The engine's falsification gate does not close this either. It corrupts the
# state and requires the checker to go red, which it does through source
# conservation — leg E — and that fires whether or not a copy would ever be
# made.
#
# So this runs the operation once, un-killed, outside the engine, and asserts
# what the checker deliberately does not: exactly one entry in the target
# folder, the source's exact byte count, the source's flag suffix, and nothing
# left staged. Run it against both images; the interesting output is that both
# pass, which is what makes "the fixed build does the same job, without the
# window" a measurement rather than an assumption.
set -u
ops=$(cd "$(dirname "$0")/../ops" && pwd)
P=/tmp/cohort4/himalaya
export HOME=$P/home XDG_CONFIG_HOME=$P/xdg
fails=0
note() { printf '     %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fails=$((fails + 1)); }

printf '### target: %s\n' "$(himalaya --version | head -1)"
printf '### binary: %s\n' "$(sha256sum /usr/local/bin/himalaya | cut -c1-16)"

sh "$ops/setup.sh" || { echo "FAIL setup did not run"; exit 2; }

# The operation exactly as the define spells it, with no shim, no oracle and no
# kill: this is the target doing its job.
himalaya -c "$P/config.toml" maildir messages copy \
    '1700000000.#0M0P1.probehost' --maildir . --target Archive > /tmp/fc-out.txt 2>&1
rc=$?
[ "$rc" = "0" ] || bad "the operation exited $rc, want 0: $(head -c 200 /tmp/fc-out.txt)"

src=$P/store/cur/'1700000000.#0M0P1.probehost:2,S'
want=$(wc -c < "$src" | tr -d ' ')
note "source is $want bytes"

n=$(ls -A "$P/store/Archive/cur" | grep -c .)
[ "$n" = "1" ] || bad "the target folder holds $n entries, want exactly 1"
if [ "$n" = "1" ]; then
    name=$(ls -A "$P/store/Archive/cur")
    got=$(wc -c < "$P/store/Archive/cur/$name" | tr -d ' ')
    note "target holds $name ($got bytes)"
    [ "$got" = "$want" ] || bad "the copy is $got bytes, want $want"
    cmp -s "$src" "$P/store/Archive/cur/$name" || bad "the copy's bytes are not the source's"
    case "$name" in *:2,S) ;; *) bad "the copy lost the source's flag suffix: $name" ;; esac
fi

staged=$(find "$P/store/Archive/tmp" "$P/store/tmp" -mindepth 1 | grep -c .)
[ "$staged" = "0" ] || bad "$staged entries left staged after a completed operation"

if [ "$fails" = "0" ]; then
    echo "ok   un-killed, the operation lands exactly one complete copy and stages nothing"
else
    echo "$fails functional-control assertion(s) failed"
    exit 1
fi
