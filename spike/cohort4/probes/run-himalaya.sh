#!/bin/sh
# Cohort-4 probe: himalaya (PROTOCOL.md "Probe plans", target 1).
# Engine-free: normal executions only, no kill, no crash, no checker.
# State root: the maildir store (root = INBOX, nested-fs layout).
#
# Two modes, and the order is part of the frozen plan (the falsification
# comes before the apparatus it justifies):
#
#   bare       No apparatus. Conditions 1-4 are judged; the determinism
#              comparison is EXPECTED to split (the minted entry name
#              embeds wall clock and pid), and the strace pass must SHOW
#              copy_file_range or sendfile (what the shim cannot see,
#              which is what justifies the seccomp profile). Exit 0 means
#              "the falsifications fired as forecast"; this mode is not a
#              probe verdict.
#
#   apparatus  /etc/ld.so.preload carries libfaketime (FAKETIME frozen)
#              and pin-getpid.so (built here from the committed source);
#              the CALLER runs this container under seccomp-enosys.json
#              (docker --security-opt seccomp=...), which this script
#              verifies by observation: the strace pass must show NO
#              copy_file_range/sendfile. All nine conditions are judged;
#              this is where the accepted verdict lives.
#
# Conditions 1-6 machine-judged (the FAILS counter of cohort 2's lib.sh,
# sourced in place); condition 7 is the printed ambient evidence;
# conditions 8 and 9 are preflight.sh. Raw strace log lands in $PROBE_OUT.
set -u
. "$(dirname "$0")/../../cohort2/probes/lib.sh"

MODE=${1:-apparatus}
WS=/tmp/probe-himalaya-$MODE
OUT=${PROBE_OUT:-$WS}
PREFLIGHT_SH="$(dirname "$0")/../preflight.sh"
PINGETPID_SRC="$(dirname "$0")/../pin-getpid.c"
rm -rf "${WS:?}"; mkdir -p "$WS"

MSGID='1700000000.#0M0P1.probehost'

PGP=""
FTV=""
if [ "$MODE" = apparatus ]; then
    FTLIB=$(find /usr/lib -name "libfaketime.so.1" | head -1)
    [ -n "$FTLIB" ] || { echo "SETUP: libfaketime not in the image"; exit 2; }
    cc -shared -fPIC -o "$WS/pin-getpid.so" "$PINGETPID_SRC" \
        || { echo "SETUP: pin-getpid.so did not compile"; exit 2; }
    echo "$FTLIB" > /etc/ld.so.preload
    PGP="$WS/pin-getpid.so"
    FTV="@2026-01-01 00:00:00 x0"
    note "apparatus (PROTOCOL, himalaya plan): ld.so.preload=$FTLIB; FAKETIME='$FTV' and pin-getpid.so on the TARGET invocations only, never on the harness. PLUMBING CORRECTION, recorded per the freeze's own rule: the plan said the apparatus rides /etc/ld.so.preload, but that file and an exported FAKETIME reach EVERY process the harness runs. pin-getpid there breaks strace, whose child management fails when its own getpid answers 4242 (measured in this probe session: 'strace: Unexpected wait status 0', empty log; faketime-only preload left strace healthy, pin-getpid-only broke it). The mechanism is unchanged: the libc getpid symbol is still interposed in the target, and only the delivery moves to the env var. A frozen clock there is worse: cp -a reads a faked stat and writes the frozen instant as the copy's REAL mtime, which is what hung the unison probe (unison-clock-diagnosis.txt). Both targets therefore carry the apparatus on the target invocations only. CONSEQUENCE FOR THE DEFINE, recorded now: any strace-based observation layer hits the same breakage if pin-getpid is global; the engine run needs the same target-only delivery or an engine-side pid pin."
fi

note "himalaya probe ($MODE), $(himalaya --version | head -1), $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- fixtures, byte-for-byte from the frozen plan --------------------------
mkdir -p "$WS/pre/root/cur" "$WS/pre/root/new" "$WS/pre/root/tmp" \
         "$WS/pre/root/Archive/cur" "$WS/pre/root/Archive/new" "$WS/pre/root/Archive/tmp"
cat > "$WS/pre/root/cur/$MSGID:2,S" <<'EOF'
Return-Path: <probe@example.invalid>
Date: Sat, 01 Mar 2026 09:00:00 +0000
From: Probe Author <probe@example.invalid>
To: Probe Target <target@example.invalid>
Subject: Existing message, fixed bytes
Message-ID: <existing0001@example.invalid>

This is the existing message. Its bytes are part of the freeze.
EOF

note "condition 7, ambient: HOME and XDG_CONFIG_HOME are created FRESH PER RUN under <WS>/home-<run>; the account config is written per run (its maildir.root names that run's root copy) and passed explicitly with -c either way. Shown non-empty-or-empty after the runs."

run_once() { # suffix -> runs the frozen operation against a fresh pre-state copy
    sfx=$1
    cp -a "$WS/pre/root" "$WS/root$sfx"
    mkdir -p "$WS/home-$sfx/.config"
    printf '[accounts.probe]\ndefault = true\nmaildir.root = "%s"\n' "$WS/root$sfx" \
        > "$WS/config-$sfx.toml"
    echo "reset: root$sfx is a fresh copy of the pre-state; home-$sfx and config-$sfx.toml are fresh"
    HOME="$WS/home-$sfx" XDG_CONFIG_HOME="$WS/home-$sfx/.config" \
        LD_PRELOAD="$PGP" FAKETIME="$FTV" \
        himalaya -c "$WS/config-$sfx.toml" maildir messages copy "$MSGID" \
        --maildir . --target Archive 2>&1
}

note "run A"; run_once A; rcA=$?
sleep 2
note "run B (>=2s later)"; run_once B; rcB=$?

[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "run A rc=$rcA, run B rc=$rcB (success convention: 0)"

if diff -r "$WS/pre/root" "$WS/rootA" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "the state root after run A differs from the pre-state"

# Exactly one new file in Archive/cur; every new/ and tmp/ still empty;
# the source message untouched.
n_arch=$(ls "$WS/rootA/Archive/cur" | wc -l | tr -d ' ')
n_tmp=$(find "$WS/rootA/tmp" "$WS/rootA/new" "$WS/rootA/Archive/tmp" "$WS/rootA/Archive/new" -type f | wc -l | tr -d ' ')
[ "$n_arch" = 1 ] && [ "$n_tmp" = 0 ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "Archive/cur holds exactly one file (got $n_arch); new/ and tmp/ everywhere hold zero (got $n_tmp)"
echo "the minted copy's filename in run A:"
ls "$WS/rootA/Archive/cur"
echo "and in run B:"
ls "$WS/rootB/Archive/cur"

copyA=$(ls "$WS/rootA/Archive/cur" | head -1)
cmp -s "$WS/rootA/cur/$MSGID:2,S" "$WS/rootA/Archive/cur/$copyA" && bodies=identical || bodies=DIFFER
case "$copyA" in *":2,S") flags=preserved ;; *) flags=LOST ;; esac
cmp -s "$WS/pre/root/cur/$MSGID:2,S" "$WS/rootA/cur/$MSGID:2,S" && src=untouched || src=CHANGED
[ "$bodies" = identical ] && [ "$flags" = preserved ] && [ "$src" = untouched ] && ok=yes || ok=no
verdict "4-round-trip" $ok "copy body $bodies to the source; flag suffix $flags; source file $src"
echo "tool read-back of the target folder (envelope list -m Archive, informational):"
HOME="$WS/home-A" XDG_CONFIG_HOME="$WS/home-A/.config" \
    himalaya -c "$WS/config-A.toml" envelope list -m Archive 2>&1 | head -5

note "diff -r of the two state roots:"
diff -r "$WS/rootA" "$WS/rootB"; drc=$?
if [ "$MODE" = bare ]; then
    # The falsification the PROTOCOL requires before the apparatus is
    # used: bare runs MUST split (minted name = wall clock + pid).
    [ "$drc" -eq 1 ] && ok=yes || ok=no
    verdict "5-determinism-falsification" $ok "bare runs split as forecast (diff rc=$drc; the minted filenames above show the differing clock and pid fields)"
else
    [ "$drc" -eq 0 ] && ok=yes || ok=no
    verdict "5-determinism" $ok "two runs >=2s apart leave byte-identical state roots (diff rc=$drc)"
fi

note "strace pass (fresh copy; raw log kept as himalaya-$MODE.strace)"
cp -a "$WS/pre/root" "$WS/rootS"
mkdir -p "$WS/home-S/.config"
printf '[accounts.probe]\ndefault = true\nmaildir.root = "%s"\n' "$WS/rootS" > "$WS/config-S.toml"
HOME="$WS/home-S" XDG_CONFIG_HOME="$WS/home-S/.config" \
    run_strace "$WS/strace.log" env "LD_PRELOAD=$PGP" "FAKETIME=$FTV" \
    himalaya -c "$WS/config-S.toml" maildir messages copy "$MSGID" \
    --maildir . --target Archive > /dev/null 2>&1
echo "strace'd run rc=$?"
cp "$WS/strace.log" "$OUT/himalaya-$MODE.strace" 2>/dev/null || true

# The closure log above traces %file,write,clone only; copy_file_range
# and sendfile are fd-based and CANNOT appear in it, so a zero there is
# "not measured", not "absent". The copy-mechanism question gets its own
# strace pass, with a positive control from the same instrument: a
# python os.copy_file_range call traced the same way must yield >=1
# matching line, or the count below is meaningless (a broken grep and an
# active seccomp profile both print 0).
note "copy-mechanism pass (dedicated strace: copy_file_range,sendfile,sendfile64)"
printf 'control source bytes\n' > "$WS/ctl-src"
strace -f -o "$WS/kcopy-control.log" -e trace=copy_file_range,sendfile,sendfile64 \
    python3 -c "import os; s=os.open('$WS/ctl-src',os.O_RDONLY); d=os.open('$WS/ctl-dst',os.O_WRONLY|os.O_CREAT,0o644); os.copy_file_range(s,d,100)" \
    > /dev/null 2>&1
ctl=$(grep -cE '^\S+ +copy_file_range\(' "$WS/kcopy-control.log")
if [ "$MODE" = bare ]; then
    [ "$ctl" -ge 1 ] || { echo "BROKEN: the copy_file_range control produced $ctl matching lines: the instrument cannot see the syscall it is counting"; exit 2; }
    echo "instrument control: python os.copy_file_range traced $ctl line(s) (>=1 required)"
else
    # Under the seccomp profile the control's copy_file_range returns
    # ENOSYS, and the traced line still appears (strace sees the attempt),
    # so the instrument control holds in both modes.
    [ "$ctl" -ge 1 ] || { echo "BROKEN: the copy_file_range control produced $ctl matching lines even as an ENOSYS attempt"; exit 2; }
    echo "instrument control: python os.copy_file_range traced $ctl line(s) (the attempt is visible even when seccomp answers ENOSYS)"
fi
cp -a "$WS/pre/root" "$WS/rootK"
mkdir -p "$WS/home-K/.config"
printf '[accounts.probe]\ndefault = true\nmaildir.root = "%s"\n' "$WS/rootK" > "$WS/config-K.toml"
HOME="$WS/home-K" XDG_CONFIG_HOME="$WS/home-K/.config" \
    strace -f -o "$WS/kcopy.log" -e trace=copy_file_range,sendfile,sendfile64 \
    env "LD_PRELOAD=$PGP" "FAKETIME=$FTV" \
    himalaya -c "$WS/config-K.toml" maildir messages copy "$MSGID" --maildir . --target Archive \
    > /dev/null 2>&1
echo "copy-mechanism run rc=$?"
cp "$WS/kcopy.log" "$OUT/himalaya-$MODE-kcopy.strace" 2>/dev/null || true
kok=$(grep -cE '^\S+ +(copy_file_range|sendfile)\(.*= [0-9]' "$WS/kcopy.log")
kall=$(grep -cE '^\S+ +(copy_file_range|sendfile)\(' "$WS/kcopy.log")
if [ "$MODE" = bare ]; then
    [ "$kok" -gt 0 ] && ok=yes || ok=no
    verdict "8-visibility-falsification" $ok "the bare copy SUCCEEDS through the kernel-side path the shim cannot see (successful copy_file_range/sendfile lines: $kok of $kall attempts): the justification for seccomp-enosys.json"
    grep -E '^\S+ +(copy_file_range|sendfile)\(' "$WS/kcopy.log" | head -3
else
    [ "$kok" -eq 0 ] && [ "$kall" -ge 1 ] && ok=yes || ok=no
    verdict "seccomp-active" $ok "no SUCCESSFUL copy_file_range/sendfile in the dedicated pass, and the target did attempt it (successful: $kok of $kall attempts; zero attempts would mean the profile was never exercised, so it fails too; ENOSYS-failed attempts are the profile working): the copy fell back to the libc read/write loop"
    grep -E '^\S+ +(copy_file_range|sendfile)\(' "$WS/kcopy.log" | head -3
fi

note "mutating paths (successful only, deduped):"
closure_paths "$WS/strace.log" "$WS/unattr-count" | sort -u | sed "s|$WS|WS|"
echo "unattributed count: $(cat "$WS/unattr-count" 2>/dev/null || echo '?')"
closure_check "$WS/strace.log" "$WS/rootS" "$WS/home-S" "$WS/config-S.toml" /tmp/
note "thread creations (successful CLONE_THREAD):"
thread_counts "$WS/strace.log"

if [ "$MODE" = apparatus ]; then
    note "conditions 8 and 9 run WITHOUT pin-getpid, recorded here rather than only in a comment: preflight installs its own visibility logger through LD_PRELOAD, and an env assignment on the target replaces that variable rather than adding to it, which would leave the run with no logger at all (measured once on unison, where it produced a wall whose own counts disagreed). The clock stays on, and is passed the same way the operation gets it: when this note first appeared it was false for this target, because the move to per-invocation apparatus had converted the operation, strace and copy-mechanism calls and left these two still relying on the export it removed (caught by review, which read the minted names in the preflight roots and found a real clock and a real pid). Pinning the pid changes generated NAMES, never which syscalls are interposable, so the two gates measure the same thing either way."
    note "condition 8, shim visibility agrees with the kernel (preflight, fresh copy)"
    cp -a "$WS/pre/root" "$WS/rootV"
    mkdir -p "$WS/home-V/.config"
    printf '[accounts.probe]\ndefault = true\nmaildir.root = "%s"\n' "$WS/rootV" > "$WS/config-V.toml"
    PROBE_OUT="$WS" sh "$PREFLIGHT_SH" visibility "$WS/rootV" -- \
        env "HOME=$WS/home-V" "XDG_CONFIG_HOME=$WS/home-V/.config" "FAKETIME=$FTV" \
        himalaya -c "$WS/config-V.toml" maildir messages copy "$MSGID" --maildir . --target Archive
    vrc=$?
    [ "$vrc" -eq 0 ] && ok=yes || ok=no
    verdict "8-visibility" $ok "preflight visibility rc=$vrc (0 = every in-root mutation matched an interposed call)"

    note "condition 9, the operation has an interior (preflight, fresh copy)"
    cp -a "$WS/pre/root" "$WS/rootI"
    mkdir -p "$WS/home-I/.config"
    printf '[accounts.probe]\ndefault = true\nmaildir.root = "%s"\n' "$WS/rootI" > "$WS/config-I.toml"
    PROBE_OUT="$WS" sh "$PREFLIGHT_SH" interior "$WS/rootI" -- \
        env "HOME=$WS/home-I" "XDG_CONFIG_HOME=$WS/home-I/.config" "FAKETIME=$FTV" \
        himalaya -c "$WS/config-I.toml" maildir messages copy "$MSGID" --maildir . --target Archive
    irc=$?
    [ "$irc" -eq 0 ] && ok=yes || ok=no
    verdict "9-interior" $ok "preflight interior rc=$irc; the count and per-class breakdown are printed above (a count of 1 goes to the owner, not to a FAIL)"
fi

note "condition 7 evidence, what the runs left in HOME (fresh per run):"
find "$WS/home-A" -type f | sed "s|$WS|WS|" | sort
echo "(end of HOME listing)"

note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
