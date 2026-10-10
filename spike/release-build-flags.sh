#!/bin/sh
# spike/release-build-flags.sh — what release.yml builds one artifact with (#694).
#
#   sh spike/release-build-flags.sh <release.yml> <artifact>          the `zig build` arguments
#   sh spike/release-build-flags.sh --runner <release.yml> <artifact>  the entry's runner
#   sh spike/release-build-flags.sh --zig <release.yml>                the Zig version set up
#   sh spike/release-build-flags.sh --selftest
#
# ci.yml's ReleaseSafe aarch64-linux job runs the acceptance suite against the build the release
# ships. It reads the arguments from release.yml rather than spelling them, so a release that changes
# its build line — the optimisation, the triple, a flag added — moves that job with it; a value
# spelled in ci.yml would be one more copy to drift, and the job would go on testing a build nobody
# ships, green. The runner and the Zig version a job fixes before any step runs, so the job compares
# those with what this prints.
#
# The arguments are everything after `zig build` on the one line outside a comment that runs it —
# and that line must build `-Dtarget=${{ matrix.target }}` — a trailing comment dropped, with the
# matrix entry's own `target:` put in for that expression. Exits 1, naming what it could not read,
# when the entry or the line is missing or ambiguous (a second build step included), when the line
# names no `-Doptimize=`, another `${{ … }}` expression, or shell beyond zig's arguments — never a
# default, which is the shape that keeps a job green after the file it reads has moved on.
set -u

# The value of <field> in the one matrix entry (under `include:`) whose artifact is <artifact>,
# whatever order the entry's keys come in; "ENTRIES=<n>" when not exactly one entry matches.
entry_field() { # <release.yml> <artifact> <field>
    awk -v art="$2" -v key="$3" '
        function keyval(s,   k) {
            sub(/^[[:space:]]*(-[[:space:]]+)?/, "", s)
            k = s; sub(/:.*/, "", k)
            sub(/^[^:]*:[[:space:]]*/, "", s)
            f[k] = s
            if (k == "artifact") a = s
        }
        function close_entry() {
            if (open_ && a == art) { seen++; if (key in f) print f[key] }
            for (k in f) delete f[k]
            a = ""; open_ = 0
        }
        /^[[:space:]]*include:[[:space:]]*$/ { inc = 1; next }
        inc && /^[[:space:]]*-[[:space:]]+[A-Za-z_-]+:/ { close_entry(); open_ = 1; keyval($0); next }
        inc && open_ && /^[[:space:]]+[A-Za-z_-]+:[[:space:]]*[^[:space:]]/ { keyval($0); next }
        inc && /^[[:space:]]*[A-Za-z_-]+:/ { close_entry(); inc = 0 }
        END { close_entry(); if (seen != 1) print "ENTRIES=" seen + 0 }
    ' "$1"
}

one() { # <what> <value>: the value when it is exactly one line, or the reason it is not
    case "$2" in *ENTRIES=*) echo "release-build-flags: $(printf '%s\n' "$2" | sed -n 's/^ENTRIES=//p') matrix entries with that artifact, not one" >&2; return 1 ;; esac
    n=$(printf '%s\n' "$2" | grep -c .)
    [ "$n" = 1 ] || { echo "release-build-flags: $n values for $1, not one" >&2; return 1; }
    printf '%s\n' "$2"
}

flags_of() { # <release.yml> <artifact>
    yml=$1 art=$2
    [ -f "$yml" ] || { echo "release-build-flags: no such file: $yml" >&2; return 1; }
    target=$(one "the '$art' entry's target" "$(entry_field "$yml" "$art" target)") || return 1
    builds=$(grep -E '^[^#]*zig build' "$yml")
    line=$(one "the zig build lines outside comments" "$builds") || return 1
    # shellcheck disable=SC2016 # the expression is matched literally, not expanded
    case "$line" in *'-Dtarget=${{ matrix.target }}'*) ;; *) echo "release-build-flags: the build line does not build the matrix target: $line" >&2; return 1 ;; esac
    args=$(printf '%s\n' "$line" | sed -e 's/^[^#]*zig build//' -e 's/[[:space:]]#.*$//' \
        -e "s/\${{ matrix.target }}/$target/" -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    case "$args" in *'${{'*) echo "release-build-flags: the build line carries an expression other than matrix.target: $args" >&2; return 1 ;; esac
    # Shell on the line — a continuation, a second command — would reach zig as step names; refuse
    # it here, by name.
    case "$args" in *\\|*'&&'*|*'||'*|*';'*|*'|'*|*'>'*|*'<'*|*'`'*|*'$('*)
        echo "release-build-flags: the build line carries shell beyond zig's arguments: $args" >&2; return 1 ;; esac
    nopt=$(printf '%s\n' "$args" | tr ' ' '\n' | grep -c '^-Doptimize=')
    [ "$nopt" = 1 ] || { echo "release-build-flags: the build line names $nopt -Doptimize=, not one" >&2; return 1; }
    printf '%s\n' "$args"
}

zig_of() { # <release.yml>: the `version:` under the setup-zig step
    awk '/uses:[[:space:]]*mlugg\/setup-zig@/ { s = 1; next } s && $1 == "version:" { print $2; s = 0 } /^[[:space:]]*- / && !/setup-zig/ { s = 0 }' "$1"
}

if [ "${1:-}" = "--selftest" ]; then
    tmp=$(mktemp -d) || exit 1
    trap 'rm -rf "$tmp"' EXIT
    # The shape release.yml has today, cut to what is read.
    cat > "$tmp/base.yml" <<'YML'
jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - runner: ubuntu-latest
            artifact: x86_64-linux
            target: x86_64-linux-gnu.2.28
          - runner: ubuntu-24.04-arm
            artifact: aarch64-linux
            target: aarch64-linux-gnu.2.28
          - runner: macos-latest
            artifact: aarch64-macos
            target: aarch64-macos
    runs-on: ${{ matrix.runner }}
    steps:
      - uses: mlugg/setup-zig@d1434d08867e3ee9daa34448df10607b98908d29 # v2
        with:
          version: 0.16.0
      # A comment that mentions zig build -Doptimize=Debug -Dtarget=${{ matrix.target }} is not the build.
      - name: Build (ReleaseSafe, baseline CPU)
        run: zig build -Doptimize=ReleaseSafe -Dtarget=${{ matrix.target }}
YML
    # The same entries with aarch64-linux's keys in another order, its runner last.
    cat > "$tmp/runner-last.yml" <<'YML'
jobs:
  build:
    strategy:
      matrix:
        include:
          - runner: ubuntu-24.04-arm
            artifact: x86_64-linux
            target: x86_64-linux-gnu.2.28
          - target: aarch64-linux-gnu.2.28
            artifact: aarch64-linux
            runner: ubuntu-26.04-arm
    steps:
      - run: zig build -Doptimize=ReleaseSafe -Dtarget=${{ matrix.target }}
YML
    fails=0
    want() { # <label> <expected output, or FAIL> <file> [mode]
        if [ "${4:-}" = runner ]; then got=$(one runner "$(entry_field "$3" aarch64-linux runner)" 2>/dev/null); rc=$?
        elif [ "${4:-}" = zig ]; then got=$(one zig "$(zig_of "$3")" 2>/dev/null); rc=$?
        else got=$(flags_of "$3" aarch64-linux 2>/dev/null); rc=$?; fi
        if [ "$2" = FAIL ]; then
            [ "$rc" != 0 ] && echo "ok   $1: refused" || { echo "FAIL $1: printed '$got' where it must refuse"; fails=$((fails + 1)); }
        else
            [ "$rc" = 0 ] && [ "$got" = "$2" ] && echo "ok   $1: $got" || { echo "FAIL $1: got '$got' (exit $rc), wanted '$2'"; fails=$((fails + 1)); }
        fi
    }
    want "today's shape" "-Doptimize=ReleaseSafe -Dtarget=aarch64-linux-gnu.2.28" "$tmp/base.yml"
    sed -e 's/aarch64-linux-gnu.2.28/aarch64-linux-gnu.2.31/' -e 's/-Doptimize=ReleaseSafe/-Doptimize=ReleaseFast/' "$tmp/base.yml" > "$tmp/moved.yml"
    want "release.yml moved both values: the flags follow" "-Doptimize=ReleaseFast -Dtarget=aarch64-linux-gnu.2.31" "$tmp/moved.yml"
    sed 's/target }}$/target }} -Dcpu=baseline -Dstrip=true/' "$tmp/base.yml" > "$tmp/more.yml"
    want "a flag added to the build line: carried" "-Doptimize=ReleaseSafe -Dtarget=aarch64-linux-gnu.2.28 -Dcpu=baseline -Dstrip=true" "$tmp/more.yml"
    sed 's/target }}$/target }}  # was -Doptimize=Debug/' "$tmp/base.yml" > "$tmp/comment.yml"
    want "a trailing comment on the build line: dropped" "-Doptimize=ReleaseSafe -Dtarget=aarch64-linux-gnu.2.28" "$tmp/comment.yml"
    sed 's/target }}$/target }} -Dversion=${{ inputs.tag }}/' "$tmp/base.yml" > "$tmp/expr.yml"
    want "another expression on the build line" FAIL "$tmp/expr.yml"
    sed 's/target }}$/target }} \\/' "$tmp/base.yml" > "$tmp/continued.yml"
    want "a line continued with a backslash" FAIL "$tmp/continued.yml"
    sed 's/target }}$/target }} \&\& strip zig-out\/bin\/sideeye/' "$tmp/base.yml" > "$tmp/chained.yml"
    want "another command chained on the line" FAIL "$tmp/chained.yml"
    { cat "$tmp/base.yml"; printf '%s\n' "      - name: Build aarch64-linux alone" \
        "        if: matrix.artifact == 'aarch64-linux'" \
        "        run: zig build -Doptimize=ReleaseFast -Dtarget=aarch64-linux-gnu.2.28"; } > "$tmp/second-build.yml"
    want "a second build step in the file" FAIL "$tmp/second-build.yml"
    grep -v 'target: aarch64-linux-gnu' "$tmp/base.yml" > "$tmp/no-target.yml"
    want "the entry's target line removed" FAIL "$tmp/no-target.yml"
    sed 's/ -Doptimize=ReleaseSafe//' "$tmp/base.yml" > "$tmp/no-optimize.yml"
    want "the build line without -Doptimize" FAIL "$tmp/no-optimize.yml"
    sed 's/artifact: x86_64-linux/artifact: aarch64-linux/' "$tmp/base.yml" > "$tmp/twice.yml"
    want "two entries named aarch64-linux" FAIL "$tmp/twice.yml"
    sed 's/artifact: aarch64-linux/artifact: arm64-linux/' "$tmp/base.yml" > "$tmp/renamed.yml"
    want "the artifact renamed" FAIL "$tmp/renamed.yml"
    want "the entry's runner" "ubuntu-24.04-arm" "$tmp/base.yml" runner
    sed 's/runner: ubuntu-24.04-arm/runner: ubuntu-26.04-arm/' "$tmp/base.yml" > "$tmp/runner.yml"
    want "the entry's runner moved: it follows" "ubuntu-26.04-arm" "$tmp/runner.yml" runner
    want "the entry's runner on its last line, not its first" "ubuntu-26.04-arm" "$tmp/runner-last.yml" runner
    want "the Zig version set up" "0.16.0" "$tmp/base.yml" zig
    sed 's/version: 0.16.0/version: 0.17.0/' "$tmp/base.yml" > "$tmp/zig.yml"
    want "the Zig version moved: it follows" "0.17.0" "$tmp/zig.yml" zig
    [ "$fails" = 0 ] && echo "ok   release-build-flags selftest: 17 of 17" || { echo "FAIL release-build-flags selftest: $fails"; exit 1; }
    exit 0
fi

case "${1:-}" in
    --runner) [ "$#" = 3 ] || { echo "usage: release-build-flags.sh --runner <release.yml> <artifact>" >&2; exit 2; }
              one "the '$3' entry's runner" "$(entry_field "$2" "$3" runner)" ;;
    --zig)    [ "$#" = 2 ] || { echo "usage: release-build-flags.sh --zig <release.yml>" >&2; exit 2; }
              one "the setup-zig version" "$(zig_of "$2")" ;;
    *)        [ "$#" = 2 ] || { echo "usage: release-build-flags.sh [--runner|--zig] <release.yml> [<artifact>] | --selftest" >&2; exit 2; }
              flags_of "$1" "$2" ;;
esac
