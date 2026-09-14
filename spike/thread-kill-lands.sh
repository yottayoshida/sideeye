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

WORK="$(mktemp -d "${THREAD_KILL_LANDS_BASE:-$HOME}/thread-kill-lands-XXXXXX")"
OUT="$WORK/out"
SIDEEYE="$OUT/bin/sideeye"
SHIM="$OUT/lib/libsideeye_shim.dylib"
CC=/usr/bin/cc

fail() { echo "FAIL: $*"; exit 1; }

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
        if [ "$rc" = "0" ] && [ "$verdict" = "PASS" ] && [ "$points" = "9" ]; then
            pass=$((pass + 1))
        else
            echo "  $kind run $i: exit=$rc verdict=$verdict crash_points=$points reason=$reason"
        fi
    done
    echo "  $kind: $pass of $RUNS passed"
    [ "$pass" = "$RUNS" ] || bad=1
done
[ "$bad" = "0" ] || fail "a world did not die where it was asked to, or a control failed (see the lines above)"
echo "PASS"
