#!/bin/sh
# Cohort-3 cargo checker (spike/cohort3/cargo-r2/ops/check.sh), byte-identical in its legs;
# only the root comes from CARGO_ROOT. Property (r1 proposals, unchanged): crash anywhere inside
# `cargo add`, and the project survives to cargo's own reader — the manifest parses and
# resolves (leg V), the dependency set is old-or-new and never a third thing (leg T), the source
# is conserved (leg C). No recovery leg, by owner ruling ("The torn-lock reading"). Every leg's
# rc is checked (a timeout's 124 must never read as an answer). `unset RUSTC`: where the driver
# exported the stand-in, the checker still runs stock cargo's own reader against the real rustc.
set -u
S=${SIDEEYE_STATE_DIR:?checker needs SIDEEYE_STATE_DIR}
C=${CARGO_ROOT:?checker needs CARGO_ROOT}
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
