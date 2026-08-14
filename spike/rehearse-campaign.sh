#!/bin/sh
# The campaign rehearsal: run the ENTIRE blind-hunt pipeline against synthetic
# targets in a scratch git repository, with defects planted one at a time, before
# any real campaign spends its one-shot blindness on discovering an apparatus bug.
#
# Why this exists: campaign 2's first Seal A was voided by a defect (configs
# disagreeing with sealed invocations) that cost nothing to find here and a void
# to find there. Blindness is the only non-renewable resource in this protocol;
# every other artifact can be rebuilt. This script moves apparatus-error
# discovery to where errors are free.
#
# Two rules this file holds itself to, both purchased with same-day failures:
#   * every guard drill asserts the MESSAGE of the guard it claims to test, not
#     just the exit code — the first version had two driver drills passing on
#     the dirty-tree guard while claiming to test two other guards;
#   * the end-to-end leg runs a real exploration through the driver and the
#     sealed runner shape — the first version fabricated the run manifest and
#     still called itself "the entire pipeline".
#
# Requirements: git, python3, docker (image sideeye-blindhunt), and the engine
# built at zig-out/ (any revision — the rehearsal tests the apparatus, not the
# engine). Scratch lives under $HOME; removed on success, kept on failure.
#
# Exit: 0 all drills passed / 1 a drill failed / 2 missing prerequisite
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
CAMP=spike/blind-hunt2

for tool in git python3 docker; do
    command -v "$tool" >/dev/null 2>&1 || { echo "rehearse: $tool is required" >&2; exit 2; }
done
[ -x "$REPO/zig-out/bin/sideeye" ] || { echo "rehearse: build the engine first (zig build -Dtarget=aarch64-linux-gnu)" >&2; exit 2; }
[ -r "$REPO/zig-out/lib/libsideeye_shim.so" ] || { echo "rehearse: shim missing from zig-out/lib" >&2; exit 2; }
# Name-based `image inspect` is flaky on this host (containerd store); accept
# either resolver, as the driver does.
docker image inspect sideeye-blindhunt:latest >/dev/null 2>&1 \
    || [ -n "$(docker images --filter reference=sideeye-blindhunt --format '{{.ID}}' 2>/dev/null | head -1)" ] \
    || { echo "rehearse: image sideeye-blindhunt not found" >&2; exit 2; }

T=$(mktemp -d "$HOME/rehearsal-XXXXXX") || exit 2
fails=0
drills=0

pass() { drills=$((drills + 1)); echo "ok   $1"; }
fail() { drills=$((drills + 1)); fails=$((fails + 1)); echo "FAIL $1"; }
check_rc() {  # check_rc <want> <got> <name>
    if [ "$1" = "$2" ]; then pass "$3 (rc=$2)"; else fail "$3 (rc=$2, wanted $1)"; fi
}
expect_msg() {  # expect_msg <want-rc> <msg-grep> <name> <command...>
    # Both the code AND the message: an exit code alone cannot say WHICH guard
    # fired, and a drill that does not pin the guard can go green on the wrong one.
    want_rc=$1; want_msg=$2; nm=$3; shift 3
    out=$("$@" 2>&1); rc=$?
    if [ "$rc" = "$want_rc" ] && echo "$out" | grep -q "$want_msg"; then
        pass "$nm (rc=$rc, guard matched)"
    else
        fail "$nm (rc=$rc, wanted $want_rc + /$want_msg/)"
        echo "$out" | head -3 | sed 's/^/     | /'
    fi
}

# --- the scratch base: real tooling, toy candidates, one Seal A commit --------

BASE=$T/base
mkdir -p "$BASE/$CAMP/configs" "$BASE/spike"
for f in sweep.sh select.sh verify-seals.sh check-config-paths.sh wrapper-template.sh; do
    cp "$REPO/$CAMP/$f" "$BASE/$CAMP/$f"
done
cp "$REPO/spike/check-sealed-campaigns.sh" "$REPO/spike/ledger-append.sh" "$REPO/spike/campaign-driver.sh" "$BASE/spike/"

printf 'zig-out/\n%s/artifacts/\n' "$CAMP" > "$BASE/.gitignore"
printf 'toy-ok\ntoy-fail\n' > "$BASE/$CAMP/priority.txt"
printf '# rehearsal candidates: synthetic, sighted on purpose — the rehearsal tests the apparatus, not blindness\n' > "$BASE/$CAMP/candidates.md"
printf 'rehearsal seed content\n' > "$BASE/$CAMP/configs/toy-seed.txt"
printf 'path = /tmp/rehearsal/toy-ok/state/toy-ok.conf\n' > "$BASE/$CAMP/configs/toy-ok.conf"
# toy-ok writes through plain read/write syscalls: /bin/cp was tried first and
# preflight refused it honestly — bookworm's cp uses copy_file_range, which the
# trace contract does not cover (unsupported_syscall_observed). dd does not.
printf 'toy-ok\t/bin/dd\t/tmp/rehearsal/toy-ok/state\t/bin/cp /work/%s/configs/toy-ok.conf /tmp/rehearsal/toy-ok/state/toy-ok.conf\t/bin/dd if=/work/%s/configs/toy-seed.txt of=/tmp/rehearsal/toy-ok/state/data.txt\ntoy-fail\t/bin/false\t/tmp/rehearsal/toy-fail/state\t-\t/bin/false\n' "$CAMP" "$CAMP" > "$BASE/$CAMP/invocations.tsv"
cat > "$BASE/$CAMP/ledger.md" <<'EOF'
# Rehearsal ledger

## Entries

(none yet — the rehearsal has not passed its Seal A)
EOF
cat > "$BASE/$CAMP/seal-a-contents.txt" <<EOF
$CAMP/seal-a-contents.txt
$CAMP/candidates.md
$CAMP/priority.txt
$CAMP/invocations.tsv
$CAMP/sweep.sh
$CAMP/select.sh
$CAMP/verify-seals.sh
$CAMP/check-config-paths.sh
$CAMP/wrapper-template.sh
$CAMP/ledger.md
$CAMP/configs/toy-seed.txt
$CAMP/configs/toy-ok.conf
EOF

git -C "$BASE" init -q
git -C "$BASE" config user.email rehearsal@localhost
git -C "$BASE" config user.name rehearsal
git -C "$BASE" add -A
git -C "$BASE" commit -qm "rehearsal: Seal A"
SEALA=$(git -C "$BASE" rev-parse HEAD)

copy() { cp -R "$BASE" "$T/$1"; echo "$T/$1"; }

# Fabricate a sweep manifest against the COMMITTED invocations (history-shape
# drills need shapes, not real preflight verdicts; the real sweep runs in group
# E). Reports are fabricated alongside so R2 stays exercisable.
# Modes: "" normal / corrupt (wrong invocations hash) / bad-digest (engine and
# shim fields present, equal, and NOT hex digests).
fab_manifest() {  # fab_manifest <repo> [mode]
    python3 - "$1" "$CAMP" "${2:-}" <<'PY'
import hashlib, json, os, sys
repo, camp, mode = sys.argv[1], sys.argv[2], sys.argv[3]
inv = open(os.path.join(repo, camp, "invocations.tsv"), "rb").read()
h = "0" * 64 if mode == "corrupt" else hashlib.sha256(inv).hexdigest()
esha, ssha = ("true", "true") if mode == "bad-digest" else ("e" * 64, "f" * 64)
rdir = os.path.join(repo, camp, "fab-reports")
os.makedirs(rdir, exist_ok=True)
cands = []
for name, code in (("toy-ok", 0), ("toy-fail", 2)):
    body = f"fabricated report for {name}\n".encode()
    open(os.path.join(rdir, name + ".report"), "wb").write(body)
    cands.append({"name": name, "exit": code, "resolved": "yes",
                  "report_sha256": hashlib.sha256(body).hexdigest()})
m = {"schema": "sideeye/blind-hunt-sweep", "invocations_sha256": h,
     "engine": "sideeye rehearsal", "engine_sha256": esha,
     "shim_sha256": ssha, "image": "rehearsal", "candidates": cands}
json.dump(m, open(os.path.join(repo, camp, "sweep-manifest.json"), "w"), indent=1)
PY
}

commit_all() { git -C "$1" add -A && git -C "$1" commit -qm "$2"; }

seal_b() {  # seal_b <repo> <declared-name>  (echoes the Seal B sha)
    mkdir -p "$1/$CAMP/declaration/$2"
    printf 'rehearsal declaration stub for %s\n' "$2" > "$1/$CAMP/declaration/$2/declaration.md"
    commit_all "$1" "rehearsal: Seal B"
    git -C "$1" rev-parse HEAD
}

verify() {  # verify <repo> <A> <B> [run] [reports]
    ( cd "$1" && sh "$CAMP/verify-seals.sh" "$2" "$3" "${4:-}" "${5:-}" )
}

fab_run_manifest() {  # fab_run_manifest <path> <head> <engine-sha> <shim-sha>
    printf '{\n  "head": "%s",\n  "worktree_clean": true,\n  "engine_sha256": "%s",\n  "shim_sha256": "%s"\n}\n' "$2" "$3" "$4" > "$1"
}
E64=$(python3 -c "print('e'*64)")
F64=$(python3 -c "print('f'*64)")

echo "== A. history-shape drills (fabricated manifests, real verifier) =="

r=$(copy a-green); fab_manifest "$r"; commit_all "$r" "sweep record"
B=$(seal_b "$r" toy-ok)
out=$(verify "$r" "$SEALA" "$B"); rc=$?
check_rc 0 $rc "green: seals verify PARTIAL with no run manifest"
echo "$out" | grep -q "PARTIAL" && pass "green: verdict line says PARTIAL" || fail "green: PARTIAL missing from verdict"

r=$(copy a2); fab_manifest "$r"; printf 'smuggled\n' >> "$r/$CAMP/priority.txt"
commit_all "$r" "sweep record + touch sealed path"
B=$(seal_b "$r" toy-ok)
expect_msg 1 "A2" "red: A2 catches a sealed path edited between the seals" verify "$r" "$SEALA" "$B"

r=$(copy a3); fab_manifest "$r"
python3 -c "
p='$r/$CAMP/ledger.md'; s=open(p).read()
open(p,'w').write(s.replace('(none yet','(rewritten',1))"
commit_all "$r" "sweep record + rewritten ledger"
B=$(seal_b "$r" toy-ok)
expect_msg 1 "A3" "red: A3 catches a rewritten ledger" verify "$r" "$SEALA" "$B"

r=$(copy b3); fab_manifest "$r" corrupt; commit_all "$r" "sweep record (hash corrupt)"
B=$(seal_b "$r" toy-ok)
expect_msg 1 "B3" "red: B3 catches a manifest not produced from the sealed invocations" verify "$r" "$SEALA" "$B"

r=$(copy b4); fab_manifest "$r"; commit_all "$r" "sweep record"
B=$(seal_b "$r" toy-fail)
expect_msg 1 "B4" "red: B4 catches a declaration for a candidate the predicate did not select" verify "$r" "$SEALA" "$B"

r=$(copy r-legs); fab_manifest "$r"; commit_all "$r" "sweep record"
B=$(seal_b "$r" toy-ok)
fab_run_manifest "$T/run-good.json" "$B" "$E64" "$F64"
out=$(verify "$r" "$SEALA" "$B" "$T/run-good.json" "$r/$CAMP/fab-reports"); rc=$?
check_rc 0 $rc "green: full battery with matching run manifest and reports"
echo "$out" | grep -q "ALL SEAL CHECKS PASSED (R1 audited)" && pass "green: the unqualified verdict line appears" || fail "green: ALL PASSED line missing"

fab_run_manifest "$T/run-badhead.json" "$SEALA" "$E64" "$F64"
expect_msg 1 "R1" "red: R1 catches a run manifest pinned to the wrong head" verify "$r" "$SEALA" "$B" "$T/run-badhead.json"

fab_run_manifest "$T/run-badengine.json" "$B" "$(python3 -c "print('a'*64)")" "$F64"
expect_msg 1 "R3" "red: R3 catches an exploration on a different engine than the sweep" verify "$r" "$SEALA" "$B" "$T/run-badengine.json"

fab_run_manifest "$T/run-badshim.json" "$B" "$E64" "$(python3 -c "print('b'*64)")"
expect_msg 1 "R3" "red: R3 catches a different shim, engine notwithstanding" verify "$r" "$SEALA" "$B" "$T/run-badshim.json"

printf '{\n  "head": "%s",\n  "worktree_clean": true,\n  "engine_sha256": "%s"\n}\n' "$B" "$E64" > "$T/run-noshim.json"
expect_msg 1 "R3" "red: R3 refuses a run manifest missing the shim field" verify "$r" "$SEALA" "$B" "$T/run-noshim.json"

r=$(copy nd); fab_manifest "$r" bad-digest; commit_all "$r" "sweep record (non-digest identity)"
B_ND=$(seal_b "$r" toy-ok)
printf '{\n  "head": "%s",\n  "worktree_clean": true,\n  "engine_sha256": "true",\n  "shim_sha256": "true"\n}\n' "$B_ND" > "$T/run-nondigest.json"
expect_msg 1 "R3" "red: R3 refuses matching non-digest identity fields" verify "$r" "$SEALA" "$B_ND" "$T/run-nondigest.json"

echo "$SEALA" >> "$r/$CAMP/voided-seals.txt"
expect_msg 2 "VOIDED" "red: a voided Seal A anchor is refused by name" verify "$r" "$SEALA" "$B_ND"

echo "== B. guard drills (real guards, planted defects) =="

r=$(copy guards)
printf 'path = /tmp/rehearsal/toy-fail/state/stolen\n' > "$r/$CAMP/configs/toy-ok.conf"
expect_msg 1 "state root" "red: config pointing at another row's state root" sh "$r/$CAMP/check-config-paths.sh" "$r/$CAMP"
expect_msg 1 "disagree" "red: the campaign walker relays the config disagreement" sh "$r/spike/check-sealed-campaigns.sh" "$r"

r=$(copy walker)
rm "$r/$CAMP/check-config-paths.sh"
expect_msg 1 "no executable check-config-paths" "red: a campaign sealing invocations without its checker" sh "$r/spike/check-sealed-campaigns.sh" "$r"

r=$(copy walker2)
chmod -x "$r/$CAMP/check-config-paths.sh"
expect_msg 1 "no executable check-config-paths" "red: a checker present but not executable" sh "$r/spike/check-sealed-campaigns.sh" "$r"

r=$(copy walker3)
mkdir -p "$r/spike/blind-hunt3/configs"
cp "$r/$CAMP/invocations.tsv" "$r/spike/blind-hunt3/"
expect_msg 1 "blind-hunt3" "red: a new campaign cannot inherit the campaign-1 exemption" sh "$r/spike/check-sealed-campaigns.sh" "$r"

r=$(copy walker4)
mkdir -p "$r/spike/blind-hunt3"
out=$(sh "$r/spike/check-sealed-campaigns.sh" "$r"); rc=$?
if [ "$rc" = 0 ] && echo "$out" | grep -q "pre-sweep"; then pass "green: a pre-sweep campaign is skipped, loudly"; else fail "green: pre-sweep skip (rc=$rc)"; fi

mkdir -p "$T/empty/spike"
expect_msg 1 "no campaign directory found" "red: an empty tree refuses instead of passing over nothing" sh "$BASE/spike/check-sealed-campaigns.sh" "$T/empty"

echo "== C. ledger-pen drills =="

r=$(copy ledger)
printf -- '- rehearsal entry one\n' | sh "$r/spike/ledger-append.sh" "$r/$CAMP" >/dev/null 2>&1
check_rc 0 $? "green: append extends HEAD (absolute path)"
python3 -c "
p='$r/$CAMP/ledger.md'; s=open(p).read()
open(p,'w').write(s.replace('# Rehearsal ledger','# Vandalized ledger',1))"
printf -- '- rehearsal entry two\n' | sh "$r/spike/ledger-append.sh" "$r/$CAMP" >/dev/null 2>&1
check_rc 1 $? "red: append refused when the file no longer extends HEAD"
grep -q "rehearsal entry two" "$r/$CAMP/ledger.md" && fail "red: refused append still landed" || pass "red: refused append restored the file"

r=$(copy ledger2)
python3 -c "
p='$r/$CAMP/ledger.md'; s=open(p).read()
open(p,'w').write(s.replace('# Rehearsal ledger','# Vandalized ledger',1))"
( cd "$r/$CAMP" && printf -- '- relative entry\n' | sh ../../spike/ledger-append.sh . ) >/dev/null 2>&1
check_rc 1 $? "red: a relative campaign path cannot bypass the HEAD baseline"

r=$(copy ledger3)
( cd "$r/$CAMP" && printf -- '- relative entry\n' | sh ../../spike/ledger-append.sh . ) > "$T/rel.out" 2>&1
rc=$?
if [ "$rc" = 0 ] && grep -q "verified against HEAD" "$T/rel.out"; then
    pass "green: a relative path still verifies against HEAD"
else
    fail "green: relative append did not verify (rc=$rc)"
fi

echo "== D. driver refusal drills (one guard each, matched by message) =="

r=$(copy drv1); printf 'stray\n' > "$r/stray.txt"
expect_msg 2 "worktree is dirty" "red: driver sweep refuses a dirty tree" \
    sh "$r/spike/campaign-driver.sh" sweep "$r/$CAMP" "$r/$CAMP/artifacts/sweep"

r=$(copy drv2); fab_manifest "$r"; commit_all "$r" "manifest committed"
expect_msg 2 "sweep runs once" "red: driver sweep refuses when a manifest already exists" \
    sh "$r/spike/campaign-driver.sh" sweep "$r/$CAMP" "$r/$CAMP/artifacts/sweep"

r=$(copy drv3); mkdir -p "$r/$CAMP/artifacts/sweep"
expect_msg 2 "must not overwrite" "red: driver sweep refuses an existing output directory" \
    sh "$r/spike/campaign-driver.sh" sweep "$r/$CAMP" "$r/$CAMP/artifacts/sweep"

r=$(copy drv4)
printf '%s/invocations.tsv\n' "$CAMP" >> "$r/.gitignore"
git -C "$r" rm -q --cached "$CAMP/invocations.tsv"
commit_all "$r" "drop invocations from HEAD"
expect_msg 2 "not in HEAD" "red: driver sweep refuses uncommitted invocations" \
    sh "$r/spike/campaign-driver.sh" sweep "$r/$CAMP" "$r/$CAMP/artifacts/sweep"

r=$(copy drv5); fab_manifest "$r"; commit_all "$r" "sweep record"
B=$(seal_b "$r" toy-ok)
expect_msg 2 "is not Seal B" "red: driver explore refuses when HEAD is not the given Seal B" \
    sh "$r/spike/campaign-driver.sh" explore "$r/$CAMP" "$SEALA" "$r/$CAMP/artifacts/run"

r=$(copy drv6); fab_manifest "$r"
expect_msg 2 "worktree is dirty" "red: driver select refuses a dirty tree (worktree/HEAD split)" \
    sh "$r/spike/campaign-driver.sh" select "$r/$CAMP"

r=$(copy drv7)
expect_msg 2 "must live under the repository" "red: driver refuses an outdir outside the repository" \
    sh "$r/spike/campaign-driver.sh" sweep "$r/$CAMP" /tmp/rehearsal-escape

r=$(copy drv8)
expect_msg 2 "contains '..'" "red: driver refuses an outdir that escapes through dot-dot" \
    sh "$r/spike/campaign-driver.sh" sweep "$r/$CAMP" "$r/$CAMP/../../../tmp/escape"

echo "== E. the real pipeline through the driver: sweep, select, seal, explore, audit =="

r=$(copy live)
mkdir -p "$r/zig-out/bin" "$r/zig-out/lib"
cp "$REPO/zig-out/bin/sideeye" "$r/zig-out/bin/"
cp "$REPO/zig-out/lib/libsideeye_shim.so" "$r/zig-out/lib/"
if sh "$r/spike/campaign-driver.sh" sweep "$r/$CAMP" "$r/$CAMP/artifacts/sweep" > "$T/live-sweep.out" 2>&1; then
    pass "green: driver sweep ran the real container sweep"
else
    fail "green: driver sweep failed (see $T/live-sweep.out)"
fi
grep -q "toy-ok exit=0 resolved=yes" "$T/live-sweep.out" && pass "green: toy-ok recording accepted by real preflight" || fail "green: toy-ok was not accepted (see $T/live-sweep.out)"
if grep -q "toy-fail exit=0" "$T/live-sweep.out"; then fail "red: toy-fail was accepted; the refusal leg is dead"; else pass "red: toy-fail refused by real preflight"; fi

cp "$r/$CAMP/artifacts/sweep/sweep-manifest.json" "$r/$CAMP/sweep-manifest.json"
printf -- '- rehearsal: real sweep recorded\n' | sh "$r/spike/ledger-append.sh" "$r/$CAMP" >/dev/null
commit_all "$r" "rehearsal: real sweep record"
sel=$(sh "$r/spike/campaign-driver.sh" select "$r/$CAMP")
[ "$sel" = "toy-ok" ] && pass "green: driver select recomputes toy-ok from the real manifest" || fail "green: selection was '$sel'"

# The Seal B carries a REAL runner: the exploration must come out of the shipped
# driver + a sealed run.sh, not out of a fabricated manifest (delta-review
# finding: the first version audited metadata it had written itself).
mkdir -p "$r/$CAMP/declaration/toy-ok"
cat > "$r/$CAMP/declaration/toy-ok/run.sh" <<'RUNNER'
#!/bin/sh
# Rehearsal runner: one real exploration of toy-ok, then the run manifest with
# the engine identity measured from the binaries that actually ran.
set -u
S=/tmp/rehearsal/explore/state
mkdir -p "$S" "$OUT" || exit 2
"$SIDEEYE" explore --state "$S" \
    --operation "/bin/dd if=/work/spike/blind-hunt2/configs/toy-seed.txt of=$S/data.txt" \
    --shim "$SHIM" --oracle /usr/bin/strace \
    --work /tmp/rehearsal/explore/work --json "$OUT/toy-ok.report.json" \
    > "$OUT/toy-ok.out" 2>&1
rc=$?
echo "toy-ok explore exit=$rc"
esha=$(sha256sum "$SIDEEYE" | cut -d' ' -f1)
ssha=$(sha256sum "$SHIM" | cut -d' ' -f1)
printf '{\n  "head": "%s",\n  "worktree_clean": %s,\n  "engine_sha256": "%s",\n  "shim_sha256": "%s"\n}\n' \
    "$HEAD" "$CLEAN" "$esha" "$ssha" > "$OUT/run-manifest.json"
exit $rc
RUNNER
chmod +x "$r/$CAMP/declaration/toy-ok/run.sh"
B=$(seal_b "$r" toy-ok)

if sh "$r/spike/campaign-driver.sh" explore "$r/$CAMP" "$B" "$r/$CAMP/artifacts/run" > "$T/live-explore.out" 2>&1; then
    pass "green: driver explore ran the sealed runner at Seal B"
else
    fail "green: driver explore failed (see $T/live-explore.out)"
fi
[ -f "$r/$CAMP/artifacts/run/run-manifest.json" ] && pass "green: the runner wrote a real run manifest" || fail "green: run manifest missing"

out=$(verify "$r" "$SEALA" "$B" "$r/$CAMP/artifacts/run/run-manifest.json" "$r/$CAMP/artifacts/sweep/sealed-reports"); rc=$?
check_rc 0 $rc "green: full battery over the REAL sweep and the REAL exploration"
echo "$out" | grep -q "ALL SEAL CHECKS PASSED (R1 audited)" && pass "green: real end-to-end run ends ALL PASSED (R1 audited)" || fail "green: ALL PASSED line missing on real artifacts"

echo ""
echo "rehearsal: $drills drills, $fails failure(s)"
if [ "$fails" = 0 ]; then
    rm -rf "$T" 2>/dev/null || /usr/bin/trash "$T" 2>/dev/null || true
    exit 0
fi
echo "rehearsal: scratch kept at $T for inspection" >&2
exit 1
