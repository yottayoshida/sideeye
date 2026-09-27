#!/bin/bash
# One target, one stage, inside the box:
#
#   docker run --rm --privileged --cgroupns=private --network none \
#       -v <checkout>:/work:ro -v <apparatus>:/ap:ro -v <transcripts>:/out \
#       sideeye-217s bash /ap/run.sh <target> <stage>
#
#   stage entry       `file -L` on the operation's image, then ONE `preflight --twice` in the mode
#                     the page's row was measured in — the row reproduced before it moves
#   stage supervised  N=5 `preflight --twice --observe supervised --oracle strace`; then 3 explores
#                     under the same flags when at least one preflight was accepted
#
# The container is privileged with its own cgroup namespace, so the engine runs as root in a
# cgroup it can make cgroups in — contained, which --observe supervised needs. Every transcript is
# the engine's output as printed, with the exit status appended by this script.
set -u
t=${1:?target}; stage=${2:?stage}
SE=/work/zig-out/bin/sideeye
SHIM=/work/zig-out/lib/libsideeye_shim.so
O=/out/$t; mkdir -p "$O"
SETUP=""; CHECK=""; CWD=""; EXPECT=""

case $t in
jj)
    export JJ_USER=probe JJ_EMAIL=probe@example.invalid JJ_TIMESTAMP=2026-01-01T00:00:00+00:00 \
        JJ_OP_TIMESTAMP=2026-01-01T00:00:00+00:00 JJ_RANDOMNESS_SEED=42 JJ_OP_HOSTNAME=probe-host \
        JJ_OP_USERNAME=probe-user JJ_TZ_OFFSET_MINS=0 HOME=/tmp/cohort2/jj/home
    mkdir -p "$HOME"
    STATE=/tmp/cohort2/jj/repo; SETUP=/ap/jj/setup.sh; CHECK=/ap/jj/check.sh; EXPECT=0
    OP="/usr/local/bin/jj -R /tmp/cohort2/jj/repo commit -m probe"; MODE=wrappers ;;
chezmoi)
    export HOME=/tmp/cz/home
    mkdir -p /tmp/cz/src "$HOME"
    printf 'hello from chezmoi\n' > /tmp/cz/src/dot_testrc
    printf 'second file\n' > /tmp/cz/src/dot_second
    STATE=/tmp/cz/dest; SETUP=/ap/cz-setup.sh
    OP="/usr/local/bin/chezmoi apply --source /tmp/cz/src --destination /tmp/cz/dest --no-tty"; MODE=wrappers ;;
gopass)
    export GOPASS_AGE_PASSWORD=testpassphrase
    # One store made once, copied into the judged root by every setup (gp-setup.sh), so each
    # world starts from the same bytes rather than from a fresh `gopass setup`.
    GOPASS_HOMEDIR=/tmp/gp-golden gopass --yes setup --crypto age --storage fs \
        --name tester --email tester@example.com > "$O/golden-setup.txt" 2>&1
    printf 'first\n' | GOPASS_HOMEDIR=/tmp/gp-golden gopass insert -f seed/entry0 >> "$O/golden-setup.txt" 2>&1
    export GOPASS_HOMEDIR=/tmp/gp
    STATE=/tmp/gp/.local/share/gopass/stores/root; SETUP=/ap/gp-setup.sh
    OP="/usr/local/bin/gopass generate --print=false test/generated 20"; MODE=wrappers ;;
gh)
    export GH_CONFIG_DIR=/tmp/ghcfg HOME=/tmp/ghhome
    STATE=/tmp/ghcfg; SETUP=/ap/gh-setup.sh
    OP="/usr/local/bin/gh config set git_protocol ssh"; MODE=wrappers ;;
lefthook|lefthook-sh)
    export LH_REPO=/tmp/lh-repo LH_HOOKS=/tmp/lh-repo/.git/hooks
    sh /ap/lefthook/seed-state.sh   # `cwd` must exist before the engine starts (docs/cli.md)
    STATE=/tmp/lh-repo/.git/hooks; SETUP=/ap/lefthook/seed-state.sh; CHECK=/ap/lefthook/verify.sh; CWD=/tmp/lh-repo
    if [ "$t" = lefthook ]; then OP="/usr/local/bin/lefthook install"; MODE=syscalls
    else OP="/bin/sh /ap/lhsh.sh"; MODE=none; fi ;;
bbsed)
    STATE=/tmp/bb; SETUP=/ap/bb-setup.sh
    OP="/bin/busybox sed -i s/a/z/ /tmp/bb/f.txt"; MODE=wrappers ;;
shbb)
    STATE=/tmp/bb; SETUP=/ap/bb-setup.sh
    OP="/bin/sh /ap/bbsed.sh"; MODE=syscalls ;;
*) echo "unknown target $t" >&2; exit 2 ;;
esac

define=(--state "$STATE" --operation "$OP")
[ -n "$SETUP" ] && define+=(--setup "$SETUP")
[ -n "$CWD" ] && define+=(--cwd "$CWD")

fresh() { rm -rf "$STATE" /tmp/se-work; mkdir -p "$STATE"; }
say() { echo "$*" | tee -a "$O/$stage-summary.txt"; }
: > "$O/$stage-summary.txt"
say "target $t  stage $stage  engine $("$SE" version)  binary $(sha256sum "$SE" | cut -c1-12)"

if [ "$stage" = entry ]; then
    img=${OP%% *}
    { file -L "$img"; ldd "$img" 2>&1; } > "$O/entry-linkage.txt"
    say "linkage: $(file -bL "$img" | cut -d, -f1-4)"
    [ "$MODE" = none ] && { say "no reproduction leg for $t (reference only)"; exit 0; }
    fresh
    "$SE" preflight --twice "${define[@]}" --observe "$MODE" --shim "$SHIM" \
        --oracle /usr/bin/strace --work /tmp/se-work > "$O/entry-preflight.txt" 2>&1
    rc=$?
    echo "exit $rc" >> "$O/entry-preflight.txt"
    [ -f /tmp/se-work/oracle.txt ] && cp /tmp/se-work/oracle.txt "$O/entry-oracle.txt"
    say "reproduce under --observe $MODE: exit $rc  $(grep -m1 -E '^(UNKNOWN|PASS|FAIL|preflight)' "$O/entry-preflight.txt")"
    if [ "$t" = shbb ]; then
        say "SIGSYS lines in the oracle capture: $(grep -c -- '--- SIGSYS {.*si_code=SYS_SECCOMP' "$O/entry-oracle.txt" 2>/dev/null || echo 0)"
    fi
    exit 0
fi

[ "$stage" = supervised ] || { echo "unknown stage $stage" >&2; exit 2; }
acc=0
for i in 1 2 3 4 5; do
    fresh
    timeout 1800 "$SE" preflight --twice "${define[@]}" --observe supervised \
        --oracle /usr/bin/strace --work /tmp/se-work > "$O/sup-preflight-$i.txt" 2>&1
    rc=$?
    echo "exit $rc" >> "$O/sup-preflight-$i.txt"
    [ "$rc" = 0 ] && acc=$((acc + 1))
    say "preflight $i: exit $rc  $(grep -m1 -E '^(UNKNOWN|SETUP|preflight|  *[a-z_]+$)' "$O/sup-preflight-$i.txt")"
done
say "preflight accepted: $acc of 5"
[ "$acc" -gt 0 ] || exit 0
for i in 1 2 3; do
    fresh
    args=("${define[@]}")
    [ -n "$CHECK" ] && args+=(--check "$CHECK")
    [ -n "$EXPECT" ] && args+=(--expect-status "$EXPECT")
    timeout 3600 "$SE" explore "${args[@]}" --observe supervised --oracle /usr/bin/strace \
        --work /tmp/se-work --json "$O/sup-explore-$i.json" > "$O/sup-explore-$i.txt" 2>&1
    rc=$?
    echo "exit $rc" >> "$O/sup-explore-$i.txt"
    v=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("verdict"), d.get("reason") or "", d.get("crash_points"), (d.get("earliest") or {}).get("crash_point"), d.get("oracle_verified"))' "$O/sup-explore-$i.json" 2>/dev/null)
    say "explore $i: exit $rc  $v"
done
