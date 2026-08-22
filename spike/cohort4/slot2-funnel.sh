#!/bin/sh
# slot-2 funnel, cheap rules first: 1 (stars), 2 (activity), 3 (contributors).
# Same yardstick that dropped vdirsyncer: a paginated 6-month commit count,
# not a page cap, and the author spread inside that window.
SINCE=2026-02-23T00:00:00Z
echo "== slot-2 funnel: rules 1, 2, 3 measured in the same 6-month window"
echo "== since=$SINCE   run at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "== gh api repos/<r>  and  gh api --paginate repos/<r>/commits?since=$SINCE&per_page=100"
echo
for r in "$@"; do
    meta=$(gh api "repos/$r" --jq '"\(.stargazers_count)\t\(.pushed_at[0:10])\t\(.language)\t\(.archived)"' 2>&1)
    case "$meta" in *"Not Found"*|*error*) echo "$r: BROKEN $meta"; continue;; esac
    stars=$(printf '%s' "$meta" | cut -f1)
    pushed=$(printf '%s' "$meta" | cut -f2)
    lang=$(printf '%s' "$meta" | cut -f3)
    n=$(gh api --paginate "repos/$r/commits?since=$SINCE&per_page=100" --jq '.[].sha' 2>/dev/null | wc -l | tr -d ' ')
    authors=$(gh api --paginate "repos/$r/commits?since=$SINCE&per_page=100" --jq '.[].author.login // "(null)"' 2>/dev/null | sort | uniq -c | sort -rn | head -4 | awk '{printf "%s:%s ", $2, $1}')
    nauth=$(gh api --paginate "repos/$r/commits?since=$SINCE&per_page=100" --jq '.[].author.login // "(null)"' 2>/dev/null | sort -u | wc -l | tr -d ' ')
    rel=$(gh api "repos/$r/releases/latest" --jq '"\(.tag_name) \(.published_at[0:10])"' 2>/dev/null || echo "none")
    printf '%-28s %7s stars  %-10s  pushed=%s\n' "$r" "$stars" "$lang" "$pushed"
    printf '    rule 2: %s commits in window, latest release %s\n' "$n" "$rel"
    printf '    rule 3: %s distinct authors in window -> %s\n' "$nauth" "$authors"
done
echo
echo "== a 0-commit window is a measurement here: the same command returned 184 for pimalaya/himalaya"
