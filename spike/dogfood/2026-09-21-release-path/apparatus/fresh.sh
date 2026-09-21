#!/bin/sh
# Is a candidate fresh — has this project met it before? (2026-09-21 release-path run)
#
#   sh fresh.sh <name> [<name> ...]
#   sh fresh.sh --ledgers          # print what is searched, and how big each is
#   sh fresh.sh --selftest
#
# Prints one line per name: `fresh <name>` or `SEEN <name> <ledger>:<line>` for every hit.
# Exit 1 if any name was seen, so a slate can be gated on it.
#
# **Six ledgers, because five was not enough.** The outcome funnel names 68 targets, and a
# candidate absent from it can still be one this project has measured: the funnel holds
# encounters, not the candidates a run screened out, and those live only in each run's
# SELECTION.md. Review found two more sets missing from an earlier draft of this campaign —
# the ten SELECTION.md files, and #618's own target selection with its four pools. #618 is
# still running with no measurement published, so a collision there would reach a sealed study.
#
# **Matching is deliberately loose**: a case-insensitive fixed-string search for the name
# anywhere in the ledger. A false `SEEN` costs one candidate; a false `fresh` puts a target
# this project has already published into a campaign that claims it is new. The failure is
# not symmetric, so the cheap direction is the wrong one to optimise.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../.." && pwd)"

# Each entry: <label>:<path>. All six are read; a missing one is a hard error rather than a
# quiet skip — a ledger that silently does not exist would make every candidate look fresh.
ledgers="
funnel:spike/outcome-funnel.tsv
target-classes:docs/target-classes.md
unknown-rate-exclusions:spike/unknown-rate/b-exclusions.txt
blind-hunt3-taint:spike/blind-hunt3/candidates.md
authoring-cost-selection:spike/authoring-cost/selection.tsv
"

# This campaign's own directory. Its records are excluded from every ledger below, so a slate
# does not come back "already met" because this run wrote it down — and so the freshness of a
# past selection can still be checked after the fact. Measured: without this, re-running the
# check the same day returns SEEN for the very target it cleared, naming this run's own
# SELECTION.md, the funnel row it added and the target-classes row it added.
mine="spike/dogfood/2026-09-21-release-path"

# Lines belonging to this campaign are dropped before searching. `grep -v` on the campaign's own
# path is enough for the two ledgers that name it (the funnel and target-classes both carry it in
# the row itself); its SELECTION.md is dropped by path in selection_files.
without_mine() { grep -v -F "$mine" "$1" 2>/dev/null || true; }

selection_files() {
    # The per-run SELECTION.md files, plus #618's four pools. Globbed rather than listed: a run
    # added after this script was written must still be searched. This campaign's own is skipped.
    for f in "$root"/spike/dogfood/*/SELECTION.md; do
        case "$f" in *"$mine"*) continue ;; esac
        [ -f "$f" ] && echo "$f"
    done
    ls "$root"/spike/authoring-cost/pool-*.txt 2>/dev/null || true
}

show_ledgers() {
    for entry in $ledgers; do
        label=${entry%%:*}; path=${entry#*:}
        [ -f "$root/$path" ] || { echo "fresh: missing ledger $path" >&2; exit 2; }
        printf '%-26s %-52s %s lines\n' "$label" "$path" "$(grep -c '' "$root/$path")"
    done
    n=0
    for f in $(selection_files); do n=$((n + 1)); done
    printf '%-26s %-52s %s files\n' "selection+pools" "spike/dogfood/*/SELECTION.md, authoring-cost/pool-*" "$n"
}

seen_in() {
    # $1 name. Prints `<label>:<line>` for each hit, nothing when clear.
    name=$1
    for entry in $ledgers; do
        label=${entry%%:*}; path=${entry#*:}
        [ -f "$root/$path" ] || { echo "fresh: missing ledger $path" >&2; exit 2; }
        line=$(without_mine "$root/$path" | grep -n -i -F -m1 "$name" | cut -d: -f1 || true)
        # `if`, not `[ ] && printf`: under `set -e` a false test as the last statement of a
        # loop body makes the function return 1, the command substitution that called it
        # fails, and the whole script dies with no output at all. Measured — the first
        # version of this selftest printed nothing and exited 1, which reads exactly like a
        # failing check and was in fact the script killing itself on a clear candidate.
        if [ -n "$line" ]; then printf '%s:%s\n' "$label" "$line"; fi
    done
    for f in $(selection_files); do
        line=$(grep -n -i -F -m1 "$name" "$f" 2>/dev/null | cut -d: -f1 || true)
        if [ -n "$line" ]; then printf '%s:%s\n' "${f#"$root"/}" "$line"; fi
    done
}

# --selftest: the two directions that matter, on names whose answer is known from the tree.
# A known target must come back SEEN and an invented one must come back fresh; a script that
# always says one of the two is the failure this gate exists to prevent.
if [ "${1:-}" = "--selftest" ]; then
    fails=0
    # `codespell` is in the funnel (2026-09-16-userview-3 filed against it).
    hits=$(seen_in codespell)
    case "$hits" in
        *funnel*) echo "ok   a target the funnel names comes back seen" ;;
        *) echo "FAIL codespell was not found in the funnel"; fails=$((fails + 1)) ;;
    esac
    # `dos2unix` is NOT in the funnel — it is #618's, which an earlier draft of this campaign
    # would have missed entirely. This case is the reason the last two ledgers are here.
    hits=$(seen_in dos2unix)
    case "$hits" in
        *authoring-cost*) echo "ok   a target only #618 names is still seen" ;;
        *) echo "FAIL dos2unix was not found in the authoring-cost ledgers"; fails=$((fails + 1)) ;;
    esac
    # This campaign's own slate must still read fresh after this campaign has written its
    # records. Without the exclusion above it comes back SEEN against its own rows, and the
    # freshness of the selection could never be checked again.
    if [ -z "$(seen_in lefthook)" ]; then
        echo "ok   this campaign's own records do not make its slate look already met"
    else
        echo "FAIL lefthook matched this campaign's own records"; fails=$((fails + 1))
    fi

    # An invented name must be clear, or every candidate would read as already met.
    if [ -z "$(seen_in zzqx-not-a-real-tool)" ]; then
        echo "ok   an invented name comes back fresh"
    else
        echo "FAIL an invented name matched something"; fails=$((fails + 1))
    fi
    [ "$fails" = 0 ] || { echo "fresh: $fails case(s) failed"; exit 1; }
    echo "fresh: selftest green"
    exit 0
fi

[ "${1:-}" = "--ledgers" ] && { show_ledgers; exit 0; }
[ $# -ge 1 ] || { echo "usage: fresh.sh <name> [<name> ...] | --ledgers | --selftest" >&2; exit 2; }

status=0
for name in "$@"; do
    hits=$(seen_in "$name")
    if [ -z "$hits" ]; then
        printf 'fresh %s\n' "$name"
    else
        status=1
        for h in $hits; do printf 'SEEN  %s  %s\n' "$name" "$h"; done
    fi
done
exit $status
