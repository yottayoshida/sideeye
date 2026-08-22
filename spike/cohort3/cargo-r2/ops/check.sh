#!/bin/sh
# Cohort-3 cargo define r2 checker: byte-identical logic to r1's, two
# deliberate deltas — the paths, and `unset RUSTC`: the launcher's
# stand-in serves the RECORDED OPERATION only, and `cargo metadata`
# genuinely needs the real rustc (its target-info probe asks for more
# than -vV — measured, proposals.md here). The checker runs outside the
# recording; its job is stock cargo's own reader. Property (r1
# proposals, unchanged): crash anywhere inside `cargo add`, and the
# project survives to cargo's own reader — the manifest parses and
# resolves (leg V), the dependency set is old-or-new and never a third
# thing (leg T), the source is conserved (leg C). NO recovery leg, by
# owner ruling (../../cargo/proposals.md, "The torn-lock reading").
# Every leg's rc is checked (a timeout's 124 must never read as an
# answer).
set -u
S=${SIDEEYE_STATE_DIR:?checker needs SIDEEYE_STATE_DIR}
C=/tmp/cohort3/cargo-r2
export CARGO_HOME="$C/home"
unset RUSTC
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
