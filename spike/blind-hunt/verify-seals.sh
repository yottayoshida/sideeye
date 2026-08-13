#!/bin/sh
# Seal A artifact (ADR 0012): the two-seal order verifier. Committed at Seal A so the
# audit logic itself is frozen before any result exists that could bend it.
#
# What it checks — and the strength of each check:
#
#   A0  Seal A is an ancestor of Seal B in the pushed history
#   A1  every path in seal-a-contents.txt exists in the Seal A commit
#   A2  no commit between the seals touched the sealed procedure — the whole range
#       A..B, not an endpoint diff: change-and-revert inside the range hides from a
#       two-point comparison (R1 finding). PRD.md and DESIGN.md ride in this set —
#       the criterion wording the campaign is scored against must not move either
#   A3  the ledger only grew: Seal A's ledger is a byte prefix of Seal B's — entries
#       (consultations, breaches) cannot be deleted on the way to Seal B
#   B1  the sweep record (invocations + manifest) first appears at Seal B
#   B3  the committed manifest's invocations_sha256 matches the committed
#       invocations.tsv — the sweep ran against the spelling that was committed,
#       not a tuned variant that was swapped afterwards (R1 finding)
#   B4  the declaration names exactly the target the sealed predicate selects:
#       selection is recomputed from the committed manifest + priority (+ burned
#       list if any) and must equal the single declaration/<name> directory
#       (R1 finding: without recomputation, a declaration for any candidate passed)
#   R1  the exploration run manifest records head == Seal B and a clean worktree
#   R2  (only when a reports directory is supplied) each sealed report re-hashes to
#       the manifest's value — the "not swapped" claim, actually recomputed
#
# All of it audits the *history as pushed*. A reader who trusts the public push
# timestamps gets the ordering; nothing here proves what happened on a private disk
# first (ADR 0012, "what this protocol honestly cannot prove").
#
# Usage: verify-seals.sh <seal-a-sha> <seal-b-sha> [<run-manifest.json>] [<reports-dir>]
# Exit:  0 all supplied checks hold / 1 a check failed / 2 usage error
#
# The verdict line says PARTIAL unless a run manifest was supplied and audited —
# a two-argument invocation cannot claim the full campaign passed (R1 finding).
set -u

[ $# -ge 2 ] && [ $# -le 4 ] || {
    echo "usage: verify-seals.sh <seal-a-sha> <seal-b-sha> [<run-manifest.json>] [<reports-dir>]" >&2
    exit 2
}
A=$1
B=$2
runmanifest=${3:-}
reportsdir=${4:-}

fails=0
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
ok() { echo "ok   $1"; }

git rev-parse --verify "$A^{commit}" >/dev/null 2>&1 || { echo "verify: $A is not a commit" >&2; exit 2; }
git rev-parse --verify "$B^{commit}" >/dev/null 2>&1 || { echo "verify: $B is not a commit" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "verify: python3 is required" >&2; exit 2; }

# The A2 no-touch set is DERIVED from seal-a-contents.txt as committed at Seal A —
# a second hand-written list here would be the two-hand-synced-copies drift this
# repo has already paid for (#65). Two adjustments: the ledger is excluded (A3
# checks it as append-only instead — appending is its job), and PRD/DESIGN are
# added (the criterion wording the campaign is scored against; they are not Seal A
# artifacts, so the contents file does not list them).

# A0 — the seals are ordered in history, not merely two commits somewhere.
if git merge-base --is-ancestor "$A" "$B" 2>/dev/null; then
    ok "A0: Seal A is an ancestor of Seal B"
else
    bad "A0: Seal A is not an ancestor of Seal B"
fi

# A1 — the sealed inventory, read from the seal itself.
contents=$(git show "$A:spike/blind-hunt/seal-a-contents.txt" 2>/dev/null) || {
    bad "A1: seal-a-contents.txt is not in the Seal A commit"
    contents=""
}
if [ -n "$contents" ]; then
    # The case patterns carry a leading '(' on purpose: inside $(...), bash 3.2's
    # parser treats the unbalanced ')' of a bare pattern as the end of the
    # substitution (measured — syntax error on this very line).
    missing=$(echo "$contents" | while read -r path; do
        case "$path" in ('' | '#'*) continue ;; esac
        git cat-file -e "$A:$path" 2>/dev/null || echo "$path"
    done)
    if [ -z "$missing" ]; then
        ok "A1: every sealed path exists in Seal A"
    else
        bad "A1: sealed paths missing from Seal A: $(echo "$missing" | tr '\n' ' ')"
    fi
fi

# A2 — nothing in the range touched the sealed procedure. The range, not the
# endpoints: A..B includes Seal B's own commit, which must add the declaration
# without amending the procedure it is being judged by.
if [ -n "$contents" ]; then
    sealed_paths=$(echo "$contents" | while read -r path; do
        case "$path" in ('' | '#'* | spike/blind-hunt/ledger.md) continue ;; esac
        echo "$path"
    done)
    touched=$(git log --oneline "$A..$B" -- $sealed_paths PRD.md DESIGN.md)
    if [ -z "$touched" ]; then
        ok "A2: no commit between the seals touched the sealed procedure (or the criterion wording)"
    else
        bad "A2: commits between the seals touched sealed paths: $(echo "$touched" | head -3 | tr '\n' '; ')"
    fi
else
    bad "A2: cannot audit — the sealed inventory was unreadable (a check that cannot look must not pass)"
fi

# A3 — the ledger is append-only across the seals, byte for byte. Shell variables
# cannot carry this comparison: command substitution strips trailing newlines, so a
# Seal B that deleted only the final LF would pass a string-prefix test (R2 finding).
# Instead: hash the first len(A) bytes of B's ledger and require A's own blob hash.
if git cat-file -e "$A:spike/blind-hunt/ledger.md" 2>/dev/null; then
    la=$(git cat-file blob "$A:spike/blind-hunt/ledger.md" | wc -c | tr -d ' ')
    a_hash=$(git rev-parse "$A:spike/blind-hunt/ledger.md")
    prefix_hash=$(git cat-file blob "$B:spike/blind-hunt/ledger.md" 2>/dev/null | head -c "$la" | git hash-object --stdin)
    if [ "$prefix_hash" = "$a_hash" ]; then
        ok "A3: Seal A's ledger is a byte prefix of Seal B's (append-only held)"
    else
        bad "A3: the ledger was rewritten between the seals, not appended to"
    fi
else
    bad "A3: ledger.md is not in the Seal A commit"
fi

# B1 — the sweep record postdates the procedure seal.
for path in spike/blind-hunt/invocations.tsv spike/blind-hunt/sweep-manifest.json; do
    if git cat-file -e "$A:$path" 2>/dev/null; then
        bad "B1: $path already exists at Seal A"
    elif git cat-file -e "$B:$path" 2>/dev/null; then
        ok "B1: $path first appears at Seal B"
    else
        bad "B1: $path is absent from Seal B"
    fi
done

# B3 — the committed manifest was produced from the committed invocations.
if git cat-file -e "$B:spike/blind-hunt/sweep-manifest.json" 2>/dev/null &&
   git cat-file -e "$B:spike/blind-hunt/invocations.tsv" 2>/dev/null; then
    want=$(git show "$B:spike/blind-hunt/sweep-manifest.json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("invocations_sha256",""))' 2>/dev/null) || want=""
    got=$(git show "$B:spike/blind-hunt/invocations.tsv" | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')
    if [ -n "$want" ] && [ "$want" = "$got" ]; then
        ok "B3: the manifest's invocations hash matches the committed invocations.tsv"
    else
        bad "B3: the sweep did not run against the committed invocations.tsv (hash mismatch or absent)"
    fi
fi

# B4 — the declaration is for the target the sealed predicate selects, recomputed.
decl=$(git ls-tree -d --name-only "$B:spike/blind-hunt/declaration" 2>/dev/null) || decl=""
if [ -z "$decl" ]; then
    bad "B4: no declaration directory at Seal B"
elif [ "$(echo "$decl" | wc -l | tr -d ' ')" != 1 ]; then
    bad "B4: more than one declaration directory at Seal B: $(echo "$decl" | tr '\n' ' ')"
else
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/verify-seals-XXXXXX") || exit 2
    # Everything below is the *committed* selection machinery, extracted from Seal B —
    # recomputing with the working tree's copies would let an edited selector vouch
    # for itself.
    git show "$B:spike/blind-hunt/select.sh" > "$tmp/select.sh" 2>/dev/null
    git show "$B:spike/blind-hunt/sweep-manifest.json" > "$tmp/manifest.json" 2>/dev/null
    git show "$B:spike/blind-hunt/priority.txt" > "$tmp/priority.txt" 2>/dev/null
    if git cat-file -e "$B:spike/blind-hunt/burned.txt" 2>/dev/null; then
        git show "$B:spike/blind-hunt/burned.txt" > "$tmp/burned.txt"
        selected=$(sh "$tmp/select.sh" "$tmp/manifest.json" "$tmp/priority.txt" "$tmp/burned.txt" 2>/dev/null) || selected=""
    else
        selected=$(sh "$tmp/select.sh" "$tmp/manifest.json" "$tmp/priority.txt" 2>/dev/null) || selected=""
    fi
    # Non-recursive cleanup on purpose: a fixed file list and rmdir, not rm -rf.
    rm -f "$tmp/select.sh" "$tmp/manifest.json" "$tmp/priority.txt" "$tmp/burned.txt" 2>/dev/null
    rmdir "$tmp" 2>/dev/null || true
    if [ -n "$selected" ] && [ "$decl" = "$selected" ]; then
        ok "B4: the declaration is for '$selected', the target the sealed predicate selects"
    else
        bad "B4: declaration '$decl' does not match the recomputed selection '${selected:-<none>}'"
    fi
fi

# R1 — exploration ran at Seal B, from a clean tree (per its own manifest).
r1_audited=0
if [ -n "$runmanifest" ]; then
    if [ -r "$runmanifest" ]; then
        if python3 - "$runmanifest" "$(git rev-parse "$B")" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
sys.exit(0 if m.get("head") == sys.argv[2] and m.get("worktree_clean") is True else 1)
PY
        then
            ok "R1: the run manifest records head == Seal B with a clean worktree"
            r1_audited=1
        else
            bad "R1: the run manifest does not pin head to Seal B with a clean worktree"
        fi
    else
        bad "R1: run manifest unreadable (a check that cannot look must not pass)"
    fi
fi

# R2 — the sealed reports re-hash to the manifest, when they are on hand to check.
if [ -n "$reportsdir" ]; then
    if [ -d "$reportsdir" ] && git cat-file -e "$B:spike/blind-hunt/sweep-manifest.json" 2>/dev/null; then
        # The manifest travels as a file, not a pipe: `python3 -` reads its *program*
        # from stdin, so a heredoc program and piped data cannot share the stream —
        # measured, the pipe silently lost and json.load read EOF.
        r2m=$(mktemp "${TMPDIR:-/tmp}/verify-r2-XXXXXX") || exit 2
        git show "$B:spike/blind-hunt/sweep-manifest.json" > "$r2m"
        if python3 - "$reportsdir" "$r2m" <<'PY'
import hashlib, json, os, sys
m = json.load(open(sys.argv[2]))
bad = 0
for c in m["candidates"]:
    p = os.path.join(sys.argv[1], c["name"] + ".report")
    try:
        h = hashlib.sha256(open(p, "rb").read()).hexdigest()
    except OSError:
        print(f"missing report: {p}", file=sys.stderr)
        bad += 1
        continue
    if h != c["report_sha256"]:
        print(f"hash mismatch: {p}", file=sys.stderr)
        bad += 1
sys.exit(1 if bad else 0)
PY
        then
            ok "R2: every sealed report re-hashes to the committed manifest"
        else
            bad "R2: sealed reports do not match the committed manifest (details above)"
        fi
        rm -f "$r2m"
    else
        bad "R2: reports directory or committed manifest unavailable (a check that cannot look must not pass)"
    fi
fi

echo ""
if [ "$fails" = 0 ]; then
    if [ "$r1_audited" = 1 ]; then
        echo "ALL SEAL CHECKS PASSED (R1 audited)"
    else
        echo "SEAL CHECKS PASSED — PARTIAL: no run manifest supplied, R1 not audited"
    fi
    exit 0
fi
echo "$fails SEAL CHECK(S) FAILED"
exit 1
