#!/bin/sh
# The r2 setup plus the RUSTC stand-in (owner-approved for cohort 3, 2026-08-22;
# spike/cohort3/cargo-r2/proposals.md): a shell script that answers `-vV` with the bytes the
# real rustc prints and refuses everything else. r2 embedded the 2026-08-22 image's bytes
# (rustc 1.98.0); this one MEASURES the image's own `rustc -vV` at setup time and writes that,
# so the stand-in never claims a version the checker's real rustc does not have. Used only by
# configurations C and D (the comparison against r2), which the driver runs only when A or B
# leaves something to compare.
set -eu
C=${CARGO_ROOT:?setup needs CARGO_ROOT}
sh "$(dirname "$0")/setup.sh"
rm -f "$C/rustc-standin"
unset RUSTC
vv=$(rustc -vV)
{
    printf '#!/bin/sh\ncase " $* " in\n    *" -vV "*) cat <<'"'"'VV'"'"'\n'
    printf '%s\n' "$vv"
    printf 'VV\n    ;;\n    *) echo "rustc-standin: unsupported argv: $*" >&2; exit 90 ;;\nesac\n'
} > "$C/rustc-standin"
chmod 755 "$C/rustc-standin"
