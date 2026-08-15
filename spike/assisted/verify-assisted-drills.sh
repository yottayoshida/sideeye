#!/bin/sh
# verify-assisted-drills.sh — see every leg of verify-assisted.sh red once (#130).
#
# The rehearse-campaign.sh principle, scaled to one verifier: build a scratch git
# repository shaped like an assisted target, plant one defect per drill, and run
# the REAL verify-assisted.sh unmodified against it. A guard is trusted only
# after failing for its own reason (spike/acceptance.sh convention: every check
# seen red once), and each drill pins the message of the leg it expects — a
# verifier that always exits 0 fails three of the four drills, one that always
# exits 1 fails the clean one.
#
# Drills:
#   1  clean order (define commit, then artifact commit)        -> green
#   2  define and artifact in the same commit                   -> D1 red (same commit)
#   3  artifact committed before the define                     -> D1 red (precedes)
#   4  define tuned in the artifact commit                      -> D2 red (differs)
#   5  an artifact never committed at all                       -> green that IGNORES it
#      (the set comes from the anchor tree, not the filesystem)
#   6  artifact renamed in-target after the define              -> still D1 red: the
#      walker follows renames to the pre-define add (kills a --follow-less walker)
#   7  artifact deleted and re-added after the define           -> still D1 red: the
#      OLDEST existence event anchors an artifact (kills a newest-event walker)
#   8  artifact moved out of the target and back                -> still D1 red: rename
#      hops are followed in both directions and in-target events keep counting
#      (kills the out-and-back laundering R1 measured as a false green)
#   9  uncommitted deletions in the working tree                -> verdicts unchanged
#      (kills the filesystem-glob set the first version used: an uncommitted `rm`
#      flipped a red target green, measured)
#  10  the real cohort target (buku) in this repository         -> exit 1 with the
#      same-commit D1 and NO unresolved files: the C071 similarity link git records
#      for report-strict.json resolves through the copy rule (kills a C-blind
#      walker, whose real-history result is exit 2, and an unconfined one, whose
#      result is a pre-cohort anchor)
#  11  define split across two commits with the artifact in between -> D1 red: the
#      define is not complete until its LATEST part (kills an oldest-part walker)
#  12  launcher (ops/explore.sh) tuned in the artifact commit   -> D2 red on the
#      launcher (kills a walker that stops collecting it)
#  13  pre-define artifact deleted by a COMMIT, dissimilar replacement added -> still
#      D1 red: the denominator is the tree united with the history, so a committed
#      deletion cannot shrink it (kills a tree-only set; R2 measured it as the
#      surviving half of the working-tree false green)
#
# Scratch trees live under $HOME (macOS temp_dir is a blocked prefix in this
# workspace) and are removed on exit.
set -u

here=$(cd "$(dirname "$0")" && pwd)
VA="$here/verify-assisted.sh"
[ -x "$VA" ] || { echo "drills: $VA is not executable" >&2; exit 2; }

fails=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

scratch=$(mktemp -d "$HOME/va-drill-XXXXXX") || exit 2
# rm -rf is intercepted by omamori on this workspace; trash is the sanctioned
# fallback for a tmpdir this run created itself (workspace-isolation rule).
trap 'rm -rf "$scratch" 2>/dev/null || /usr/bin/trash "$scratch" 2>/dev/null || true' EXIT

# Build one scratch repo per drill. $1: drill number.
mkrepo() {
    r="$scratch/r$1"
    mkdir -p "$r/spike/assisted/t/ops"
    git -C "$r" init -q -b main
    git -C "$r" -c user.email=d@d -c user.name=d commit -q --allow-empty -m root
    echo "$r"
}
commit() { git -C "$1" add -A && git -C "$1" -c user.email=d@d -c user.name=d commit -q -m "$2"; }
define_files() {
    printf '[world]\nstate = "/tmp/t"\n' > "$1/spike/assisted/t/ops/t.toml"
    printf '#!/bin/sh\nexit 0\n' > "$1/spike/assisted/t/ops/check.sh"
    printf '#!/bin/sh\nexit 0\n' > "$1/spike/assisted/t/ops/setup.sh"
}
artifact_files() { printf '{"verdict":"FAIL"}\n' > "$1/spike/assisted/t/report.json"; }

# ---- drill 1: clean order -> green ----------------------------------------------
r=$(mkrepo 1)
define_files "$r"; commit "$r" "define"
artifact_files "$r"; commit "$r" "artifact"
o=$("$VA" -C "$r" t 2>&1); rc=$?
if [ "$rc" = "0" ] && echo "$o" | grep -q "ALL ORDER CHECKS PASSED"; then
    ok "drill 1: clean order is green"
else
    bad "drill 1: expected green, got exit $rc"; echo "$o" | sed 's/^/     | /'
fi

# ---- drill 2: same commit -> D1 red ---------------------------------------------
r=$(mkrepo 2)
define_files "$r"; artifact_files "$r"; commit "$r" "everything at once"
o=$("$VA" -C "$r" t 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "D1: define and first artifact were introduced by the same commit"; then
    ok "drill 2: same-commit introduction is D1 red"
else
    bad "drill 2: expected D1 same-commit red, got exit $rc"; echo "$o" | sed 's/^/     | /'
fi

# ---- drill 3: artifact first -> D1 red ------------------------------------------
r=$(mkrepo 3)
artifact_files "$r"; commit "$r" "artifact first"
define_files "$r"; commit "$r" "define afterwards"
o=$("$VA" -C "$r" t 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "D1: the first artifact .* precedes the define"; then
    ok "drill 3: artifact-before-define is D1 red"
else
    bad "drill 3: expected D1 precedes red, got exit $rc"; echo "$o" | sed 's/^/     | /'
fi

# ---- drill 4: define tuned at the artifact commit -> D2 red ---------------------
r=$(mkrepo 4)
define_files "$r"; commit "$r" "define"
artifact_files "$r"
printf '[world]\nstate = "/tmp/t"\n# tuned after the fact\n' > "$r/spike/assisted/t/ops/t.toml"
commit "$r" "artifact plus a tuned define"
o=$("$VA" -C "$r" t 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "D2: spike/assisted/t/ops/t.toml differs between the define commit and the first artifact commit"; then
    ok "drill 4: post-hoc define tuning is D2 red"
else
    bad "drill 4: expected D2 differs red, got exit $rc"; echo "$o" | sed 's/^/     | /'
fi

# ---- drill 5: an uncommitted artifact is not part of the claim ------------------
r=$(mkrepo 5)
define_files "$r"; commit "$r" "define"
artifact_files "$r"; commit "$r" "artifact"
printf '{"verdict":"FAIL"}\n' > "$r/spike/assisted/t/report-extra.json"   # untracked
o=$("$VA" -C "$r" t 2>&1); rc=$?
if [ "$rc" = "0" ] && echo "$o" | grep -q "the working tree differs" && ! echo "$o" | grep -q "report-extra"; then
    ok "drill 5: an untracked file is outside the anchor tree (noted, ignored)"
else
    bad "drill 5: expected green with a working-tree note and no report-extra anchor, got exit $rc"; echo "$o" | sed 's/^/     | /'
fi

# ---- drill 6: in-target rename after the define does not detach the artifact ----
r=$(mkrepo 6)
artifact_files "$r"; commit "$r" "artifact first"
define_files "$r"; commit "$r" "define afterwards"
git -C "$r" mv spike/assisted/t/report.json spike/assisted/t/report-final.json
commit "$r" "rename the artifact"
o=$("$VA" -C "$r" t 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "D1: the first artifact .* precedes the define"; then
    ok "drill 6: an in-target rename still anchors the artifact at its pre-define add"
else
    bad "drill 6: expected D1 precedes red through the rename, got exit $rc"; echo "$o" | sed 's/^/     | /'
fi

# ---- drill 7: delete and re-add does not launder the artifact's age -------------
r=$(mkrepo 7)
artifact_files "$r"; commit "$r" "artifact first"
git -C "$r" rm -q spike/assisted/t/report.json; commit "$r" "delete it"
define_files "$r"; commit "$r" "define"
printf '{"verdict":"FAIL","fresh":true}\n' > "$r/spike/assisted/t/report.json"
commit "$r" "re-add the artifact"
o=$("$VA" -C "$r" t 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "D1: the first artifact .* precedes the define"; then
    ok "drill 7: the OLDEST existence event anchors a deleted-and-re-added artifact"
else
    bad "drill 7: expected D1 precedes red through delete/re-add, got exit $rc"; echo "$o" | sed 's/^/     | /'
fi

# ---- drill 8: moving out of the target and back does not reset provenance -------
r=$(mkrepo 8)
artifact_files "$r"; commit "$r" "artifact first"
git -C "$r" mv spike/assisted/t/report.json parked.json; commit "$r" "move it out"
define_files "$r"; commit "$r" "define"
git -C "$r" mv parked.json spike/assisted/t/report.json; commit "$r" "move it back"
o=$("$VA" -C "$r" t 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "D1: the first artifact .* precedes the define"; then
    ok "drill 8: out-and-back keeps the artifact anchored at its original in-target add"
else
    bad "drill 8: expected D1 precedes red through out-and-back, got exit $rc"; echo "$o" | sed 's/^/     | /'
fi

# ---- drill 9: uncommitted working-tree changes cannot move an anchor ------------
r=$(mkrepo 9)
artifact_files "$r"; commit "$r" "artifact first"
define_files "$r"; commit "$r" "define afterwards"
rm "$r/spike/assisted/t/ops/check.sh" "$r/spike/assisted/t/ops/setup.sh" "$r/spike/assisted/t/report.json"
o=$("$VA" -C "$r" t 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "D1: the first artifact .* precedes the define" && echo "$o" | grep -q "the working tree differs"; then
    ok "drill 9: an uncommitted rm changes nothing (the set is the anchor tree's)"
else
    bad "drill 9: expected the same D1 red plus a working-tree note, got exit $rc"; echo "$o" | sed 's/^/     | /'
fi

# ---- drill 10: the real cohort history exercises the copy rule ------------------
# git records spike/assisted/buku/report-strict.json as a C071 copy of an
# unrelated blind-hunt JSON (measured). A C-blind walker cannot resolve it
# (exit 2); an unconfined one anchors it a day before the cohort existed
# (D1 "precedes"). The committed rule yields the same-commit red with every file
# resolved.
o=$("$VA" buku 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "D1: define and first artifact were introduced by the same commit" && ! echo "$o" | grep -q "no resolvable introduction"; then
    ok "drill 10: the real buku history resolves every anchor through the copy rule"
else
    bad "drill 10: expected the cohort same-commit red with no unresolved files, got exit $rc"; echo "$o" | sed 's/^/     | /'
fi

# ---- drill 11: the define is not complete until its latest part -----------------
r=$(mkrepo 11)
printf '[world]\nstate = "/tmp/t"\n' > "$r/spike/assisted/t/ops/t.toml"
printf '#!/bin/sh\nexit 0\n' > "$r/spike/assisted/t/ops/setup.sh"
commit "$r" "define, most of it"
artifact_files "$r"; commit "$r" "artifact"
printf '#!/bin/sh\nexit 0\n' > "$r/spike/assisted/t/ops/check.sh"
commit "$r" "the checker arrives last"
o=$("$VA" -C "$r" t 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "D1: the first artifact .* precedes the define (spike/assisted/t/ops/check.sh"; then
    ok "drill 11: a define completed after the artifact is D1 red on its latest part"
else
    bad "drill 11: expected D1 red anchored on the late checker, got exit $rc"; echo "$o" | sed 's/^/     | /'
fi

# ---- drill 13: a committed deletion cannot shrink the denominator ---------------
r=$(mkrepo 13)
artifact_files "$r"; commit "$r" "artifact first"
define_files "$r"; commit "$r" "define"
git -C "$r" rm -q spike/assisted/t/report.json
printf 'completely different content, nothing like the old report\n' > "$r/spike/assisted/t/report-final.json"
commit "$r" "drop the early report, add a dissimilar one"
o=$("$VA" -C "$r" t 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "D1: the first artifact .* precedes the define" && echo "$o" | grep -q "no longer in the tree"; then
    ok "drill 13: a committed deletion leaves the old answer in the denominator, annotated"
else
    bad "drill 13: expected D1 red anchored on the deleted report, got exit $rc"; echo "$o" | sed 's/^/     | /'
fi

# ---- drill 12: a tuned launcher is D2 red ---------------------------------------
r=$(mkrepo 12)
define_files "$r"
printf '#!/bin/sh\nexec engine "$@"\n' > "$r/spike/assisted/t/ops/explore.sh"
commit "$r" "define with launcher"
artifact_files "$r"
printf '#!/bin/sh\nHOME=/elsewhere exec engine "$@"\n' > "$r/spike/assisted/t/ops/explore.sh"
commit "$r" "artifact plus a tuned launcher"
o=$("$VA" -C "$r" t 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "D2: spike/assisted/t/ops/explore.sh differs"; then
    ok "drill 12: a launcher tuned between question and answer is D2 red"
else
    bad "drill 12: expected D2 red on the launcher, got exit $rc"; echo "$o" | sed 's/^/     | /'
fi

echo ""
if [ "$fails" -eq 0 ]; then
    echo "ALL DRILLS PASSED"
    exit 0
fi
echo "$fails DRILL(S) FAILED"
exit 1
