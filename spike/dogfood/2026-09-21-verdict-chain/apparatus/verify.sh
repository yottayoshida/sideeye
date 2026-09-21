#!/bin/sh
# What `overcommit --install` owes, judged over EVERY entry in the hooks directory.
#
# `overcommit --install` copies one Ruby entrypoint into `.git/hooks` under ten names —
# measured: ten regular files of 3,682 bytes, one distinct md5 between them. Beside them sit
# the fourteen `*.sample` files `git init` wrote, which install must not damage.
#
# The user-visible contract: **every file in this directory is either one of git's samples
# or a complete, executable overcommit hook.** Git runs whatever is at a hook path on the
# next commit, so a hook cut off mid-file is worse than no hook at all, and a complete hook
# without its exec bit is one git silently skips.
#
# Legitimate after a crash: no overcommit hook, or fewer than a finished run writes. Those
# are recoverable by running install again. A hook that exists and is cut short is not.
#
# ## Why this judges the samples too, which install does not write
#
# The first version looped over the ten managed names only and was refused by the engine:
# `UNKNOWN checker_not_falsified`, *"the checker accepted a state whose every file had been
# overwritten with junk"*. The falsification corrupts each world's **initial** state
# (`src/main.zig:2444` restores `initial` and then corrupts it) — which here is the fourteen
# samples and nothing else, the state `seed-state.sh` leaves. A checker that names only the
# ten files the operation writes has nothing to say about that state, so it exits 0 and the
# engine correctly refuses to trust an instrument it could not make respond.
#
# Judging every entry fixes that and is the truer invariant anyway: a state holding a file
# that is neither a sample nor a whole overcommit hook is one a user would not accept,
# whoever put it there.
set -u
h=${OC_HOOKS:-/tmp/oc-repo/.git/hooks}
fail() { echo "check: $*" >&2; exit 1; }

[ -d "$h" ] || fail "the hooks directory is gone"


for f in "$h"/* "$h"/.*; do
    b=${f##*/}
    case "$b" in .|..) continue ;; esac
    # `old-hooks` is overcommit's own scratch under this define: it is created, nothing is
    # moved into it (no pre-existing user hook is seeded), and it is removed again —
    # measured, both branches. A world crashed inside that window leaves an empty directory
    # git does not look at, so it is declared `scratch` in the toml for the built-in
    # invariants and skipped here for the same reason. **Under a define that seeds a
    # pre-existing hook this would be wrong**: there the directory holds the user's file.
    # Skipped only when it is what the tool makes — a DIRECTORY. A regular file of that name
    # is not overcommit's scratch and falls through to the checks below, so the skip cannot
    # become a hiding place for a corrupted file that happens to carry the name.
    if [ "$b" = old-hooks ] && [ -d "$f" ]; then continue; fi
    [ -e "$f" ] || continue                 # the glob itself when the directory is empty
    [ -f "$f" ] || fail "$b exists and is not a regular file"
    case "$b" in
        *.sample)
            # git writes these; install must leave them alone. Their first two bytes are
            # what says the file is still a script rather than whatever replaced it.
            head -c 2 "$f" | grep -q '#!' || fail "$b is a git sample and no longer starts with a shebang"
            ;;
        *)
            # The NAME is the subject, so it is what `case` matches and the ten names are
            # literal patterns. The earlier form put the name IN the pattern
            # (`case "$managed" in *" $b "*`), which makes a filename carrying `*` or `?`
            # into a glob that can match a managed name it is not. Nothing overcommit writes
            # carries one, which is exactly why it would have gone unnoticed.
            case "$b" in
                commit-msg|overcommit-hook|post-checkout|post-commit|post-merge|\
                post-rewrite|pre-commit|pre-push|pre-rebase|prepare-commit-msg)
                    # Both ends, because a file holding only the leading comment would pass a
                    # name-only test: the entrypoint names itself in its header and again in
                    # its last lines, so the tail is what says the copy reached its end.
                    head -c 200 "$f" | grep -q 'Overcommit' || fail "$b exists but is not overcommit's"
                    tail -c 200 "$f" | grep -q 'EX_SOFTWARE' || fail "$b is cut short before its rescue block"
                    [ -x "$f" ] || fail "$b is not executable, so git would skip the hook install wrote"
                    ;;
                *) fail "$b is neither a git sample nor a hook overcommit manages" ;;
            esac
            ;;
    esac
done
exit 0
