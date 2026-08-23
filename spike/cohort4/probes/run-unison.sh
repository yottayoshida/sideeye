#!/bin/sh
# Cohort-4 probe: unison (PROTOCOL.md "Probe plans", target 2).
# Engine-free: normal executions only, no kill, no crash, no checker.
# State root: one directory holding a/ (changed side), b/ (propagation
# side) and unison/ (the UNISON dir: archives, fpcache, locks, the
# DANGER.README location).
#
# IN-PLACE by design (the cohort-2 borg lesson, carried by that probe's
# committed header): unison derives its archive names from a hash of the
# root descriptors, which include absolute paths, so running A and B in
# different directories manufactures a split that no real explore would
# see. Both runs execute at ONE canonical path, restored from a pristine
# copy of the frozen pre-state before each.
#
# Two modes, and the order is part of the frozen plan:
#
#   bare       No apparatus. The determinism comparison is EXPECTED to
#              split (freshDirStamp folds gettimeofday, getpid and the
#              directory inode into an archived number), and the
#              dedicated copy-mechanism strace must show the kernel-side
#              path (FICLONE ioctl / copy_file_range / sendfile) if the
#              copy stub reaches it. Exit 0 means "the falsifications
#              fired as forecast"; not a probe verdict.
#
#   apparatus  /etc/ld.so.preload carries libfaketime and pin-getpid.so;
#              the CALLER runs the container under seccomp-enosys.json.
#              All nine conditions are judged. NOTE the frozen plan's own
#              forecast: a split that survives the declared apparatus is
#              a NAMED WALL (nondeterministic-writer class), and this
#              script reporting FAIL on 5-determinism is that wall being
#              recorded, not the harness breaking. Which term survives is
#              NOT the one the freeze predicted; unison-clock-diagnosis.txt
#              eliminates clock, pid, mtime and inode one at a time and
#              records the remainder as unattributed.
#
# Conditions 1-6 machine-judged (cohort 2's lib.sh, sourced in place);
# condition 7 is the printed ambient evidence; conditions 8 and 9 are
# preflight.sh. Raw strace logs land in $PROBE_OUT.
set -u
. "$(dirname "$0")/../../cohort2/probes/lib.sh"

MODE=${1:-apparatus}
WS=/tmp/probe-unison-$MODE
OUT=${PROBE_OUT:-$WS}
PREFLIGHT_SH="$(dirname "$0")/../preflight.sh"
PINGETPID_SRC="$(dirname "$0")/../pin-getpid.c"
rm -rf "$WS"; mkdir -p "$WS"

# The frozen operation argv (PROTOCOL: one argv, carried identically by
# the setup run and both probe runs). $PGP delivers pin-getpid.so to the
# TARGET only (empty in bare mode; see the plumbing-correction note).
PGP=""
FTV=""
run_op() { # runs the frozen argv at the canonical root, target-only apparatus
    if [ -n "$FTV" ]; then
        ( cd "$WS/root" && FAKETIME="$FTV" LD_PRELOAD="$PGP" \
            UNISON="$WS/root/unison" HOME="$WS/home" \
            unison ./a ./b -batch -ignoreinodenumbers=true ) 2>&1
    else
        ( cd "$WS/root" && UNISON="$WS/root/unison" HOME="$WS/home" \
            unison ./a ./b -batch -ignoreinodenumbers=true ) 2>&1
    fi
}

if [ "$MODE" = apparatus ]; then
    FTLIB=$(find /usr/lib -name "libfaketime.so.1" | head -1)
    [ -n "$FTLIB" ] || { echo "SETUP: libfaketime not in the image"; exit 2; }
    cc -shared -fPIC -o "$WS/pin-getpid.so" "$PINGETPID_SRC" \
        || { echo "SETUP: pin-getpid.so did not compile"; exit 2; }
    echo "$FTLIB" > /etc/ld.so.preload
    PGP="$WS/pin-getpid.so"
    FTV="@2026-01-01 00:00:00 x0"
    note "apparatus (PROTOCOL, unison plan): ld.so.preload=$FTLIB, FAKETIME='$FTV' and pin-getpid.so applied to the TARGET invocations only, never to the harness. PLUMBING CORRECTION, measured and recorded per the freeze's rule: the first apparatus run exported FAKETIME for the whole script, so the fixtures and the pristine restores were themselves created under the frozen clock. Their mtimes then equalled the frozen instant as the target reads it, which arms unison's own conservative guard (fileinfo.ml:243-249, sleep one second and call the file changed), and libfaketime scales that one-second sleep by the frozen speed: strace showed clock_nanosleep(CLOCK_REALTIME, tv_sec=9223372036), i.e. never. Evidence and the bisection that found it: unison-clock-diagnosis.txt. libfaketime is inert without FAKETIME in the environment, so keeping it out of the harness is the whole fix."
fi

note "unison probe ($MODE), $(unison -version), $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- pre-state, built once at the canonical path, then frozen as pristine --
# Step 1: both replicas identical, one setup run builds the archives.
mkdir -p "$WS/root/a" "$WS/root/b" "$WS/root/unison" "$WS/home"
printf 'the original note, fixed bytes\n' > "$WS/root/a/notes.txt"
printf 'the original note, fixed bytes\n' > "$WS/root/b/notes.txt"
printf 'the bystander, fixed bytes\n' > "$WS/root/a/stable.txt"
printf 'the bystander, fixed bytes\n' > "$WS/root/b/stable.txt"
note "setup run (step 1, archive construction; part of setup, NOT the operation)"
run_op; src=$?
echo "setup run rc=$src"
[ "$src" -eq 0 ] || { echo "SETUP: the archive-construction run failed"; exit 2; }
# Step 2: the changed bytes land on the a side.
printf 'the changed note, fixed bytes, deliberately longer than what it replaces\n' > "$WS/root/a/notes.txt"
cp -a "$WS/root" "$WS/pristine"
cp -a "$WS/home" "$WS/pristine-home"
note "pre-state frozen (pristine copies taken after step 2). unison/ after setup:"
find "$WS/pristine/unison" -type f | sed "s|$WS|WS|" | sort

note "condition 7, ambient: HOME=<WS>/home, restored from pristine-home before every run; UNISON is set explicitly to <WS>/root/unison inside the operation (in-root, PROTOCOL's borg-lesson placement). Restores are printed."

restore() {
    rm -rf "$WS/root" "$WS/home"
    cp -a "$WS/pristine" "$WS/root"
    cp -a "$WS/pristine-home" "$WS/home"
    echo "restore: root and home reset to pristine (canonical path unchanged)"
}

note "run A"; restore
echo "wall before: $(date -u +%H:%M:%S.%N)"
run_op; rcA=$?
echo "wall after:  $(date -u +%H:%M:%S.%N)"
cp -a "$WS/root" "$WS/resultA"

sleep 2
note "run B (>=2s later)"; restore
echo "wall before: $(date -u +%H:%M:%S.%N)"
run_op; rcB=$?
echo "wall after:  $(date -u +%H:%M:%S.%N)"
cp -a "$WS/root" "$WS/resultB"

[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "run A rc=$rcA, run B rc=$rcB (success convention: 0)"

if diff -r "$WS/pristine" "$WS/resultA" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "the state root after run A differs from the pre-state"

# The propagation: b/notes.txt carries the changed bytes; a/ untouched;
# the bystander byte-identical on both sides; no DANGER.README left.
printf 'the changed note, fixed bytes, deliberately longer than what it replaces\n' | cmp -s - "$WS/resultA/b/notes.txt" && prop=carried || prop=NOT-CARRIED
printf 'the changed note, fixed bytes, deliberately longer than what it replaces\n' | cmp -s - "$WS/resultA/a/notes.txt" && asrc=untouched || asrc=CHANGED
printf 'the bystander, fixed bytes\n' | cmp -s - "$WS/resultA/b/stable.txt" && byst=intact || byst=CHANGED
[ ! -f "$WS/resultA/unison/DANGER.README" ] && danger=absent || danger=PRESENT
[ "$prop" = carried ] && [ "$asrc" = untouched ] && [ "$byst" = intact ] && [ "$danger" = absent ] && ok=yes || ok=no
verdict "3-artifacts" $ok "b/notes.txt $prop; a/notes.txt $asrc; b/stable.txt $byst; DANGER.README $danger after a clean run"

# Round-trip through the tool: a second run of the same argv on the
# synced result must leave THE REPLICAS unchanged and report that there
# is nothing to do. The assert is on a/ and b/ deliberately: unison
# rewrites its own archive bytes and appends a session banner to
# unison.log on EVERY invocation, no-op runs included, and the freeze's
# own expected-artifacts line already says the archives are updated.
#
# HARNESS CORRECTION, measured not reasoned: the first cut of this check
# diffed the whole root and went red while the tool printed "Nothing to
# do: replicas have not changed since last sync." It also compared
# against the wrong snapshot - the re-run starts from run B's state, not
# run A's. Both fixed here. Scanning the same class across both probe
# scripts found no other comparison whose unit was wrong: 2-non-noop and
# 5-determinism diff whole roots on purpose, because there the
# bookkeeping is precisely the subject.
rtout=$(run_op); rtrc=$?
if diff -r "$WS/resultB/a" "$WS/root/a" > /dev/null 2>&1 \
   && diff -r "$WS/resultB/b" "$WS/root/b" > /dev/null 2>&1; then rt=unchanged; else rt=MUTATED; fi
rtline=$(echo "$rtout" | grep -m1 "Nothing to do")
[ -n "$rtline" ] && said=yes || said=no
[ "$rtrc" -eq 0 ] && [ "$rt" = unchanged ] && [ "$said" = yes ] && ok=yes || ok=no
verdict "4-round-trip" $ok "re-running the frozen argv on the synced result: rc=$rtrc, replicas $rt, tool's own line: ${rtline:-<none - the tool proposed work>} (uitext.ml carries two such lines, :1325 and :1328; whichever printed is shown)"
echo "$rtout" | tail -3

note "diff -r of the two results (in-place, canonical path):"
before_det=$FAILS
diff -r "$WS/resultA" "$WS/resultB"; drc=$?
if [ "$MODE" = bare ]; then
    [ "$drc" -eq 1 ] && ok=yes || ok=no
    verdict "5-determinism-falsification" $ok "bare runs split as forecast (diff rc=$drc; freshDirStamp's clock/pid/inode terms are live)"
else
    [ "$drc" -eq 0 ] && ok=yes || ok=no
    verdict "5-determinism" $ok "two runs >=2s apart leave byte-identical state roots (diff rc=$drc). If this is FAIL: the residue outlives every declared apparatus and is recorded unattributed (unison-clock-diagnosis.txt eliminates clock, pid, propagated mtime and inode separately); a nondeterministic-writer wall, recorded at probe time, costing no define"
fi

note "strace pass (closure accounting; restored pre-state; raw log kept)"
restore
( cd "$WS/root" && UNISON="$WS/root/unison" HOME="$WS/home" \
    run_strace "$WS/strace.log" env "LD_PRELOAD=$PGP" "FAKETIME=$FTV" \
    unison ./a ./b -batch -ignoreinodenumbers=true ) > /dev/null 2>&1
echo "strace'd run rc=$?"
cp "$WS/strace.log" "$OUT/unison-$MODE.strace" 2>/dev/null || true
note "mutating paths (successful only, deduped):"
closure_paths "$WS/strace.log" "$WS/unattr-count" | sort -u | sed "s|$WS|WS|"
echo "unattributed count: $(cat "$WS/unattr-count" 2>/dev/null || echo '?')"
closure_check "$WS/strace.log" "$WS/root" "$WS/home" /tmp/
note "thread creations (successful CLONE_THREAD):"
thread_counts "$WS/strace.log"

# Copy mechanism, dedicated pass: the closure trace cannot see fd-based
# syscalls (%file,write only), so a zero there is "not measured". Same
# instrument control as himalaya's: a traced os.copy_file_range attempt
# must be visible, or the counts below are meaningless.
note "copy-mechanism pass (dedicated strace: ioctl,copy_file_range,sendfile,sendfile64)"
printf 'control source bytes\n' > "$WS/ctl-src"
strace -f -o "$WS/kcopy-control.log" -e trace=copy_file_range,sendfile,sendfile64 \
    python3 -c "import os; s=os.open('$WS/ctl-src',os.O_RDONLY); d=os.open('$WS/ctl-dst',os.O_WRONLY|os.O_CREAT,0o644); os.copy_file_range(s,d,100)" \
    > /dev/null 2>&1
ctl=$(grep -cE '^\S+ +copy_file_range\(' "$WS/kcopy-control.log")
[ "$ctl" -ge 1 ] || { echo "BROKEN: the copy_file_range control produced $ctl matching lines: the instrument cannot see what it counts"; exit 2; }
echo "instrument control: python os.copy_file_range traced $ctl line(s)"
restore
( cd "$WS/root" && UNISON="$WS/root/unison" HOME="$WS/home" \
    strace -f -o "$WS/kcopy.log" -e trace=ioctl,copy_file_range,sendfile,sendfile64 \
    env "LD_PRELOAD=$PGP" "FAKETIME=$FTV" \
    unison ./a ./b -batch -ignoreinodenumbers=true ) > /dev/null 2>&1
echo "copy-mechanism run rc=$?"
cp "$WS/kcopy.log" "$OUT/unison-$MODE-kcopy.strace" 2>/dev/null || true
kok=$(grep -cE '^\S+ +(copy_file_range|sendfile)\(.*= [0-9]' "$WS/kcopy.log")
kall=$(grep -cE '^\S+ +(copy_file_range|sendfile)\(' "$WS/kcopy.log")
fic=$(grep -cE '^\S+ +ioctl\(.*(FICLONE|0x40049409)' "$WS/kcopy.log")
echo "observed: FICLONE ioctl attempts=$fic; copy_file_range/sendfile attempts=$kall, successful=$kok"
if [ "$MODE" = bare ]; then
    if [ "$kok" -gt 0 ] || [ "$fic" -gt 0 ]; then ok=yes; else ok=no; fi
    verdict "8-visibility-falsification" $ok "the bare copy reaches a kernel-side mechanism the shim cannot see (FICLONE=$fic, successful cfr/sendfile=$kok): the justification for the profile. If FAIL: the stub fell straight to read/write on this filesystem and the apparatus is NOT justified; that goes to the owner before any apparatus run is accepted"
    grep -E '^\S+ +(ioctl\(.*(FICLONE|0x40049409)|copy_file_range\(|sendfile\()' "$WS/kcopy.log" | head -4
else
    [ "$kok" -eq 0 ] && ok=yes || ok=no
    verdict "seccomp-active" $ok "no SUCCESSFUL kernel-side copy (successful cfr/sendfile: $kok of $kall attempts; FICLONE attempts=$fic answered ENOTTY by the arg-filtered rule): the stub fell back to the read/write loop"
    grep -E '^\S+ +(ioctl\(.*(FICLONE|0x40049409)|copy_file_range\(|sendfile\()' "$WS/kcopy.log" | head -4
fi

if [ "$MODE" = apparatus ]; then
    # pin-getpid is deliberately NOT passed to the two preflight gates:
    # preflight owns LD_PRELOAD for its own visibility logger, and an env
    # assignment here REPLACES it rather than adding to it. The first run
    # of this probe did exactly that and reported a wall whose own numbers
    # refused to add up (open: interposed=9 yet unmatched=21, write:
    # interposed=385 yet unmatched=26) - the interposed calls were the
    # `env` process, and unison ran with no logger at all. The pid pin
    # changes generated NAMES, never which syscalls are interposable, so
    # dropping it here costs the measurement nothing.
    note "condition 8, shim visibility agrees with the kernel (preflight, restored pre-state)"
    restore
    ( cd "$WS/root" && PROBE_OUT="$WS" sh "$PREFLIGHT_SH" visibility "$WS/root" -- \
        env "UNISON=$WS/root/unison" "HOME=$WS/home" "FAKETIME=$FTV" \
        unison ./a ./b -batch -ignoreinodenumbers=true )
    vrc=$?
    [ "$vrc" -eq 0 ] && ok=yes || ok=no
    verdict "8-visibility" $ok "preflight visibility rc=$vrc (0 = every in-root mutation matched an interposed call)"

    note "condition 9, the operation has an interior (preflight, restored pre-state)"
    restore
    ( cd "$WS/root" && PROBE_OUT="$WS" sh "$PREFLIGHT_SH" interior "$WS/root" -- \
        env "UNISON=$WS/root/unison" "HOME=$WS/home" "FAKETIME=$FTV" \
        unison ./a ./b -batch -ignoreinodenumbers=true )
    irc=$?
    [ "$irc" -eq 0 ] && ok=yes || ok=no
    verdict "9-interior" $ok "preflight interior rc=$irc; count and per-class breakdown above (a count of 1 goes to the owner, not to a FAIL)"
fi

note "condition 7 evidence, what the runs left in HOME (restored per run):"
find "$WS/home" -type f | sed "s|$WS|WS|" | sort
echo "(end of HOME listing)"

note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
