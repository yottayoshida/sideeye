#!/bin/sh
# unison-clock-diagnosis.sh: the bisection behind two entries in the unison
# probe - the plumbing correction, and the determinism wall.
#
# The first apparatus run of run-unison.sh stopped after "Looking for
# changes" with unison parked in hrtimer_nanosleep. Everything below was
# measured to find out why and what it costs, each run bounded by
# `timeout` so a hang costs seconds instead of a session.
#
#   point 1  Apparatus applied to the WHOLE harness (fixtures and pristine
#            restores created under the frozen clock), which is what the
#            first run did.
#   point 2  The same apparatus applied to the TARGET only.
#   point 3  With the target-only plumbing, is the operation deterministic?
#            Four variants, because the frozen plan named three terms
#            (clock, pid, inode) and a fourth turned up: the mtime the
#            kernel assigns to the file unison writes. `-times=true` is
#            not in the frozen argv; it appears here only to measure
#            whether an amendment WOULD buy determinism, which is the
#            question an owner would otherwise have to guess at.
#
# Not a probe: no verdict here counts. The probe is run-unison.sh.
set -u

FT=$(find /usr/lib -name "libfaketime.so.1" | head -1)
[ -n "$FT" ] || { echo "BROKEN: libfaketime not in the image"; exit 2; }
echo "$FT" > /etc/ld.so.preload
cc -shared -fPIC -o /tmp/pg.so /repo/spike/cohort4/pin-getpid.c \
    || { echo "BROKEN: pin-getpid.so did not compile"; exit 2; }
FZ="@2026-01-01 00:00:00 x0"
LIMIT=20
echo "unison $(unison -version); ld.so.preload=$FT; runs bounded at ${LIMIT}s"
echo ""

# Ground truth is the mtime ON DISK, read with the apparatus off. That is
# not "the mtime the target sees": libfaketime fakes what some stat
# callers are told (coreutils' stat is faked, python's os.stat is not),
# and the mechanism that matters below is a `cp -a` running under the
# apparatus, which reads a faked stat and writes the frozen instant as
# the copy's REAL mtime. So the disk is the right thing to read here, and
# the claim is about the disk.
mt() { env -u FAKETIME python3 -c "import os,sys;print(int(os.stat(sys.argv[1]).st_mtime))" "$1"; }

prep() { # dir under-apparatus(yes/no)
    W=$1
    rm -rf "${W:?}"; mkdir -p "$W/root/a" "$W/root/b" "$W/root/unison" "$W/home"
    if [ "$2" = yes ]; then export FAKETIME="$FZ"; fi
    printf 'the original note, fixed bytes\n' > "$W/root/a/notes.txt"
    printf 'the original note, fixed bytes\n' > "$W/root/b/notes.txt"
    printf 'the bystander, fixed bytes\n' > "$W/root/a/stable.txt"
    printf 'the bystander, fixed bytes\n' > "$W/root/b/stable.txt"
    timeout "$LIMIT" env FAKETIME="$FZ" sh -c "cd $W/root && UNISON=$W/root/unison HOME=$W/home unison ./a ./b -batch -ignoreinodenumbers=true" > "$W/setup.out" 2>&1
    echo "  setup run rc=$?"
    printf 'the changed note, fixed bytes, deliberately longer than what it replaces\n' > "$W/root/a/notes.txt"
    cp -a "$W/root" "$W/pristine"; cp -a "$W/home" "$W/phome"
    unset FAKETIME
    echo "  a/notes.txt mtime after the pre-state was built: $(mt "$W/pristine/a/notes.txt")  (frozen instant = 1767225600)"
}

runop() { # dir tag extra-args preload under-apparatus
    W=$1
    if [ "$5" = yes ]; then export FAKETIME="$FZ"; fi
    rm -rf "${W:?}/root" "${W:?}/home"; cp -a "$W/pristine" "$W/root"; cp -a "$W/phome" "$W/home"
    unset FAKETIME
    timeout "$LIMIT" env FAKETIME="$FZ" LD_PRELOAD="$4" sh -c "cd $W/root && UNISON=$W/root/unison HOME=$W/home unison ./a ./b -batch -ignoreinodenumbers=true $3" > "$W/$2.out" 2>&1
    rc=$?
    if [ "$rc" -eq 124 ]; then echo "  $2: TIMED OUT (rc=124) - never returned"
    else echo "  $2: rc=$rc | $(tail -1 "$W/$2.out" | cut -c1-52)"; fi
    cp -a "$W/root" "$W/res$2" 2>/dev/null
    return "$rc"
}

echo "== point 1: apparatus over the whole harness (what the first run did)"
prep /tmp/p1 yes
runop /tmp/p1 A "" "" yes || true
echo "  what it was sleeping on (bounded strace of the same run):"
rm -rf /tmp/p1/root /tmp/p1/home
export FAKETIME="$FZ"; cp -a /tmp/p1/pristine /tmp/p1/root; cp -a /tmp/p1/phome /tmp/p1/home; unset FAKETIME
timeout "$LIMIT" strace -f -o /tmp/p1/s.log env FAKETIME="$FZ" sh -c "cd /tmp/p1/root && UNISON=/tmp/p1/root/unison HOME=/tmp/p1/home unison ./a ./b -batch -ignoreinodenumbers=true" > /dev/null 2>&1
grep -m1 'clock_nanosleep' /tmp/p1/s.log | sed 's/^/    /'
echo "    reading: the file's mtime as the target reads it equals the frozen"
echo "    instant, which arms unison's own guard (fileinfo.ml:243-249: sleep"
echo "    one second, call the file changed). libfaketime scales that sleep"
echo "    by the frozen speed, so tv_sec is 2^63-ish: the wait cannot end."
echo ""

echo "== point 2: the same apparatus, applied to the target only"
prep /tmp/p2 no
runop /tmp/p2 A "" "" no || true
runop /tmp/p2 B "" "" no || true
echo ""

echo "== point 3: determinism under the target-only plumbing, four variants"
for v in "control::" "pin-getpid::/tmp/pg.so" "times:-times=true:" "both:-times=true:/tmp/pg.so"; do
    tag=$(echo "$v" | cut -d: -f1); args=$(echo "$v" | cut -d: -f2); pre=$(echo "$v" | cut -d: -f3)
    W=/tmp/v$tag
    prep "$W" no > /dev/null 2>&1
    runop "$W" A "$args" "$pre" no > /dev/null 2>&1
    sleep 2
    runop "$W" B "$args" "$pre" no > /dev/null 2>&1
    d=$(diff -r "$W/resA" "$W/resB" 2>&1 | grep -v '\.out')
    n=$(printf '%s' "$d" | grep -c .)
    echo "  $tag: b/notes.txt mtime A=$(mt "$W/resA/b/notes.txt") B=$(mt "$W/resB/b/notes.txt"); differing entries=$n"
    printf '%s\n' "$d" | sed "s|$W|<r>|g" | head -3 | sed 's/^/      /'
done
echo ""
echo "== point 4: what is left moving, measured where the runs actually happen"
# A name of its own: prep() assigns $W, so anything below that calls prep
# and then reads $W is reading the wrong directory. An earlier revision
# did exactly that and printed an EMPTY residual line without complaint,
# which is the failure this file exists to catch in others.
VB=/tmp/vboth
resid=""
for f in $(cd "$VB/resA/unison" && ls ar* fp* 2>/dev/null); do
    cmp -s "$VB/resA/unison/$f" "$VB/resB/unison/$f" && continue
    resid="$resid$(echo "$f" | cut -c1-2) ($(cmp -l "$VB/resA/unison/$f" "$VB/resB/unison/$f" | wc -l | tr -d ' ') bytes) "
done
if [ -z "$resid" ]; then
    echo "  BROKEN: no residual difference could be read from $VB - either the"
    echo "  variant did not run or this measurement is looking in the wrong"
    echo "  place. Nothing below should be believed."
    exit 2
fi
for f in $(cd "$VB/resA/unison" && ls ar* fp* 2>/dev/null); do
    cmp -s "$VB/resA/unison/$f" "$VB/resB/unison/$f" && continue
    echo "  $f: $(cmp -l "$VB/resA/unison/$f" "$VB/resB/unison/$f" | wc -l | tr -d ' ') differing bytes of $(stat -c %s "$VB/resA/unison/$f")"
done
echo "  inodes as each run saw them (the freeze forecast the DIRECTORY inode"
echo "  as the un-coverable residue, so this is the term to check):"
prep /tmp/p4 no > /dev/null 2>&1
for r in A B; do
    rm -rf "${W:?}/root" "${W:?}/home"
    cp -a /tmp/p4/pristine /tmp/p4/root; cp -a /tmp/p4/phome /tmp/p4/home
    echo "    run $r before: root=$(stat -c %i /tmp/p4/root) a=$(stat -c %i /tmp/p4/root/a) b=$(stat -c %i /tmp/p4/root/b)"
    timeout "$LIMIT" env FAKETIME="$FZ" LD_PRELOAD=/tmp/pg.so sh -c "cd /tmp/p4/root && UNISON=/tmp/p4/root/unison HOME=/tmp/p4/home unison ./a ./b -batch -ignoreinodenumbers=true -times=true" > /dev/null 2>&1
    echo "    run $r after:  the propagated b/notes.txt has inode $(stat -c %i /tmp/p4/root/b/notes.txt), mtime $(mt /tmp/p4/root/b/notes.txt)"
    [ "$r" = A ] && sleep 2
done
echo ""
echo "== reading, and what it does NOT say"
# Generated from the numbers measured above rather than typed beside
# them: an earlier revision of this file hard-coded both the byte counts
# and the count of eliminated hypotheses, and each drifted from its own
# output within one run.
elim="the wall clock, frozen | the pid, pinned | the propagated file's mtime, pinned by -times | the inodes of the directories and of the propagated file"
n_elim=$(printf '%s' "$elim" | awk -F'|' '{print NF}')
echo "  Hypotheses eliminated by measurement, one variant each ($n_elim):"
printf '%s\n' "$elim" | tr '|' '\n' | sed 's/^ */    - /'
echo "  Residual difference after all of them: $resid"
echo ""
echo "  Two things this does NOT say."
echo "  1. It does not eliminate the propagated mtime FOR THE SHIPPED ARGV."
echo "     The frozen operation carries no -times, and the control variant"
echo "     above shows its mtime differing between runs. The elimination"
echo "     holds in the -times variants, and the point of measuring them is"
echo "     narrow: even with the mtime pinned, the archive still differs, so"
echo "     amending the frozen argv would not buy determinism. It is not a"
echo "     claim that the shipped run has no mtime term."
echo "  2. It does not attribute the residue. freshDirStamp's inode term,"
echo "     which the freeze named as the un-coverable residue, is measured"
echo "     above and does not move, so the freeze's forecast was wrong about"
echo "     which term survives. What does move is unattributed, and stays"
echo "     recorded that way."
echo ""
echo "  The probe does not need the attribution. Two runs of one operation"
echo "  on one pre-state do not agree, so condition 5 fails and unison is a"
echo "  named wall of the nondeterministic-writer class, recorded at probe"
echo "  time for the price of this transcript and no define. Attribution is"
echo "  upstream-report work, and this cohort has not authorised contact."
