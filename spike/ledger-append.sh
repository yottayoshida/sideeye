#!/bin/sh
# The only sanctioned way to write to a campaign ledger.
#
# Why: campaign ledgers are append-only, and the verifier enforces it as a byte
# prefix (A3). That discipline has now been broken twice by hand edits that meant
# well — a placeholder "annotated" in place, an entry "corrected" in place — and
# both times the byte-prefix check caught what the editor's intent did not. This
# tool makes the mistake unmakeable: it appends stdin to the ledger and then
# PROVES the result still extends the last committed version, restoring the
# original and failing loudly if it does not.
#
# The comparison baseline is HEAD's copy of the file: every commit must extend
# the previous one, which composes into "Seal A's ledger is a prefix of Seal B's"
# across any number of commits. A ledger not yet in HEAD (first commit of a new
# campaign) is appended without a baseline, and says so.
#
# Usage: ledger-append.sh <campaign-dir>  < text-to-append
# Exit:  0 appended and verified / 1 prefix violation (file restored) / 2 usage
set -u

[ $# -eq 1 ] || { echo "usage: ledger-append.sh <campaign-dir>  < text" >&2; exit 2; }
# Canonicalize FIRST: a relative campaign dir ("." from inside the campaign) used
# to reach `git ls-files` as a path relative to the wrong root, which silently
# took the "untracked, no baseline" branch — the exact bypass this tool exists
# to prevent (delta-review finding).
dir=$(cd "$1" 2>/dev/null && pwd) || { echo "ledger-append: cannot resolve $1" >&2; exit 2; }
ledger=$dir/ledger.md
[ -f "$ledger" ] || { echo "ledger-append: no ledger at $ledger" >&2; exit 2; }

repo_root=$(git -C "$(dirname "$ledger")" rev-parse --show-toplevel 2>/dev/null) || {
    echo "ledger-append: $ledger is not inside a git repository" >&2
    exit 2
}
rel=$(git -C "$repo_root" ls-files --full-name --error-unmatch "$ledger" 2>/dev/null) || rel=""

addition=$(cat)
[ -n "$addition" ] || { echo "ledger-append: refusing to append nothing" >&2; exit 2; }

before=$(mktemp "${TMPDIR:-/tmp}/ledger-before-XXXXXX") || exit 2
cp "$ledger" "$before"

printf '%s\n' "$addition" >> "$ledger"

if [ -z "$rel" ]; then
    echo "ledger-append: appended (file not yet tracked; no baseline to verify against)"
    rm -f "$before"
    exit 0
fi

# The working tree BEFORE this append must itself extend HEAD — if a hand edit
# already broke the prefix, appending on top would bury it, and this tool would
# be laundering the violation it exists to prevent.
if git -C "$repo_root" cat-file -e "HEAD:$rel" 2>/dev/null; then
    baselen=$(git -C "$repo_root" cat-file blob "HEAD:$rel" | wc -c | tr -d ' ')
    base_hash=$(git -C "$repo_root" rev-parse "HEAD:$rel")
    pre_hash=$(head -c "$baselen" "$before" | git hash-object --stdin)
    post_hash=$(head -c "$baselen" "$ledger" | git hash-object --stdin)
    if [ "$pre_hash" != "$base_hash" ] || [ "$post_hash" != "$base_hash" ]; then
        cp "$before" "$ledger"
        rm -f "$before"
        echo "ledger-append: the ledger no longer extends HEAD's version — append refused, file restored" >&2
        echo "ledger-append: someone edited above the append point; fix that first (the verifier's A3 would catch it later, at seal time, which is the expensive place)" >&2
        exit 1
    fi
fi

rm -f "$before"
echo "ledger-append: appended and verified against HEAD ($rel)"
