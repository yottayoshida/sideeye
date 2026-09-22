#!/bin/bash
# A crash point reached on a thread other than the main one kills the world (#569), macOS.
#
#   bash spike/thread-kill-lands.sh [RUNS]        (default 12)
#
# Three toys, each writing three files with open/write/fsync/close — nine crash points — and
# each explored RUNS times with --allow-unverified:
#   pthread  a pthread worker does the writing; the main thread joins it
#   gcd      a block on GCD's global queue does it; the main thread waits on a semaphore
#   nothread the main thread does it, with no other thread (the control)
# Every run must exit 0 with verdict PASS over exactly nine crash points. No root, no oracle.
#
# What it is for. Until #569, the shim's group kill fired from a worker thread was taken by
# another thread on macOS and the worker ran on to the `_exit` behind it, so the world "exited
# on its own" and the run refused `kill_did_not_land`. This script against main 48438c8 on an
# arm64 Mac: the pthread toy refused 11 runs in 12, the gcd toy 12 in 12, and the nothread
# control passed 12 in 12 (BUILDLOG, 2026-09-14).
#
# What it does not know. Its power on the CI runner is not measured: the red above is this
# machine's, with the kill's `raise` and wait removed together. Neither was removed alone as a
# mutation, so nothing here shows that the wait is needed — a build with `raise` and no wait
# passed the gcd toy 12 in 12 — and a change that dropped the wait would leave this green. That
# the defect reaches a hosted runner at all rests on #569's own record of check 6 in
# spike/fsusage/acceptance-local.sh refusing on CI's macOS before this change.
#
# The count is checked as well as the verdict so that a toy which quietly wrote nothing — a
# PASS over zero crash points — cannot read as a kill that landed.
set -u

RUNS="${1:-12}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
[ "$(uname -s)" = Darwin ] || { echo "FAIL: macOS only (GCD, and the defect is XNU's delivery)"; exit 1; }
# At least one: zero runs would pass every toy having measured nothing.
case "$RUNS" in ''|*[!0-9]*|0|0*) echo "FAIL: RUNS must be a positive number, got '$RUNS'"; exit 1 ;; esac

fail() { echo "FAIL: $*"; exit 1; }

WORK="$(mktemp -d "${THREAD_KILL_LANDS_BASE:-$HOME}/thread-kill-lands-XXXXXX")"
# Without this, a base directory that does not exist leaves WORK empty (there is no `set -e`
# here), the build lands in /out, and the script reports "zig build failed" — a true sentence
# about the wrong cause. The CI step creates its base; a hand invocation need not.
# `fail` is defined above rather than below, where it used to sit: the first draft of this guard
# called it four lines before its definition, so the guard itself was a command-not-found that
# nothing stopped, and the run went on to report the build failure it was written to prevent.
[ -n "$WORK" ] || fail "could not make a work directory under ${THREAD_KILL_LANDS_BASE:-$HOME} — does it exist?"
OUT="$WORK/out"
SIDEEYE="$OUT/bin/sideeye"
SHIM="$OUT/lib/libsideeye_shim.dylib"
CC=/usr/bin/cc

echo "predicate: for each of pthread, gcd and nothread, all $RUNS runs exit 0 with verdict PASS"
echo "           over 9 crash points (--allow-unverified, no oracle)"
echo "work: $WORK"

# Into a prefix that did not exist a moment ago, for the reason spike/fsusage/acceptance-local.sh
# gives: an existence or mtime check on zig-out cannot tell this tree's binary from a cached one.
( cd "$HERE" && zig build --prefix "$OUT" ) || fail "zig build failed; nothing was measured"
[ -x "$SIDEEYE" ] || fail "zig build installed no binary at $SIDEEYE"
[ -f "$SHIM" ] || fail "zig build installed no shim at $SHIM"

cat > "$WORK/toy.c" <<'EOF'
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static const char *dir;
static int rc = 1;
static dispatch_semaphore_t done;
static int writefile(const char *name) {
    char p[1024]; snprintf(p, sizeof(p), "%s/%s", dir, name);
    int fd = open(p, O_CREAT | O_WRONLY | O_TRUNC, 0600);
    if (fd < 0) { perror("open"); return 1; }
    if (write(fd, "ok\n", 3) != 3) { perror("write"); return 1; }
    if (fsync(fd) != 0) { perror("fsync"); return 1; }
    if (close(fd) != 0) { perror("close"); return 1; }
    return 0;
}
static int body(void) { return writefile("keep") || writefile("keep2") || writefile("keep3"); }
static void *pworker(void *arg) { (void)arg; rc = body(); return NULL; }
static void gworker(void *arg) { (void)arg; rc = body(); dispatch_semaphore_signal(done); }
int main(int argc, char **argv) {
    dir = getenv("PROBE_STATE"); if (!dir) dir = "./state";
    const char *kind = argc > 1 ? argv[1] : "nothread";
    if (strcmp(kind, "pthread") == 0) {
        pthread_t t;
        if (pthread_create(&t, NULL, pworker, NULL) != 0) return 1;
        if (pthread_join(t, NULL) != 0) return 1;
        return rc;
    }
    if (strcmp(kind, "gcd") == 0) {
        done = dispatch_semaphore_create(0);
        dispatch_async_f(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), NULL, gworker);
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        return rc;
    }
    return body();
}
EOF
"$CC" -O0 -pthread -o "$WORK/toy" "$WORK/toy.c" || fail "could not build the toy"

# One read of a report: its verdict, crash points and unknown_reason, space-separated.
report() { python3 -c "
import json,sys
try: d=json.load(open(sys.argv[1])); print(d.get('verdict'), d.get('crash_points'), d.get('unknown_reason'))
except Exception: print('(no-json) - -')" "$1"; }
# The refusal's own words: `message` says which of the engine's refusal sites fired
# (of the six that answer `kill_did_not_land`, the three in the world loop are the ones a
# run here can reach — no landing record, a different operation sequence, a world that
# exited on its own; the three in `containment.zig` are cgroup-side and this script is
# macOS-only), and `next_step` says whose fault it reads as.
detail() { python3 -c "
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    print('    message:  ', (d.get('message') or '-').replace(chr(10), ' '))
    print('    next_step:', (d.get('next_step') or '-').replace(chr(10), ' ')[:300])
except Exception as e: print('    (report unreadable:', e, ')')" "$1"; }

# A failing run keeps everything it produced. Twice (2026-09-16 and 2026-09-18, #625) one
# run in twelve refused `kill_did_not_land` on the hosted runner, the summary line above was
# all CI kept, and neither occurrence could be told apart from the others afterwards: the
# work directory is a temp path nothing uploads. So the failing run's report, its explore
# transcript and its world directory (the world's trace files and its stdout) are copied
# under failed/, which the CI job uploads when the step is red, and the report's own words
# are printed here beside the summary.
keep_failed() {
    local kind=$1 i=$2 dst="$WORK/failed/$kind-$i"
    mkdir -p "$dst"
    cp "$WORK/$kind-$i.json" "$WORK/$kind-$i.txt" "$dst/" 2>/dev/null
    [ -d "$WORK/w-$kind-$i" ] && cp -R "$WORK/w-$kind-$i" "$dst/world"
    detail "$WORK/$kind-$i.json"
    # The transcript opens with the verdict, the reason and its sentence. Measured on the
    # refusal the pre-#569 shim produces ("a world that should have been killed exited on its
    # own"), where the closing lines carried nothing the opening lines had not; the engine's
    # other refusal sites were not read this way, and the diagnosis does not rest on this
    # excerpt — `message` above comes from the report.
    echo "    transcript (first 4 lines of $kind-$i.txt):"
    head -n 4 "$WORK/$kind-$i.txt" | sed 's/^/      | /'
    # What was actually kept, rather than what the copies were asked to keep: a run whose
    # world directory is gone (a setup that failed and undid its own mkdirs) copies less, and
    # the difference belongs in the log rather than in the reader's assumption.
    echo "    kept under: $dst — $(cd "$dst" && ls | tr '\n' ' ')"
}

# A run that continued past a refused `setpgid(0, 0)` says so on the engine's stderr, which
# lands in this run's transcript (#629, #632, #651). With those fixes in place such a run
# **passes**, so `keep_failed` never sees it, the transcript dies with the temp directory,
# and the one record of the state five CI failures were read as `kill_did_not_land` is lost
# on the only machine where it has ever appeared. The job log is kept whether the step is
# green or red, so the line goes there. Three lines can appear: a child that already led its
# own group (#629, which names the session it read), one that left the engine's with
# `setsid` (#632, which names the group it left), and one refused `setsid` as well because
# the engine's own `setpgid(pid, pid)` had landed by then (#651, which names both errnos).
kept_notes=0
note_kept() {
    local kind=$1 i=$2 lines n
    # All three surviving notes open this way — the one that kept its group (#629), the one
    # that left the engine's with `setsid` (#632), and the one refused `setsid` as well and
    # found the group its own by then (#651) — and so do the shortened strings each falls
    # back to if its buffer is ever too small, which naming `errno` would miss.
    lines=$(grep "sideeye: setpgid(0, 0) failed" "$WORK/$kind-$i.txt" 2>/dev/null) || return 0
    [ -n "$lines" ] || return 0
    n=$(printf '%s\n' "$lines" | wc -l | tr -d ' ')
    kept_notes=$((kept_notes + 1))
    echo "  $kind run $i: $n child(ren) continued past a refused setpgid(0, 0) (#629, #632, #651)"
    # Every line, not the first. A run forks a child per crash point, and they need not
    # agree: which branch each child took is the reading, and nothing puts the interesting
    # one first. Bounded so a build where every child writes one (the mutation this was seen
    # red with, eleven per run) cannot bury the summary below.
    printf '%s\n' "$lines" | head -n 20 | sed 's/^/      | /'
    [ "$n" -gt 20 ] && echo "      | (and $((n - 20)) more)"
    return 0
}

bad=0
for kind in pthread gcd nothread; do
    pass=0
    for i in $(seq 1 "$RUNS"); do
        st="$WORK/state-$kind-$i"; mkdir -p "$st"
        PROBE_STATE="$st" "$SIDEEYE" explore --state "$st" --operation "$WORK/toy $kind" \
            --shim "$SHIM" --work "$WORK/w-$kind-$i" --json "$WORK/$kind-$i.json" --allow-unverified \
            > "$WORK/$kind-$i.txt" 2>&1
        rc=$?
        read -r verdict points reason <<< "$(report "$WORK/$kind-$i.json")"
        note_kept "$kind" "$i" # before the verdict branch: a green run carries it too
        if [ "$rc" = "0" ] && [ "$verdict" = "PASS" ] && [ "$points" = "9" ]; then
            pass=$((pass + 1))
        else
            echo "  $kind run $i: exit=$rc verdict=$verdict crash_points=$points reason=$reason"
            keep_failed "$kind" "$i"
        fi
    done
    echo "  $kind: $pass of $RUNS passed"
    [ "$pass" = "$RUNS" ] || bad=1
done
# Before the `fail` below, which exits: a red run is the one most worth knowing this about,
# and "none" is itself a reading — without it a green run cannot be told from one that never
# looked. It counts survivors only: a child that neither call would move writes the `could
# not be arranged` note instead and dies, and that run fails, where `keep_failed` prints its
# transcript in full.
if [ "$kept_notes" = "0" ]; then
    echo "  no child continued past a refused setpgid(0, 0) in any run (#629, #632, #651)"
else
    echo "  setpgid(0, 0) was refused, and survived, in $kept_notes run(s) (#629, #632, #651) — the lines above say which state each one was in"
fi
[ "$bad" = "0" ] || fail "a world did not die where it was asked to, or a control failed (see the lines above; the failing runs are kept under $WORK/failed)"
echo "PASS"
