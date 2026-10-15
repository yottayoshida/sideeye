#!/bin/sh
# The root is the argument, not acceptance.sh's /work default: run by hand, /work does not
# exist and every path in the check reads as missing.
set -u

ROOT=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
fails=0

# Guards path rot, not claim drift: every backticked token containing a slash in the
# evidence-first pages must exist in the repo, so a moved transcript or a renamed
# checker cannot leave a page pointing at nothing. Claim-vs-transcript verification
# stays a review-time axis (ADR 0039 records that ruling and what would reopen it; #357).
# Pages that quote ratios or numbers must keep them out of
# backticks — a backticked "3/7" is extracted as a path here and goes red (#85). Sunset: never fired by the v1.0 freeze -> removal list.
doc_fails=0
# The list itself is asserted, for the same reason each page's reference count is: the
# pages live on one line, and a branch that adds a page collides there with any other
# branch that does. Resolve that conflict by taking one side and the pages the other
# side added leave the sweep in silence, still green over what remains. A page added
# here has to move this number too (#605).
# The list is built once and both read from `$doc_pages`: counted, then swept through a
# heredoc. Written as two heredocs — one counted, one swept — the assertion guarded the
# copy nobody walked, which is worse than no assertion: measured under dash, the count
# said 4 while the sweep covered 3 and doc_fails stayed 0, for exactly the merge this
# check exists to catch. Not an unquoted variable in `for` (a path with a space is lost
# and a glob expands) and not a pipeline (`... | while read` counts into a subshell whose
# total never reaches the caller — the shape upstream-report-status.sh shipped once,
# exiting 0 over a table of failures).
doc_pages=$(printf '%s\n' \
    "$ROOT/docs/target-classes.md" \
    "$ROOT/docs/checker-cookbook.md" \
    "$ROOT/docs/kill-criteria-review.md" \
    "$ROOT/docs/outcome-funnel.md")
doc_page_count=$(printf '%s\n' "$doc_pages" | grep -c .)
if [ "$doc_page_count" != "4" ]; then
    echo "     the evidence-first page list holds $doc_page_count pages, not the 4 this check is written for — a merge that dropped one leaves the sweep green over the rest"
    doc_fails=$((doc_fails + 1))
fi
while IFS= read -r page; do
    [ -n "$page" ] || continue
    if [ ! -f "$page" ]; then
        echo "     missing page: $page"
        doc_fails=$((doc_fails + 1))
        continue
    fi
    refs=$(grep -o '`[^`]*`' "$page" | tr -d '`' | grep / | grep -v '[ <#]' || true)
    # The denominator is asserted: an extraction that finds almost nothing (say, the
    # pages moved to markdown links) must go red here, not pass over an empty loop.
    ref_count=$(printf '%s\n' "$refs" | grep -c . || true)
    if [ "$ref_count" -lt 5 ]; then
        echo "     only $ref_count slashed references extracted from ${page##*/} — the sweep is not seeing the page"
        doc_fails=$((doc_fails + 1))
    fi
    set -f
    for r in $refs; do
        case "$r" in -*|/*) continue ;; esac
        if [ ! -e "$ROOT/$r" ]; then
            echo "     missing: $r (in ${page##*/})"
            doc_fails=$((doc_fails + 1))
        fi
    done
    set +f
done <<PAGE_LIST
$doc_pages
PAGE_LIST
if [ "$doc_fails" = "0" ]; then
    echo "ok   every slashed backtick reference in the listed pages resolves in the repo"
else
    echo "FAIL docs reference existence: $doc_fails missing"
    fails=$((fails + 1))
fi

[ "$fails" = 0 ]
