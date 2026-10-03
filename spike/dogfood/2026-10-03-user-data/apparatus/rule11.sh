#!/bin/sh
# Rule 11 receipts (spike/cohort4/SCOUT-BRIEF.md): the last ten bug reports of a tracker and the
# first reply from someone the project counts as its own — OWNER, MEMBER, COLLABORATOR or
# CONTRIBUTOR, as GitHub reports author_association. Written for the 2026-10-03 user-data rounds
# in the shape of 2026-09-28's transcripts/receipts/rule11-bug-reports.txt, whose script was not
# kept.
#
#   sh rule11.sh <owner/repo> [label]
#
# With no label, the first of `bug`, `kind/bug`, `type: bug`, `Bug` that has any issue is used;
# when none has, the last ten issues of any label are taken and the header says so — the
# fallback 2026-09-22 used for todo.txt-cli. Pull requests are excluded.
set -u
repo=${1:?usage: rule11.sh <owner/repo> [label]}
label=${2:-}; any=${ANY:-0}   # ANY=1: skip the bug labels, take the last ten issues of any label
own='OWNER|MEMBER|COLLABORATOR|CONTRIBUTOR'

list() { # <label or empty>
    if [ -n "$1" ]; then
        gh api -X GET "repos/$repo/issues" -f state=all -f per_page=100 -f labels="$1" \
            --jq '[.[] | select(.pull_request == null)] | .[0:10][] | "\(.number) \(.created_at[0:10]) \(.comments) \(.user.login)"' 2>/dev/null
    else
        gh api -X GET "repos/$repo/issues" -f state=all -f per_page=100 \
            --jq '[.[] | select(.pull_request == null)] | .[0:10][] | "\(.number) \(.created_at[0:10]) \(.comments) \(.user.login)"' 2>/dev/null
    fi
}

rows=""
if [ "$any" = 1 ]; then
    rows=$(list ""); used="(any label, asked for: the bug label held too few)"
elif [ -n "$label" ]; then
    rows=$(list "$label"); used=$label
else
    for l in bug kind/bug "type: bug" Bug "type:bug" "T: bug"; do
        rows=$(list "$l"); used=$l
        [ -n "$rows" ] && break
    done
    [ -n "$rows" ] || { rows=$(list ""); used="(none matched; last issues of any label)"; }
fi

echo "== $repo (label $used)"
[ -n "$rows" ] || { echo "no issues returned"; exit 2; }
echo "$rows" | while read -r n created comments author; do
    first=none
    if [ "$comments" -gt 0 ]; then
        first=$(gh api "repos/$repo/issues/$n/comments?per_page=50" \
            --jq "[.[] | select(.author_association | test(\"^($own)\$\")) | select(.user.login != \"$author\")] | first | if . == null then \"none\" else \"\(.author_association) \(.created_at[0:10])\" end" 2>/dev/null || echo "unreadable")
    fi
    echo "#$n $created comments=$comments first_project_reply=$first"
done
