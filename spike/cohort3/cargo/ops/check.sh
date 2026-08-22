#!/bin/sh
# Cohort-3 cargo define (P1) checker. Property (proposals.md P1): crash
# anywhere inside `cargo add`, and the project survives to cargo's own
# reader — the manifest parses and resolves (leg V), the dependency set
# is old-or-new and never a third thing (leg T), the source is conserved
# (leg C). The lockfile is Cargo-maintained derived state ("maintained by
# Cargo", the cargo book); leg V lets cargo's reader re-sync it, which is
# the documented ownership — L0 already judged its bytes before this ran.
# NO recovery leg, by owner ruling (proposals.md, "The torn-lock
# reading"): a lock cargo's own reader cannot open is the failure, not a
# state to repair first — cargo regenerates an ABSENT lock by itself, so
# its automatic maintenance has already had its turn.
# Every leg's rc is checked (a timeout's 124 must never read as an
# answer). Runs with the ambient CARGO_HOME the operation used.
set -u
S=${SIDEEYE_STATE_DIR:?checker needs SIDEEYE_STATE_DIR}
C=/tmp/cohort3/cargo
export CARGO_HOME="$C/home"
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

fail() { echo "checker(cargo-add): $*"; exit 1; }

[ -f "$S/Cargo.toml" ] || fail "the manifest is missing from the state dir"

# ---- leg V: cargo's own reader parses and resolves the crashed project ----
timeout 120 cargo metadata --offline --format-version 1 \
    --manifest-path "$S/Cargo.toml" > "$T/meta" 2> "$T/meta.err"
rc=$?
[ "$rc" -eq 0 ] || fail "leg V: cargo metadata exited $rc (124 = timeout): $(head -c 200 "$T/meta.err")"

# ---- leg T: the dependency set is old-or-new, never a third thing ---------
# The manifest side is the entry count; the resolution side is metadata's
# package list. A manifest that names depcrate but cannot resolve it dies
# in leg V (metadata fails), so T's own red is the count itself. The
# compact-JSON anchor ("name":"depcrate", no space) is pinned by the
# green-new drill, not by any format guarantee.
n=$(grep -c '^depcrate' "$S/Cargo.toml")
resolved=$(tr ',' '\n' < "$T/meta" | grep -c '"name":"depcrate"')
case "$n" in
    0) [ "$resolved" -eq 0 ] || fail "leg T: the manifest names no depcrate but metadata resolves it" ;;
    1) [ "$resolved" -ge 1 ] || fail "leg T: the manifest names depcrate but metadata does not resolve it" ;;
    *) fail "leg T: the manifest names depcrate $n times — neither the old state nor the completed add" ;;
esac

# ---- leg C: conservation of the source bytes ------------------------------
printf 'pub fn probe() -> u32 { 42 }\n' | cmp -s - "$S/src/lib.rs" || fail "leg C: src/lib.rs bytes changed"

exit 0
