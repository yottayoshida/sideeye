#!/bin/sh
# Is a candidate fresh — has this project met it before? (2026-09-21 verdict-chain run)
#
#   sh fresh.sh <name> [<name> ...]
#   sh fresh.sh --ledgers          # print what is searched, and how big each is
#   sh fresh.sh --selftest
#
# Prints one line per name: `fresh <name>` or `SEEN <name> <ledger>:<line>` for every hit.
# Exit 1 if any name was seen, so a slate can be gated on it.
#
# **Nine ledgers, because six was not enough.** The outcome funnel names 68 targets, and a
# candidate absent from it can still be one this project has measured: the funnel holds
# encounters, not the candidates a run screened out, and those live only in each run's
# SELECTION.md. The 2026-09-21 release-path run added the ten SELECTION.md files and #618's
# own target selection with its four pools, for the reason its header gave: #618 was still
# running with no measurement published, so a collision there would reach a sealed study.
#
# Three more are added here, all of them name ledgers the previous six did not search:
#
#   b2-exclusions.txt   229 lines, the largest name ledger in the tree — and the file the
#                       PREVIOUS campaign wrote its own target into as a follow-through.
#                       A checker that does not read what its own campaign writes is a
#                       pair that can only drift. Re-checked on that run's 26 fresh names:
#                       the only hit is the line it wrote itself, so the hole had not yet
#                       produced a false `fresh` — it is closed before it does.
#   b2-targets.txt      the 30 names #619 is measuring RIGHT NOW.
#   b2-candidates.txt   the 289 names those 30 were drawn from.
#
# The last two are the #618 argument applied to #619: a collision reaches a study in
# flight. A candidate found in b2-targets.txt is dropped at selection rather than patched
# afterwards — `spike/unknown-rate/count.py` re-derives that list as the keyed first N of
# the candidates minus the exclusions, so excluding one of the 30 promotes the 31st and
# turns `spike/acceptance.sh` red. The CI failure is the small half; the contaminated
# study is the large one.
#
# **Matching is deliberately loose**: a case-insensitive fixed-string search for the name
# anywhere in the ledger. A false `SEEN` costs one candidate; a false `fresh` puts a target
# this project has already published into a campaign that claims it is new. The failure is
# not symmetric, so the cheap direction is the wrong one to optimise.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../.." && pwd)"

# Each entry: <label>:<path>. All eight are read (plus the globbed selection files and
# pools, which makes nine sources); a missing one is a hard error rather than a
# quiet skip — a ledger that silently does not exist would make every candidate look fresh.
ledgers="
funnel:spike/outcome-funnel.tsv
target-classes:docs/target-classes.md
unknown-rate-exclusions:spike/unknown-rate/b-exclusions.txt
blind-hunt3-taint:spike/blind-hunt3/candidates.md
authoring-cost-selection:spike/authoring-cost/selection.tsv
b2-exclusions:spike/unknown-rate/b2-exclusions.txt
b2-targets:spike/unknown-rate/b2-targets.txt
b2-candidates:spike/unknown-rate/b2-candidates.txt
"

# This campaign's own directory. Its records are excluded from every ledger below, so a slate
# does not come back "already met" because this run wrote it down — and so the freshness of a
# past selection can still be checked after the fact. Measured: without this, re-running the
# check the same day returns SEEN for the very target it cleared, naming this run's own
# SELECTION.md, the funnel row it added and the target-classes row it added.
mine="spike/dogfood/2026-09-21-verdict-chain"

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
        # `grep -n` on the FILE, then drop this campaign's own rows — not `grep -n` on the
        # filtered stream, which numbers the lines it was handed and so reports a number
        # that does not exist in the file. Measured: with one `$mine` row removed above it,
        # `pre-commit` was reported at b2-exclusions:165 while the file's 165 is `poetry`.
        # Same class as the gate's threads count, found by sweeping for it: a search that
        # could not read its input must not come back looking like "no hit", because here
        # "no hit" is `fresh` — the direction this script's own header calls the expensive
        # one. `grep` distinguishes them (0 match, 1 no match, 2 error) and the status is
        # read rather than thrown away with `2>/dev/null`.
        # `&& grc=0 || grc=$?`, not `; grc=$?`: under `set -e` an assignment takes the
        # status of its command substitution, so a plain no-match (grep's 1) kills the
        # script — silently, exiting 1, which reads exactly like a failing check. That is
        # the trap this file's own comment below already describes, met a second time from
        # a different direction. An `||` list is not a `set -e` trigger.
        hit=$(grep -n -i -F "$name" "$root/$path" 2>/dev/null) && grc=0 || grc=$?
        [ "$grc" -le 1 ] || { echo "fresh: could not search $path (grep exited $grc)" >&2; exit 2; }
        line=$(printf '%s\n' "$hit" | grep -v -F "$mine" | head -1 | cut -d: -f1 || true)
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
    # The self-exclusion must be scoped to THIS campaign and to nothing else. The previous
    # campaign's version of this case asserted the opposite — that `lefthook` reads fresh —
    # because `lefthook` was ITS slate and `mine` pointed at ITS directory. Copying that
    # case forward unchanged would assert both directions at once and one of them would
    # always be red. Here `mine` is a different directory, so lefthook is somebody else's
    # measured target and must come back SEEN: that is what fails if `mine` is ever widened
    # (a glob, a parent directory) into excluding other campaigns' records too.
    hits=$(seen_in lefthook)
    case "$hits" in
        *funnel*) echo "ok   another campaign's measured target still reads seen" ;;
        *) echo "FAIL lefthook did not come back seen from the funnel; is \$mine too wide?"; fails=$((fails + 1)) ;;
    esac

    # The other direction of the same scoping: this campaign's OWN target must still read
    # fresh after this campaign has written its follow-through rows, or the freshness of
    # this selection could never be re-checked. The exclusion works by campaign path
    # (`grep -v -F "$mine"`), so every row this run adds has to carry that path in its
    # text — including the one in a NAME ledger, `spike/unknown-rate/b2-exclusions.txt`,
    # whose rows are `<package>\t<reason>` and carried no path before this campaign. The
    # previous run wrote `lefthook  measured (2026-09-21 release-path dogfood)` there, which
    # its own checker could not have dropped; this run writes the path instead. Without that
    # change this case is red.
    if [ -z "$(seen_in overcommit)" ]; then
        echo "ok   this campaign's own records do not make its own target look already met"
    else
        echo "FAIL overcommit matched this campaign's own records: $(seen_in overcommit | tr '\n' ' ')"
        fails=$((fails + 1))
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
