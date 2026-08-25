#!/bin/sh
# CI entry point for the spike/ language-stats classification.
#
# Why this exists: the rule in .gitattributes used to be "register a directory
# here when its campaign closes", and it was missed on every closure it faced —
# cohort 4, spike/macos-oracle/ (#181), spike/scout-model-comparison/ (#221).
# Nothing read that file at the moment a record closed. The direction is now
# inverted so the closing moment carries no obligation, and this holds the new
# arrangement in place.
#
# It reads the ATTRIBUTE, not the text of .gitattributes. A pattern that is
# syntactically fine and semantically wrong — a typo, a later line overriding an
# earlier one, a rule that matches nothing — leaves the file looking correct and
# the attribute unapplied. Only `git check-attr` can tell those apart.
#
# Contract, deliberately strict in both directions:
#
#   * every tracked file under spike/ resolves to set or unset. `unspecified` is
#     a FAILURE. That third state is what hid the three misses: before the
#     inversion, 35 files that should have been documentation and 27 that were
#     correctly code all reported the same `unspecified`, so nothing could tell
#     a decision from an omission.
#   * finding no file at all is a failure, not a pass. A path typo here would
#     otherwise report success over an empty set — the failure mode this
#     repository keeps meeting.
#   * every tracked file directly under spike/ is unset. The maintained harness
#     lives at the top level, and hiding it would overstate how much of this
#     repository is Zig.
#   * every tracked file inside a subdirectory of spike/ is set, EXCEPT the
#     literal exemptions below.
#   * each exemption matches at least one file and every file it matches is
#     unset. A stale exemption — one naming a directory .gitattributes no longer
#     unsets — fails here rather than silently widening what is allowed.
#   * no tracked path under spike/ carries a tab or a newline. Git allows both
#     and the NUL-to-line fold below cannot survive either. The fold's own
#     asserts already fail closed on them, but they fail talking about column
#     drift, which does not tell anyone what to rename.
#
# The exemptions are literals, so a new live directory cannot inherit one by
# accident. What this catches is one-sided drift: a directory unset in
# .gitattributes but missing from exempt_dirs fails as a record that came back
# unset, and a stale literal here fails as an exemption matching nothing.
#
# What it does NOT catch, and must not be described as catching: a new live
# directory omitted from BOTH places. It is documentation by default and this
# check expects documentation, so both agree and CI is green. That is the one
# misclassification the inverted default can produce, and ADR 0021 takes it
# deliberately — it understates Shell rather than counting a frozen transcript
# as code. Naming it here because the first draft of this header claimed the
# check forces the decision, which it does not.
set -u

root=${1:-$(cd "$(dirname "$0")/.." && pwd)}

# Live directories: subdirectories of spike/ that hold maintained code rather
# than a closed record. Directory names, space separated, padded with a space at
# each end so membership is a `case` match rather than word splitting. That
# padding is not decoration: the file loop below runs under IFS=newline, and
# `for e in $exempt_dirs` there would read the whole list as one word. With a
# single entry that is indistinguishable from working; it breaks the first time
# a second live directory is added, which is the only time this list is edited.
exempt_dirs=" toys "

total=0
fails=0
n_set=0
n_unset=0
seen_exempt=" "

# `check-attr -z` emits NUL-separated (path, attribute, value) triples. They are
# folded back into tab-separated lines with tr+paste rather than awk's RS: BSD
# awk, which is what macOS ships, does not accept RS="\0" and reads the whole
# stream as one record. That variant passed on the Linux runner and produced
# nothing here, which is the shape where CI is greener than the machine you are
# standing at. The count and alignment assertions below are what make the fold
# safe: a path containing a newline would shift the columns, and a shifted
# column stops matching the attribute name.
n_files=$(git -C "$root" ls-files spike/ | wc -l | tr -d ' ')

# Exactly two bytes break the fold below: a tab adds a column and a newline
# splits a record. `ls-files -z` separates with NUL and introduces neither, so
# deleting those two from the stream and comparing byte counts detects them and
# nothing else.
#
# Two narrower guards were tried first and both rejected legal paths. Detecting
# the double quote that `git ls-files` puts on a path it escapes catches a
# Japanese filename under the default `core.quotePath`, and reading that setting
# means the check depends on the reader's config. Forcing
# `core.quotePath=false` fixes the non-ASCII case but not the general one: `"`
# and `\` are escaped whatever that setting says, and neither of them harms the
# fold. Measured, in this order, on real paths.
raw_bytes=$(git -C "$root" ls-files -z spike/ | wc -c | tr -d ' ')
kept_bytes=$(git -C "$root" ls-files -z spike/ | LC_ALL=C tr -d '\11\12' | wc -c | tr -d ' ')
if [ "$raw_bytes" != "$kept_bytes" ]; then
    echo "FAIL  a tracked path under spike/ contains a tab or a newline" >&2
    echo "      ($((raw_bytes - kept_bytes)) such byte(s)). That breaks the NUL-to-line fold" >&2
    echo "      this check reads. Rename them: the convention is that tracked paths here hold" >&2
    echo "      no tab and no newline. Quotes, backslashes and non-ASCII are all fine." >&2
    echo "      Paths carrying a tab (one carrying a newline cannot be shown on one line):" >&2
    git -C "$root" ls-files -z spike/ | tr '\0' '\n' | LC_ALL=C grep "$(printf '\t')" | head -5 >&2
    exit 1
fi
pairs=$(git -C "$root" ls-files -z spike/ | git -C "$root" check-attr -z --stdin linguist-documentation |
    tr '\0' '\n' | paste -d'	' - - -)

if [ -z "$pairs" ]; then
    echo "FAIL  no tracked file found under $root/spike/ — this check could not look" >&2
    exit 1
fi

# `while IFS= read -r` rather than `for line in $pairs`: it splits on the line
# only, so a path containing a space survives, and IFS stays scoped to the read
# instead of being saved and restored around a block. The earlier form set IFS
# shell-wide for the loop body and silently broke `for e in $exempt_dirs` inside
# it. A here-document rather than a pipe, so the counters below stay in this
# shell — a `printf | while` would increment them in a subshell and report zero.
while IFS= read -r line; do
    [ -n "$line" ] || continue
    path=${line%%	*}
    tail_=${line#*	}
    attr=${tail_%%	*}
    value=${tail_#*	}
    total=$((total + 1))

    if [ "$attr" != linguist-documentation ]; then
        echo "FAIL  column drift at record $total: expected the attribute name, read '$attr'" >&2
        exit 1
    fi

    case "$value" in
        set) n_set=$((n_set + 1)) ;;
        unset) n_unset=$((n_unset + 1)) ;;
        *)
            echo "FAIL  $path: linguist-documentation is $value; every file under spike/ must be set or unset"
            fails=$((fails + 1))
            continue
            ;;
    esac

    rest=${path#spike/}
    case "$rest" in
        */*)
            dir=${rest%%/*}
            want=set
            case "$exempt_dirs" in
                *" $dir "*)
                    want=unset
                    case "$seen_exempt" in
                        *" $dir "*) ;;
                        *) seen_exempt="$seen_exempt$dir " ;;
                    esac
                    ;;
            esac
            if [ "$value" != "$want" ]; then
                if [ "$want" = set ]; then
                    echo "FAIL  $path: a record directory came back $value; spike/$dir/ is not a live directory here"
                else
                    echo "FAIL  $path: spike/$dir/ is exempt as a live directory but this file came back $value"
                fi
                fails=$((fails + 1))
            fi
            ;;
        *)
            if [ "$value" != unset ]; then
                echo "FAIL  $path: a top-level harness file came back $value; hiding it understates Shell"
                fails=$((fails + 1))
            fi
            ;;
    esac
done <<PAIRS
$pairs
PAIRS

# A literal that matches nothing is an exemption for a directory that has been
# renamed or deleted. Left in place it would quietly cover a future directory
# that takes the same name.
for e in $exempt_dirs; do
    case "$seen_exempt" in
        *" $e "*) ;;
        *)
            echo "FAIL  the exemption '$e' matched no tracked file under spike/$e/ — stale literal"
            fails=$((fails + 1))
            ;;
    esac
done

# The scan has to cover every tracked file, not most of them. Without this a
# fold that dropped the tail would report a clean sweep over a short list.
if [ "$total" != "$n_files" ]; then
    echo "FAIL  scanned $total files but spike/ tracks $n_files — the attribute stream and the file list disagree" >&2
    exit 1
fi

if [ "$fails" = 0 ]; then
    # No count for the third state: reaching this line means there were none,
    # because any unspecified file raises fails and takes the branch below. A
    # variable printed here could only ever read zero, which would look like a
    # measurement and be an assertion.
    echo "ok   $total tracked files under spike/ classified: $n_set documentation, $n_unset code, none unspecified"
    exit 0
fi

echo "FAIL spike/ classification: $fails problem(s) over $total tracked files" >&2
exit 1
