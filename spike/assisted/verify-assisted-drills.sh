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
#   5  an artifact with no resolvable introduction (untracked)  -> exit 2, never a
#      narrowed-set verdict (the fail-open that produced a false green on real data)
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

# ---- drill 5: unresolvable artifact -> exit 2, not a narrowed verdict -----------
r=$(mkrepo 5)
define_files "$r"; commit "$r" "define"
artifact_files "$r"; commit "$r" "artifact"
printf '{"verdict":"FAIL"}\n' > "$r/spike/assisted/t/report-extra.json"   # untracked
o=$("$VA" -C "$r" t 2>&1); rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "cannot determine the order"; then
    ok "drill 5: an unresolvable artifact refuses (exit 2) instead of narrowing the set"
else
    bad "drill 5: expected exit 2 cannot-determine, got exit $rc"; echo "$o" | sed 's/^/     | /'
fi

echo ""
if [ "$fails" -eq 0 ]; then
    echo "ALL DRILLS PASSED"
    exit 0
fi
echo "$fails DRILL(S) FAILED"
exit 1
