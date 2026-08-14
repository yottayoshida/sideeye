#!/bin/sh
# The campaign rehearsal: run the ENTIRE blind-hunt pipeline against synthetic
# targets in a scratch git repository, with defects planted one at a time, before
# any real campaign spends its one-shot blindness on discovering an apparatus bug.
#
# Why this exists: campaign 2's first Seal A was voided by a defect (configs
# disagreeing with sealed invocations) that cost nothing to find here and a void
# to find there. Blindness is the only non-renewable resource in this protocol;
# every other artifact can be rebuilt. This script moves apparatus-error
# discovery to where errors are free. The loop-closure experiments already
# demanded mutual-contrast controls of their apparatus ("unpatched must fail,
# patched must pass"); this applies the same demand to the campaign procedure
# itself.
#
# What it does:
#   1. Builds a scratch git repo that mimics the real layout (spike/blind-hunt2/)
#      and copies the REAL sealed tooling byte-for-byte — so it rehearses the
#      tooling that will run, not an adaptation of it.
#   2. Synthetic candidates: toy-ok (/bin/cp writes into its state root — a real
#      recording for preflight) and toy-fail (/bin/false — a real refusal).
#   3. Plants defects one at a time and requires the matching guard to go red:
#      A2 (sealed path touched), A3 (ledger rewritten), B3 (manifest hash),
#      B4 (wrong declaration), R1 (wrong head), R3 (wrong engine), the voided-
#      anchor preamble, the config/invocation check, the campaign walker, the
#      ledger-append tool, and the driver's refusals.
#   4. Runs the REAL container sweep through the driver, seals a toy Seal B, and
#      requires the full verify battery to end green: ALL SEAL CHECKS PASSED
#      (R1 audited).
#
# Requirements: git, python3, docker (image sideeye-blindhunt:latest), and the
# engine built at zig-out/ (any revision — the rehearsal tests the apparatus,
# not the engine). Scratch lives under $HOME and is removed on success, kept on
# failure with its path printed.
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

# Fabricate a plausible sweep manifest against the COMMITTED invocations (host
# drills need history shapes, not real preflight verdicts; the real sweep runs
# in drill group F). Reports are fabricated alongside so R2 stays exercisable.
fab_manifest() {  # fab_manifest <repo> [corrupt-hash|""] > writes manifest + reports
    python3 - "$1" "$CAMP" "${2:-}" <<'PY'
import hashlib, json, os, sys
repo, camp, corrupt = sys.argv[1], sys.argv[2], sys.argv[3]
inv = open(os.path.join(repo, camp, "invocations.tsv"), "rb").read()
h = hashlib.sha256(inv).hexdigest() if not corrupt else "0" * 64
rdir = os.path.join(repo, camp, "fab-reports")
os.makedirs(rdir, exist_ok=True)
cands = []
for name, code in (("toy-ok", 0), ("toy-fail", 2)):
    body = f"fabricated report for {name}\n".encode()
    open(os.path.join(rdir, name + ".report"), "wb").write(body)
    cands.append({"name": name, "exit": code, "resolved": "yes",
                  "report_sha256": hashlib.sha256(body).hexdigest()})
m = {"schema": "sideeye/blind-hunt-sweep", "invocations_sha256": h,
     "engine": "sideeye rehearsal", "engine_sha256": "e" * 64,
     "shim_sha256": "f" * 64, "image": "rehearsal", "candidates": cands}
json.dump(m, open(os.path.join(repo, camp, "sweep-manifest.json"), "w"), indent=1)
PY
}

seal_b() {  # seal_b <repo> <declared-name>
    mkdir -p "$1/$CAMP/declaration/$2"
    printf 'rehearsal declaration stub for %s\n' "$2" > "$1/$CAMP/declaration/$2/declaration.md"
    git -C "$1" add -A
    git -C "$1" commit -qm "rehearsal: Seal B"
    git -C "$1" rev-parse HEAD
}

verify() {  # verify <repo> <A> <B> [run] [reports]
    ( cd "$1" && sh "$CAMP/verify-seals.sh" "$2" "$3" "${4:-}" "${5:-}" )
}

fab_run_manifest() {  # fab_run_manifest <path> <head> <engine-sha> <shim-sha>
    printf '{\n  "head": "%s",\n  "worktree_clean": true,\n  "engine_sha256": "%s",\n  "shim_sha256": "%s"\n}\n' "$2" "$3" "$4" > "$1"
}

echo "== A. history-shape drills (fabricated manifests, real verifier) =="

r=$(copy a-green); fab_manifest "$r"; git -C "$r" add -A; git -C "$r" commit -qm "sweep record"
B=$(seal_b "$r" toy-ok)
out=$(verify "$r" "$SEALA" "$B"); rc=$?
check_rc 0 $rc "green: seals verify PARTIAL with no run manifest"
echo "$out" | grep -q "PARTIAL" && pass "green: verdict line says PARTIAL" || fail "green: PARTIAL missing from verdict"

r=$(copy a2); fab_manifest "$r"; printf 'smuggled\n' >> "$r/$CAMP/priority.txt"
git -C "$r" add -A; git -C "$r" commit -qm "sweep record + touch sealed path"
B=$(seal_b "$r" toy-ok)
verify "$r" "$SEALA" "$B" >/dev/null 2>&1
check_rc 1 $? "red: A2 catches a sealed path edited between the seals"

r=$(copy a3); fab_manifest "$r"
python3 -c "
p='$r/$CAMP/ledger.md'; s=open(p).read()
open(p,'w').write(s.replace('(none yet','(rewritten',1))"
git -C "$r" add -A; git -C "$r" commit -qm "sweep record + rewritten ledger"
B=$(seal_b "$r" toy-ok)
verify "$r" "$SEALA" "$B" >/dev/null 2>&1
check_rc 1 $? "red: A3 catches a rewritten ledger"

r=$(copy b3); fab_manifest "$r" corrupt; git -C "$r" add -A; git -C "$r" commit -qm "sweep record (hash corrupt)"
B=$(seal_b "$r" toy-ok)
verify "$r" "$SEALA" "$B" >/dev/null 2>&1
check_rc 1 $? "red: B3 catches a manifest not produced from the sealed invocations"

r=$(copy b4); fab_manifest "$r"; git -C "$r" add -A; git -C "$r" commit -qm "sweep record"
B=$(seal_b "$r" toy-fail)
verify "$r" "$SEALA" "$B" >/dev/null 2>&1
check_rc 1 $? "red: B4 catches a declaration for a candidate the predicate did not select"

r=$(copy r-legs); fab_manifest "$r"; git -C "$r" add -A; git -C "$r" commit -qm "sweep record"
B=$(seal_b "$r" toy-ok)
fab_run_manifest "$T/run-good.json" "$B" "$(python3 -c "print('e'*64)")" "$(python3 -c "print('f'*64)")"
out=$(verify "$r" "$SEALA" "$B" "$T/run-good.json" "$r/$CAMP/fab-reports"); rc=$?
check_rc 0 $rc "green: full battery with matching run manifest and reports"
echo "$out" | grep -q "ALL SEAL CHECKS PASSED (R1 audited)" && pass "green: the unqualified verdict line appears" || fail "green: ALL PASSED line missing"

fab_run_manifest "$T/run-badhead.json" "$SEALA" "$(python3 -c "print('e'*64)")" "$(python3 -c "print('f'*64)")"
verify "$r" "$SEALA" "$B" "$T/run-badhead.json" >/dev/null 2>&1
check_rc 1 $? "red: R1 catches a run manifest pinned to the wrong head"

fab_run_manifest "$T/run-badengine.json" "$B" "$(python3 -c "print('a'*64)")" "$(python3 -c "print('f'*64)")"
verify "$r" "$SEALA" "$B" "$T/run-badengine.json" >/dev/null 2>&1
check_rc 1 $? "red: R3 catches an exploration on a different engine than the sweep"

echo "$SEALA" >> "$r/$CAMP/voided-seals.txt"
verify "$r" "$SEALA" "$B" >/dev/null 2>&1
check_rc 2 $? "red: a voided Seal A anchor is refused by name"

echo "== B. guard drills (real guards, planted defects) =="

r=$(copy guards)
printf 'path = /tmp/rehearsal/toy-fail/state/stolen\n' > "$r/$CAMP/configs/toy-ok.conf"
sh "$r/$CAMP/check-config-paths.sh" "$r/$CAMP" >/dev/null 2>&1
check_rc 1 $? "red: config pointing at another row's state root"
sh "$r/spike/check-sealed-campaigns.sh" "$r" >/dev/null 2>&1
check_rc 1 $? "red: the campaign walker relays the config disagreement"

r=$(copy walker)
rm "$r/$CAMP/check-config-paths.sh"
sh "$r/spike/check-sealed-campaigns.sh" "$r" >/dev/null 2>&1
check_rc 1 $? "red: a campaign sealing invocations without its checker"

echo "== C. ledger-append drills =="

r=$(copy ledger)
printf -- '- rehearsal entry one\n' | sh "$r/spike/ledger-append.sh" "$r/$CAMP" >/dev/null 2>&1
check_rc 0 $? "green: append extends HEAD"
python3 -c "
p='$r/$CAMP/ledger.md'; s=open(p).read()
open(p,'w').write(s.replace('# Rehearsal ledger','# Vandalized ledger',1))"
printf -- '- rehearsal entry two\n' | sh "$r/spike/ledger-append.sh" "$r/$CAMP" >/dev/null 2>&1
check_rc 1 $? "red: append refused when the file no longer extends HEAD"
grep -q "rehearsal entry two" "$r/$CAMP/ledger.md" && fail "red: refused append still landed" || pass "red: refused append restored the file"

echo "== D. driver refusal drills =="

r=$(copy drv)
printf 'stray\n' > "$r/stray.txt"
sh "$r/spike/campaign-driver.sh" sweep "$r/$CAMP" "$r/$CAMP/artifacts/sweep" >/dev/null 2>&1
check_rc 2 $? "red: driver sweep refuses a dirty tree"
rm "$r/stray.txt"
fab_manifest "$r"
sh "$r/spike/campaign-driver.sh" sweep "$r/$CAMP" "$r/$CAMP/artifacts/sweep" >/dev/null 2>&1
check_rc 2 $? "red: driver sweep refuses when a manifest already exists"
sh "$r/spike/campaign-driver.sh" explore "$r/$CAMP" "$SEALA" "$r/$CAMP/artifacts/run" >/dev/null 2>&1
check_rc 2 $? "red: driver explore refuses when HEAD is not the given Seal B"

echo "== E. the real sweep, through the driver, end to end =="

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
git -C "$r" add -A; git -C "$r" commit -qm "rehearsal: real sweep record"
sel=$(sh "$r/spike/campaign-driver.sh" select "$r/$CAMP")
[ "$sel" = "toy-ok" ] && pass "green: driver select recomputes toy-ok from the real manifest" || fail "green: selection was '$sel'"
B=$(seal_b "$r" toy-ok)
esha=$(shasum -a 256 "$r/zig-out/bin/sideeye" | cut -d' ' -f1)
ssha=$(shasum -a 256 "$r/zig-out/lib/libsideeye_shim.so" | cut -d' ' -f1)
fab_run_manifest "$T/live-run.json" "$B" "$esha" "$ssha"
out=$(verify "$r" "$SEALA" "$B" "$T/live-run.json" "$r/$CAMP/artifacts/sweep/sealed-reports"); rc=$?
check_rc 0 $rc "green: full battery over the REAL sweep artifacts"
echo "$out" | grep -q "ALL SEAL CHECKS PASSED (R1 audited)" && pass "green: real-artifact run ends ALL PASSED (R1 audited)" || fail "green: ALL PASSED line missing on real artifacts"

echo ""
echo "rehearsal: $drills drills, $fails failure(s)"
if [ "$fails" = 0 ]; then
    rm -rf "$T" 2>/dev/null || /usr/bin/trash "$T" 2>/dev/null || true
    exit 0
fi
echo "rehearsal: scratch kept at $T for inspection" >&2
exit 1
