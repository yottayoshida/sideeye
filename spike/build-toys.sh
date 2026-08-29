#!/bin/sh
# Build the toy targets. Runs inside the spike container.
#
# Each one exists to make sideeye answer a different question honestly:
#   toy-bug     supported target with a real crash-consistency bug -> expect FAIL
#   toy-fixed   supported target without it                        -> expect PASS
#   toy-raw     bypasses libc entirely                             -> expect UNKNOWN
#   toy-static  no dynamic linker, so no injection at all          -> expect UNKNOWN
#   toy-rust    a real-language stand-in; what it calls is measured, not assumed
set -eu

root=${SIDEEYE_ROOT:-/work}
out=${1:-$root/spike/out}
mkdir -p "$out"

cc_flags="-O0 -g -Wall -Wextra"

echo "building toy-bug"
gcc $cc_flags -DBUGGY=1 -o "$out/toy-bug" "$root/spike/toys/toy.c" -lpthread

echo "building toy-fixed"
gcc $cc_flags -o "$out/toy-fixed" "$root/spike/toys/toy.c" -lpthread

echo "building toy-lfs"
# The same correct toy compiled with large-file support, so its fopen resolves to
# fopen64 — the glibc alias path the stdio wrappers must also cover (ADR 0005).
gcc $cc_flags -D_FILE_OFFSET_BITS=64 -o "$out/toy-lfs" "$root/spike/toys/toy.c" -lpthread

echo "building toy-raw"
gcc $cc_flags -o "$out/toy-raw" "$root/spike/toys/toy_raw.c"

echo "building toy-static"
# The static link is the point; the linker's warning about getpwnam-style lookups in
# statically linked binaries does not apply to what this toy does.
gcc $cc_flags -static -DBUGGY=1 -o "$out/toy-static" "$root/spike/toys/toy.c" -lpthread

echo "building toy-mixed"
gcc $cc_flags -o "$out/toy-mixed" "$root/spike/toys/toy_mixed.c"

echo "building toy-pwritev"
# Writes through the vectored positional calls the oracle classifies and the shim
# did not export (#256). Two iovecs, so a wrapper with the arguments in the wrong
# order writes visibly wrong bytes rather than merely mis-recording.
gcc $cc_flags -o "$out/toy-pwritev" "$root/spike/toys/toy_pwritev.c"

echo "building toy-pwritev-lfs"
# The same toy with large-file support, so its pwritev is meant to resolve to glibc's
# pwritev64 alias — the path `toy-lfs` walks for the stdio wrappers, and the reason
# the batch exports the aliases at all. Whether the build actually took that path is
# CHECKED rather than assumed: if _FILE_OFFSET_BITS stopped mattering here, the toy
# would silently fall back to plain pwritev and the leg that drives it would turn
# into a duplicate of the non-LFS one while still claiming to walk the alias.
gcc $cc_flags -D_FILE_OFFSET_BITS=64 -o "$out/toy-pwritev-lfs" "$root/spike/toys/toy_pwritev.c"
if nm -u "$out/toy-pwritev-lfs" | grep -q "pwritev64"; then
    echo "ok   toy-pwritev-lfs references pwritev64 (the alias path is real)"
else
    echo "FAIL toy-pwritev-lfs does not reference pwritev64 — the LFS leg would measure"
    echo "     the plain symbol while claiming to measure the alias"
    exit 1
fi

echo "building toy-twice"
# Succeeds once, then fails: the only target shape that shows whether `preflight
# --twice` applies its gates to the SECOND observation as well as the first (#199).
gcc $cc_flags -o "$out/toy-twice" "$root/spike/toys/toy_twice.c"

echo "building toy-copy"
# Calls copy_file_range directly, in both directions (destination inside the state
# directory, and source inside with the destination outside). The C toy is the
# primary leg for #244 precisely because it does not depend on any language
# runtime's internal choice of copy primitive.
gcc $cc_flags -o "$out/toy-copy" "$root/spike/toys/toy_copy.c"

echo "building toy-rust"
rustc -O -o "$out/toy-rust" "$root/spike/toys/toy_rust.rs"

echo "--- built ---"
ls -la "$out"

echo "--- link type check (the boundary cases must actually differ) ---"
# Decided from the ELF program headers rather than `file`'s description string: an
# INTERP segment names the dynamic loader, and its absence is what "statically linked"
# means. The first version of this check used `file`, which is not installed in the
# image — grep then matched nothing and the check reported failure for every binary.
# It failed loudly, which is the right direction, but a check that depends on an
# optional tool is a check that can also go quiet.
is_dynamic() {
    readelf -l "$1" 2>/dev/null | grep -q INTERP
}

for t in toy-bug toy-fixed toy-raw toy-rust; do
    if is_dynamic "$out/$t"; then
        echo "ok   $t is dynamically linked"
    else
        echo "FAIL $t should be dynamically linked"
        exit 1
    fi
done
if is_dynamic "$out/toy-static"; then
    echo "FAIL toy-static should be statically linked"
    exit 1
else
    echo "ok   toy-static is statically linked"
fi
