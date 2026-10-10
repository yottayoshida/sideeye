#!/bin/sh
# Judges one lane of .github/workflows/zig-ahead.yml against the breakages already known
# (#698, ADR 0111).
#
#   zig-ahead.sh judge <known.tsv> <os> <lane> <zig version> <exit status> <log>
#   zig-ahead.sh lint <known.tsv>
#   zig-ahead.sh --selftest
#
# Why a judge and not the build's exit status: Zig 0.17.0 shipped on 2026-10-01 and does not
# build Sideeye (#782), so a lane that simply went red on a failed build would be red from its
# first run until #782 lands — and a second, different breakage arriving in the meantime would
# change nothing anyone sees. Red has to mean "something not already written down".
#
# Contract (one lane, one verdict; exit 0 is green):
#
#   * lane `pinned` — the Zig `build.zig.zon` names — must build and pass its tests. It never
#     consults the list. It is the run's comparison: if every lane is red, this one says whether
#     Zig broke Sideeye or the workflow broke itself.
#   * lanes `latest` and `master` look up the rows for their OS (`linux`, `macos`, or `*` for
#     both — a release can break one OS's code only, and Linux does not even analyse the macOS
#     branches) and their key: the latest release's MAJOR.MINOR, so a point release meets the
#     same row; `master` for master.
#     - built and tested, no row: green.
#     - built and tested, a row: RED — the row is stale; the change that fixed the breakage
#       removes it.
#     - failed, every compiler diagnostic (`path:line:col: error: …`) contains the text of one
#       of the rows, and every row's text appears in some diagnostic: green, naming the issues.
#       Order is not read: once a breakage moves past build.zig, the executable, the shim and
#       the test roots fail in parallel, and which diagnostic prints first changes from run to
#       run. Summary lines (`error: 2 compilation errors`) are not diagnostics and are not read.
#     - failed with a diagnostic no row explains: RED.
#     - failed, and a row's text appears in no diagnostic: RED — that breakage is gone and its
#       row is stale, even though the lane still fails on another. Which is why a row may name
#       only a breakage the lane prints today: one hidden behind an earlier breakage (Zig stops
#       at build.zig before compiling anything else) reads as gone, and is written when it shows.
#     - failed with no diagnostic at all (a download that failed, a test that failed, a link
#       error, a crash): RED. A test failure cannot ride beside a known diagnostic in one lane:
#       the workflow runs the tests only once the build has passed. A link error can, once a
#       breakage is past build.zig and one artifact links while another fails to compile — then
#       a known diagnostic beside it hides it. While the build stops at build.zig, as it does for
#       every row written so far, nothing links at all.
#   * on the `latest` lane, any row keyed to a release that is not the latest is RED: once the
#     latest moves on, such a row is never looked up again, so the stale rule above could never
#     fire for it.
#
# What it does not do: decide anything about the build itself. It reads a status and a log.

set -u

minor_of() {
    printf '%s\n' "$1" | sed -n 's/^\([0-9][0-9]*\.[0-9][0-9]*\)\..*$/\1/p'
}

# lint <known>: every row that is not a comment or blank has four tab-separated columns — an
# OS (`linux`, `macos`, `*`), a key (`master` or MAJOR.MINOR), a text of at least ten
# characters that neither starts nor ends with a space, an issue (`#N`). A row that does not
# parse would otherwise match nothing and turn a known breakage red a week after the edit that
# broke it; a text of a space or two would match every diagnostic and explain away anything.
lint() {
    awk -F'\t' '
        /^#/ || $0 == "" { next }
        {
            ok = (NF == 4) && ($1 == "linux" || $1 == "macos" || $1 == "*") \
                 && ($2 == "master" || $2 ~ /^[0-9]+\.[0-9]+$/) && (length($3) >= 10) && ($3 !~ /^[ ]|[ ]$/) && ($4 ~ /^#[0-9]+$/)
            if (!ok) { printf "FAIL %s:%d: not <os> TAB <master|MAJOR.MINOR> TAB <text of 10+ characters, no space at either end> TAB <#N>: %s\n", FILENAME, NR, $0; bad = 1 }
            rows++
        }
        END {
            if (!bad) printf "ok   %s: %d row(s), every one <os> <key> <text of 10+ characters> <#N>\n", FILENAME, rows
            exit bad
        }' "$1"
}

# explained <line> <texts>: 0 when the line contains one of the newline-separated texts, as a
# fixed string. Kept out of the command substitution in `judge`: the shell macOS ships as
# /bin/sh (bash 3.2) reads a `case` pattern's `)` inside `$( … )` as the substitution's end.
# The loop runs in an explicit subshell: ksh and zsh run a pipeline's last element in the
# current shell, where its `exit` would end the caller's `$( … )` at the first match and drop
# every line after it — unexplained ones included, so the verdict would fall to green.
explained() {
    printf '%s\n' "$2" | (
        while IFS= read -r t; do
            [ -n "$t" ] || continue
            case $1 in
                *"$t"*) exit 0 ;;
            esac
        done
        exit 1
    )
}

judge() {
    known=$1 os=$2 lane=$3 version=$4 exit_status=$5 log=$6
    case $os in linux | macos) ;; *) echo "FAIL unknown os '$os' (linux or macos)"; return 1 ;; esac
    case $exit_status in '' | *[!0-9]*) echo "FAIL exit status '$exit_status' is not a number"; return 1 ;; esac
    [ -r "$log" ] || { echo "FAIL no log at $log"; return 1; }
    lint "$known" >/dev/null || { lint "$known"; return 1; }

    case $lane in
        pinned)
            if [ "$exit_status" -eq 0 ]; then
                echo "ok   $os pinned $version: builds and its tests pass"
                return 0
            fi
            echo "FAIL $os pinned $version: the Zig build.zig.zon names did not build and test Sideeye (status $exit_status) — the workflow or the runner is broken, not a new Zig"
            tail -n 30 "$log"
            return 1
            ;;
        latest)
            key=$(minor_of "$version")
            [ -n "$key" ] || { echo "FAIL $os latest: cannot read MAJOR.MINOR from '$version'"; return 1; }
            stale=$(awk -F'\t' -v key="$key" '/^#/ || $0 == "" { next } $2 != "master" && $2 != key { printf "  %s:%d: %s\n", FILENAME, NR, $0 }' "$known")
            if [ -n "$stale" ]; then
                echo "FAIL $os latest $version: the list holds rows for a release that is no longer the latest — they can never be looked up again; remove them"
                printf '%s\n' "$stale"
                return 1
            fi
            ;;
        master) key=master ;;
        *) echo "FAIL unknown lane '$lane' (pinned, latest or master)"; return 1 ;;
    esac

    # This lane's rows, once: `<text> TAB <issue>` per line.
    rows=$(awk -F'\t' -v os="$os" -v key="$key" '/^#/ || $0 == "" { next } ($1 == os || $1 == "*") && $2 == key { print $3 "\t" $4 }' "$known")
    texts=$(printf '%s\n' "$rows" | cut -f1 | sed '/^$/d')
    issues=$(printf '%s\n' "$rows" | cut -f2 | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ $//')

    if [ "$exit_status" -eq 0 ]; then
        if [ -n "$texts" ]; then
            echo "FAIL $os $lane $version: builds and its tests pass, but the list still holds a breakage for $os $key ($issues) — remove the row"
            return 1
        fi
        echo "ok   $os $lane $version: builds and its tests pass"
        return 0
    fi

    diags=$(grep -E '^[^[:space:]][^:]*:[0-9]+:[0-9]+: error: ' "$log")
    if [ -z "$diags" ]; then
        echo "FAIL $os $lane $version: failed (status $exit_status) with no compiler diagnostic in the log — not a breakage the list can know"
        tail -n 30 "$log"
        return 1
    fi
    unexplained=$(printf '%s\n' "$diags" | while IFS= read -r line; do
        explained "$line" "$texts" || printf '  %s\n' "$line"
    done)
    if [ -n "$unexplained" ]; then
        echo "FAIL $os $lane $version: a breakage the list does not explain${issues:+ (known for $os $key: $issues)}:"
        printf '%s\n' "$unexplained"
        return 1
    fi
    # The other direction: a row no diagnostic shows is a breakage that is gone. The lane still
    # fails on the rest, so the "builds while a row remains" rule above cannot catch it.
    gone=$(printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r t issue; do
        [ -n "$t" ] || continue
        printf '%s\n' "$diags" | grep -qF -- "$t" || printf '  %s (%s)\n' "$t" "$issue"
    done)
    if [ -n "$gone" ]; then
        echo "FAIL $os $lane $version: still fails, but no diagnostic shows these listed breakages — fixed, or hidden behind an earlier one; a row may name only what the lane prints, so remove them:"
        printf '%s\n' "$gone"
        return 1
    fi
    n=$(printf '%s\n' "$diags" | grep -c .)
    echo "ok   $os $lane $version: does not build, and all $n diagnostic(s) are known ($issues)"
    return 0
}

# --selftest: every rule above, each driven red or green from a log and a list written here.
# The positive controls are first-class cases, not an afterthought: a judge that always says
# FAIL passes every red case.
selftest() {
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/zig-ahead-selftest-XXXXXX") || {
        echo "FAIL selftest: could not create a scratch directory" >&2
        return 1
    }
    trap '[ -n "${tmp:-}" ] && { rm -f "$tmp"/* 2>/dev/null; rmdir "$tmp" 2>/dev/null; }' EXIT INT TERM
    fails=0
    T=$(printf '\t')
    args="no field named 'args' in struct 'Build'"
    star="no field named 'star' in struct 'Build'"

    printf '# comment\n\n*%s0.17%s%s%s#782\n*%smaster%s%s%s#782\nmacos%s0.17%sno member named mac_only%s#790\n' \
        "$T" "$T" "$args" "$T" "$T" "$T" "$args" "$T" "$T" "$T" "$T" > "$tmp/known.tsv"
    printf '*%s0.16%s%s%s#782\n' "$T" "$T" "$args" "$T" > "$tmp/stale.tsv"
    cat "$tmp/known.tsv" "$tmp/stale.tsv" > "$tmp/known-plus-stale.tsv"
    printf '*%s0.17%s%s\n' "$T" "$T" "$args" > "$tmp/malformed.tsv"
    # Two breakages listed for one lane; the logs below show one, or both.
    printf '*%s0.17%s%s%s#782\n*%s0.17%s%s%s#799\n' "$T" "$T" "$args" "$T" "$T" "$T" "$star" "$T" > "$tmp/two-rows.tsv"
    # A text of one space matches every diagnostic, and so would explain anything; lint refuses it.
    printf '*%s0.17%s %s#782\n' "$T" "$T" "$T" > "$tmp/blank-text.tsv"
    # No space, but short enough to be in every diagnostic — `error` is: refused by the length.
    printf '*%s0.17%serror%s#782\n' "$T" "$T" "$T" > "$tmp/short-text.tsv"
    # Long enough, but with a space at its end: refused too, by the other half of the rule.
    printf '*%s0.17%s%s %s#782\n' "$T" "$T" "$args" "$T" > "$tmp/trailing-space.tsv"
    : > "$tmp/empty.tsv"

    printf 'build.zig:612:11: error: %s\n    if (b.args) |args| run_cmd.addArgs(args);\nlib/std/Build.zig:1:1: note: struct declared here\n' "$args" > "$tmp/args.log"
    printf 'src/a.zig:1:2: error: %s\nshim/b.zig:3:4: error: %s\nerror: 2 compilation errors\n' "$args" "$args" > "$tmp/two-known.log"
    printf 'shim/b.zig:3:4: error: %s\nerror: 2 compilation errors\nsrc/a.zig:1:2: error: %s\n' "$args" "$args" > "$tmp/two-known-swapped.log"
    printf 'src/a.zig:1:2: error: %s\nsrc/c.zig:5:6: error: %s\n' "$args" "$star" > "$tmp/one-new.log"
    printf 'error: unable to download https://ziglang.org/builds/zig.tar.xz\n' > "$tmp/no-diag.log"
    printf 'src/m.zig:9:9: error: no member named mac_only\n' > "$tmp/mac-only.log"
    printf 'src/c.zig:5:6: error: %s\n' "$star" > "$tmp/star-only.log"
    printf 'src/m.zig:9:9: error: no member named mac_only\nbuild.zig:612:11: error: %s\n' "$args" > "$tmp/mac-and-args.log"
    printf 'src/a.zig:1:2: error: %s\nsrc/c.zig:5:6: error: %s\n' "$args" "$star" > "$tmp/args-and-star.log"
    : > "$tmp/clean.log"

    # case: expected-exit  known  os  lane  version  status  log
    while IFS='|' read -r want k o l v s g; do
        [ -n "$want" ] || continue
        out=$(judge "$tmp/$k" "$o" "$l" "$v" "$s" "$tmp/$g" 2>&1)
        got=$?
        if [ "$got" -ne "$want" ]; then
            echo "FAIL selftest: judge $k $o $l $v status=$s $g exited $got, want $want:" >&2
            printf '%s\n' "$out" | sed 's/^/     /' >&2
            fails=$((fails + 1))
        fi
    done <<EOF
0|known.tsv|linux|pinned|0.16.0|0|clean.log
1|known.tsv|linux|pinned|0.16.0|1|args.log
0|empty.tsv|linux|latest|0.18.0|0|clean.log
1|known.tsv|linux|latest|0.17.0|0|clean.log
1|known-plus-stale.tsv|linux|latest|0.17.0|1|args.log
0|known.tsv|linux|latest|0.17.0|1|args.log
0|known.tsv|linux|latest|0.17.1|1|args.log
1|known.tsv|linux|latest|0.18.0|1|args.log
1|empty.tsv|linux|latest|0.18.0|1|args.log
0|known.tsv|linux|master|0.18.0-dev.131+41f885830|1|two-known.log
0|known.tsv|linux|master|0.18.0-dev.131+41f885830|1|two-known-swapped.log
1|known.tsv|linux|master|0.18.0-dev.131+41f885830|1|one-new.log
1|known.tsv|linux|master|0.18.0-dev.131+41f885830|1|no-diag.log
1|known.tsv|linux|latest|0.17.0|1|mac-only.log
0|known.tsv|macos|latest|0.17.0|1|mac-and-args.log
1|malformed.tsv|linux|latest|0.17.0|1|args.log
1|known.tsv|windows|latest|0.17.0|1|args.log
1|two-rows.tsv|linux|latest|0.17.0|1|star-only.log
0|two-rows.tsv|linux|latest|0.17.0|1|args-and-star.log
1|blank-text.tsv|linux|latest|0.17.0|1|one-new.log
1|trailing-space.tsv|linux|latest|0.17.0|1|args.log
EOF

    # Lint itself, not only through a verdict: a text with a space at an end matches nothing, so
    # the verdict above stays red without the rule and cannot show it working.
    for bad in blank-text short-text trailing-space malformed; do
        if lint "$tmp/$bad.tsv" >/dev/null 2>&1; then
            echo "FAIL selftest: lint passed $bad.tsv" >&2
            fails=$((fails + 1))
        fi
    done
    if ! lint "$tmp/known.tsv" >/dev/null 2>&1; then
        echo "FAIL selftest: lint refused a well-formed list" >&2
        fails=$((fails + 1))
    fi

    # The case the list exists for on two OSes at once: Linux builds while macOS fails on a
    # breakage only macOS's rows know. With no Linux row, both are green.
    printf 'macos%s0.18%sno member named mac_only%s#790\n' "$T" "$T" "$T" > "$tmp/mac-row.tsv"
    if ! judge "$tmp/mac-row.tsv" linux latest 0.18.0 0 "$tmp/clean.log" >/dev/null 2>&1 ||
        ! judge "$tmp/mac-row.tsv" macos latest 0.18.0 1 "$tmp/mac-only.log" >/dev/null 2>&1; then
        echo "FAIL selftest: Linux building and macOS failing on a macOS-only row were not both green" >&2
        fails=$((fails + 1))
    fi

    if [ "$fails" -eq 0 ]; then
        echo "ok   selftest: pinned green and red; a clean build green with no row and red with a stale one; known diagnostics green in either order, a point release on its minor's row, an OS-only row on its OS alone; red on an unexplained diagnostic, on a listed breakage no diagnostic shows any more, on no diagnostic, on a row for a superseded release, on a malformed or blank-text row and on an unknown OS"
        return 0
    fi
    return 1
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    lint) [ $# -eq 2 ] || { echo "usage: $0 lint <known.tsv>" >&2; exit 2; }; lint "$2"; exit $? ;;
    judge) [ $# -eq 7 ] || { echo "usage: $0 judge <known.tsv> <os> <lane> <zig version> <exit status> <log>" >&2; exit 2; }
        shift; judge "$@"; exit $? ;;
    *) echo "usage: $0 judge <known.tsv> <os> <lane> <zig version> <exit status> <log> | lint <known.tsv> | --selftest" >&2; exit 2 ;;
esac
