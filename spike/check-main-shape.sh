#!/bin/sh
# spike/check-main-shape.sh — src/main.zig only loses declarations (#572, ADR 0062).
#
# Counts the functions and the state declared by src/main.zig and fails when either count
# exceeds its ceiling. The ceilings are the counts left by the last seam that moved code out
# of the file, and they only ever come down: the pull request that moves the next boundary
# out lowers them in the same change. This is not a line-count target — #572 names that as a
# non-goal — it counts declarations, in one direction, and says where new behaviour goes:
# into the module that owns it, which main.zig's module map names.
#
# What counts as a function: a top-level `fn` with any of the modifiers Zig allows in front
# of it — `pub`, `export`, `inline`, `noinline`, and `extern` with or without a library name
# (`extern "c" fn`, which is how src/posix.zig declares libc). What counts as state: a
# top-level `var` with any of its modifiers (`pub`, `export`, `threadlocal`, `extern` with or
# without a library name), AND a `var` declared directly inside a top-level container
# (`const X = struct { var y … };`, `extern struct`, `packed struct`, `union`, `enum`,
# `opaque` alike) — that is a module-level variable with a namespace in front of it, which
# this repository uses for real state (shim/src/common.zig, shim/src/syscalls.zig), so a
# ratchet that ignored it would be a ratchet with a door in it. The first version of this
# check counted bare `fn ` and `var ` at column zero and said in its own comment that
# `pub var` does not exist in Zig, while the same pull request had declared two; the second
# version added the modifiers and missed `extern "c"`, the spelling the repository actually
# uses. Two review rounds caught the two; the selftest below tries every spelling named here.
#
# What does NOT count, deliberately: `test` blocks (tests stay beside the behaviour they
# hold; a ceiling on tests would reward moving them away from it); a `var` inside a function
# body (a local, not state); a `fn` or `var` nested deeper than one level (a struct inside a
# struct, a struct inside a function) — those belong to the declaration that holds them.
# The one-level rule is a parsing choice, not a claim that deeper nesting cannot hold state.
# "Directly inside a container" is read as exactly four spaces of indentation, which is
# what `zig fmt` produces and what every file here has; a hand-formatted one-line struct or
# a tab-indented `var` would not be counted, and nothing in CI runs `zig fmt --check` today.
#
# What this check does not decide is WHERE a declaration belongs: a function moved out of
# main.zig into the wrong module satisfies it. The module maps say where, in prose, and a
# review reads them. This removes the default of leaving things in main.zig; it is not a
# placement oracle.
#
# Exit 0: within both ceilings, counts printed. Exit 1: a ceiling exceeded, or the file
# unreadable. `--selftest`: proves the check goes red on a synthetic file one declaration
# over either ceiling — in each of the spellings above — and stays green at the ceilings with
# the non-counted forms present, then exits 0; any other outcome exits 1. CI runs the
# selftest first, so a green from a check that cannot go red is never reported.
#
# Sunset: delete this when main.zig holds `main()` and its phases and nothing else — the
# module map will say so — or when a ceiling has not moved in six months, which means the
# series has stopped and the guard is guarding a shape nobody is changing.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FN_MAX=89
VAR_MAX=32

# count <file> -> "<fn> <var>"
count() {
    awk '
    BEGIN { fn = 0; var = 0; in_type = 0 }
    # a top-level function, one-liner or not; leaves any container scope. `extern` may
    # carry a library name: `extern "c" fn`.
    /^((pub|export|inline|noinline|extern( "[A-Za-z0-9_]+")?) )*fn / { fn++; in_type = 0; next }
    # a top-level variable, same modifiers
    /^((pub|export|threadlocal|extern( "[A-Za-z0-9_]+")?) )*var / { var++; next }
    # a top-level container opens a scope in which a 4-space `var` is state
    /^((pub|export) )*const [A-Za-z_0-9]+ = (extern |packed )?(struct|union|enum|opaque)/ { in_type = ($0 !~ /};[ \t]*$/); next }
    /^};/ { in_type = 0; next }
    /^}/  { in_type = 0; next }
    in_type && /^    ((pub|export|threadlocal) )*var / { var++; next }
    END { print fn, var }
    ' "$1"
}

# judge <file> <label> -> 0 within ceilings, 1 over (message on stdout)
judge() {
    f=$1; label=$2
    [ -r "$f" ] || { echo "FAIL $label: cannot read $f"; return 1; }
    set -- $(count "$f")
    fn=${1:-0}; var=${2:-0}
    rc=0
    if [ "$fn" -gt "$FN_MAX" ]; then
        echo "FAIL $label declares $fn top-level fn, ceiling $FN_MAX (#572, ADR 0062): a new function"
        echo "     goes into the module that owns the behaviour — see the module map at the top of"
        echo "     src/main.zig. Lower the ceiling only in the pull request that moves code out."
        rc=1
    fi
    if [ "$var" -gt "$VAR_MAX" ]; then
        echo "FAIL $label declares $var module-level var, ceiling $VAR_MAX (#572, ADR 0062): new run or"
        echo "     report state gets an owner outside src/main.zig; the module map says which."
        rc=1
    fi
    [ "$rc" = 0 ] && echo "ok   $label: $fn top-level fn (ceiling $FN_MAX), $var module-level var (ceiling $VAR_MAX)"
    return $rc
}

if [ "${1:-}" = "--selftest" ]; then
    tmp=$(mktemp -d) || { echo "FAIL selftest: cannot create a temp directory"; exit 1; }
    cleanup() { rm -f "$tmp"/*; rmdir "$tmp" 2>/dev/null; }
    trap cleanup EXIT HUP INT TERM
    # synth <file> <plain-fn> <plain-var>: a file whose counted declarations are the plain
    # ones asked for PLUS five functions in the other spellings (outer, export, pub inline,
    # noinline, extern) and three variables in theirs (pub, threadlocal, struct-scope pub),
    # PLUS the forms that must not count: tests holding locals, a function holding a local
    # and a nested struct, a container holding a method with a local, a comment saying `fn `.
    synth() {
        f=$1; nf=$2; nv=$3
        : > "$f"
        i=0; while [ "$i" -lt "$nf" ]; do
            if [ $((i % 2)) = 0 ]; then echo "fn f$i() void {}" >> "$f"; else echo "pub fn f$i() void {}" >> "$f"; fi
            i=$((i + 1)); done
        i=0; while [ "$i" -lt "$nv" ]; do echo "var v$i: u32 = 0;" >> "$f"; i=$((i + 1)); done
        cat >> "$f" <<'EOF'
export fn exported() void {}
pub inline fn inlined() void {}
noinline fn not_inlined() void {}
extern fn prototype() void;
pub var smuggled: u32 = 0;
threadlocal var per_thread: u32 = 0;
const Holder = struct {
    pub var namespaced_state: u32 = 0;
    fn method() void {
        var local: u32 = 0;
        _ = local;
    }
};
test "a test is not a declaration this check counts" {
    var local_in_test: u32 = 0;
    _ = local_in_test;
}
fn outer() void {
    var local_in_fn: u32 = 0;
    _ = local_in_fn;
    const helper = struct {
        var nested_two_deep: u32 = 0;
        fn inner() void {}
    };
    _ = helper;
}
const E = enum { a, b };
// fn in a comment is not a declaration either, nor is var here
EOF
    }
    fails=0
    # at the ceilings: five special functions and three special variables are in the decoy
    # block, so synth is asked for that many fewer plain ones.
    synth "$tmp/at" $((FN_MAX - 5)) $((VAR_MAX - 3))
    if judge "$tmp/at" "selftest at-ceiling" > /dev/null; then
        echo "ok   selftest: at the ceilings — with tests, locals, a nested struct and a comment present — is green"
    else echo "FAIL selftest: a file exactly at both ceilings was reported over: $(count "$tmp/at")"; fails=$((fails + 1)); fi
    red() { # red <label> <extra line>
        cp "$tmp/at" "$tmp/over"; printf '%s\n' "$2" >> "$tmp/over"
        if judge "$tmp/over" "selftest $1" > /dev/null; then echo "FAIL selftest: $1 was not caught"; fails=$((fails + 1))
        else echo "ok   selftest: $1 is red"; fi
    }
    red "one more plain fn"          "fn one_too_many() void {}"
    red "one more export fn"         "export fn one_too_many() void {}"
    red "one more pub inline fn"     "pub inline fn one_too_many() void {}"
    red "one more noinline fn"       "noinline fn one_too_many() void {}"
    red "one more extern fn"         "extern fn one_too_many() void;"
    red "one more extern \"c\" fn"   "pub extern \"c\" fn one_too_many(n: usize) c_int;"
    red "one more plain var"         "var one_too_many: u32 = 0;"
    red "one more pub var"           "pub var one_too_many: u32 = 0;"
    red "one more threadlocal var"   "threadlocal var one_too_many: u32 = 0;"
    red "one more extern \"c\" var"  "pub extern \"c\" var one_too_many: [*][*:0]u8;"
    red "one more struct-scope var"  "const Another = struct {
    var one_too_many: u32 = 0;
};"
    red "one more extern-struct var" "const Foreign = extern struct {
    var one_too_many: u32 = 0;
};"
    red "one more union(enum) var"   "const Either = union(enum) {
    var one_too_many: u32 = 0;
};"
    green() { # green <label> <extra line>
        cp "$tmp/at" "$tmp/still"; printf '%s\n' "$2" >> "$tmp/still"
        if judge "$tmp/still" "selftest $1" > /dev/null; then echo "ok   selftest: $1 stays green"
        else echo "FAIL selftest: $1 was counted: $(count "$tmp/still")"; fails=$((fails + 1)); fi
    }
    green "one more test block"      'test "another" {}'
    green "a local inside a new test" 'test "with a local" {
    var l: u32 = 0;
    _ = l;
}'
    judge "$tmp/does-not-exist" "selftest unreadable" > /dev/null && { echo "FAIL selftest: an unreadable file was reported green"; fails=$((fails + 1)); } \
        || echo "ok   selftest: an unreadable file is red, not silently green"
    [ "$fails" = 0 ] || exit 1
    exit 0
fi

judge "${MAIN_ZIG:-$ROOT/src/main.zig}" "src/main.zig"
