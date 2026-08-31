#!/bin/sh
# The staged repository holds nothing the pin cannot reach (#62).
#
#   sh check-history.sh <stage-root> <pin>
#
# Run twice, from two places, on purpose: `stage.sh` runs it after stripping, and the
# launcher for the variant being measured (`run-agent.sh`, `run-agent-mcp.sh`) runs it
# again immediately before the agent. The second run is not belt and braces —
# `repo/**` is deliberately outside the seal (it is the agent's own work product, so
# the judge must not restore it), which means nothing else looks at the repository
# between staging and the measurement. One run at stage time says what was built; two
# runs say what the agent received. **Both launchers** because the mcp variant runs a
# further container against the stage (`contrast-mcp.sh`) inside that same window —
# more traffic through it, not less.
#
# What it does NOT cover: the run itself. The agent has `Bash` and this is not a
# network namespace, so nothing here stops a `git clone` mid-measurement. This is a
# property of the handover; enforcement during the run is the transcript audit's, and
# whether that audit has ever been seen refusing anything is #63.
#
# ## Why the check reads the object store rather than the ref graph
#
# The first draft asserted `rev-list --all --count == 1`, and review broke it: deleting
# refs does not delete objects. A repository can pass every ref-level assertion while
# `git cat-file --batch-all-objects` still lists every future commit and blob, and
# `git fsck --unreachable` names them. So the comparison here is
#
#     everything reachable from HEAD  ==  everything the object database holds
#
# which is a statement about what is *present*, not about what is *indexed*. It also
# makes the check independent of how the history was narrowed: a shallow fetch and a
# clone-then-strip both have to satisfy the same sentence.
#
# ## Every repository, because the submodules are invisible from the superproject
#
# A submodule's objects live in `repo/.git/modules/<path>`, where the superproject's
# `rev-list` and `for-each-ref` cannot see them at all: one stripped of nothing sails
# through a check that only looks at the top level. The set is **derived from the pin's
# tree** rather than written down — the first version named `src/libshared`, and review
# built a superproject with a second submodule that narrowed clean, checked green, and
# kept its whole future. A submodule the pin names and the stage lacks is a failure too.
#
# Exit 0 when both repositories hold only what the pin reaches, 1 when one does not,
# 2 when the check could not run — never read a 2 as a pass.
#
# ## How to call it, and why that is not a style question
#
# Every caller runs under `set -eu`, so the dispatch has to be written
#
#     hist_rc=0
#     sh check-history.sh "$ROOT" "$pin" || hist_rc=$?
#     case $hist_rc in ...
#
# The name is its own rather than `rc` because `stage.sh` already uses `rc` further down
# for the explore container's status; two unrelated meanings on one name in one script is
# a reordering away from being a bug.
#
# A bare call followed by `case $?` on the next line never reaches the case: `set -e`
# ends the caller the moment a standalone command exits non-zero. All three call sites
# shipped that shape in #62 — the `||` form had been seen red, then it was "improved"
# into `case $?` and the improved form was never run. Measured 2026-09-01 against a
# disposable stage: both launchers printed nothing of their own, and a BROKEN 2 went
# straight out as the caller's exit status where 1 was meant. On the left of `||` a
# command is tested rather than fatal, which is what lets the dispatch happen at all.
set -u

die_broken() { echo "BROKEN: $*" >&2; exit 2; }

ROOT=${1:?usage: check-history.sh <stage-root> <pin>}
PIN=${2:?usage: check-history.sh <stage-root> <pin>}
REPO="$ROOT/stage/repo"

[ -d "$REPO/.git" ] || die_broken "no repository at $REPO"
command -v git >/dev/null || die_broken "git not found"

fails=0

check_one() { # $1 = label, $2 = git directory, $3 = expected HEAD
    label=$1
    dir=$2
    want_head=$3
    bad=0

    head=$(git -C "$dir" rev-parse HEAD 2>/dev/null) || {
        echo "FAIL $label: HEAD does not resolve"
        fails=$((fails + 1))
        return
    }
    if [ "$head" != "$want_head" ]; then
        echo "FAIL $label: HEAD is $head, wanted $want_head"
        bad=$((bad + 1))
    fi

    # Every ref is gone. A ref pointing INTO the pin's ancestry would be harmless, but
    # "none" is the state the stripping produces and is cheaper to assert than
    # ancestry per ref — and a ref that reappeared is a fetch nobody declared.
    refs=$(git -C "$dir" for-each-ref --format='%(refname)')
    if [ -n "$refs" ]; then
        echo "FAIL $label: refs exist that stripping removed:"
        printf '%s\n' "$refs" | head -8 | sed 's/^/     | /'
        bad=$((bad + 1))
    fi

    # An alternate object store would put objects somewhere this comparison does not
    # own, and "the object database" would stop naming one thing. `stage.sh` clones
    # from a URL and never passes `--reference`, so this should not exist; it is
    # asserted rather than assumed because the whole check below is a statement about
    # a single store. BROKEN, not FAIL: the check cannot make its statement, which is
    # a different thing from the statement being false.
    gitdir=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null) ||
        die_broken "$label: no git directory"
    [ -e "$gitdir/objects/info/alternates" ] &&
        die_broken "$label: an alternate object store is configured; this check owns only one"

    # The object store holds exactly what HEAD reaches. This is the clause that a
    # ref-level check cannot make.
    allowed=$(git -C "$dir" rev-list --objects HEAD 2>/dev/null | cut -d' ' -f1 | LC_ALL=C sort -u)
    physical=$(git -C "$dir" cat-file --batch-all-objects --batch-check='%(objectname)' 2>/dev/null | LC_ALL=C sort -u)
    [ -n "$allowed" ] || die_broken "$label: rev-list produced nothing — the check did not run"
    [ -n "$physical" ] || die_broken "$label: cat-file produced nothing — the check did not run"
    n_allowed=$(printf '%s\n' "$allowed" | grep -c .)
    n_physical=$(printf '%s\n' "$physical" | grep -c .)
    if [ "$allowed" != "$physical" ]; then
        printf '%s\n' "$allowed" > "$tmp_a"
        printf '%s\n' "$physical" > "$tmp_p"
        echo "FAIL $label: the object store and HEAD's reach differ"
        echo "     reachable=$n_allowed present=$n_physical"
        LC_ALL=C comm -13 "$tmp_a" "$tmp_p" | head -5 | sed 's/^/     | only in the store /'
        LC_ALL=C comm -23 "$tmp_a" "$tmp_p" | head -5 | sed 's/^/     | missing from the store /'
        bad=$((bad + 1))
    fi

    # The same statement from the other side. `--no-reflogs` because a surviving
    # reflog is itself something the stripping should have removed, and this line
    # should not quietly treat it as a root.
    unreachable=$(git -C "$dir" fsck --full --no-reflogs --unreachable 2>/dev/null)
    if [ -n "$unreachable" ]; then
        echo "FAIL $label: unreachable objects survive"
        printf '%s\n' "$unreachable" | head -5 | sed 's/^/     | /'
        bad=$((bad + 1))
    fi

    if [ "$bad" = 0 ]; then
        printf 'ok   %-14s HEAD=%.12s, %s object(s), no refs, nothing unreachable\n' \
            "$label" "$head" "$n_allowed"
    else
        fails=$((fails + bad))
    fi
}

# Two files rather than a directory, so the cleanup is `rm -f` and not a recursive
# delete: this runs under tooling that intercepts recursive removes, and a trap that
# is refused leaves scratch behind on every invocation.
tmp_a=$(mktemp) || die_broken "cannot create a scratch file"
tmp_p=$(mktemp) || die_broken "cannot create a scratch file"
# A third file, and not a reuse of the two above: the submodule list is read by a
# `while` loop while `check_one` writes those two on every mismatch, so sharing one
# would rewrite the list mid-iteration.
tmp_s=$(mktemp) || die_broken "cannot create a scratch file"
trap 'rm -f "$tmp_a" "$tmp_p" "$tmp_s"' EXIT

check_one superproject "$REPO" "$PIN"

# The submodules are DERIVED from the pin's tree, never listed here. The first version
# named `src/libshared`, and review demonstrated what that costs: a superproject with a
# second submodule narrowed clean, checked green, and still carried that submodule's
# whole future. A check whose value is that it does not depend on the completeness of
# the stripping list must not keep its own copy of that list.
#
# Read after the superproject is checked, because a wrong HEAD up there would measure
# the submodules against the wrong expectation.
tree=$(git -C "$REPO" ls-tree -r HEAD 2>/dev/null) ||
    die_broken "could not read the pin's tree"
[ -n "$tree" ] || die_broken "the pin's tree is empty — the check did not run"
printf '%s\n' "$tree" | awk '$2 == "commit" { print $4 }' > "$tmp_s"
n_sub=$(grep -c . "$tmp_s")

while read -r sm_path; do
    [ -n "$sm_path" ] || continue
    sub="$REPO/$sm_path"
    [ -e "$sub/.git" ] ||
        die_broken "the pin names a submodule at $sm_path and the stage has none there"
    gitlink=$(git -C "$REPO" rev-parse "HEAD:$sm_path" 2>/dev/null) ||
        die_broken "could not read the recorded commit for $sm_path"
    check_one "sub:$sm_path" "$sub" "$gitlink"
done < "$tmp_s"

echo "checked 1 superproject and $n_sub submodule(s), derived from the pin's tree"

if [ "$fails" != 0 ]; then
    echo "the stage carries git the pin cannot reach ($fails failure(s))" >&2
    exit 1
fi
exit 0
