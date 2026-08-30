#!/bin/bash
# The three falsifiable checks from the plan, run against a real fs_usage.
#
# Needs root for fs_usage, and sudo's credential cache is per-terminal, so this has to
# be run from a terminal a human is at. It asks once and reuses the cache.
#
#   bash spike/fsusage/acceptance-local.sh
#
# Each check prints its own predicate before its result, so a green line that measured
# nothing is visible as one.
set -u

HERE="$(cd "$(dirname "$0")/../.." && pwd)"
SIDEEYE="$HERE/zig-out/bin/sideeye"
SHIM="$HERE/zig-out/lib/libsideeye_shim.dylib"
WORK="$(mktemp -d "$HOME/fsusage-acceptance-XXXXXX")"
CC=/usr/bin/cc

fail() { echo "FAIL: $*"; exit 1; }

# Build here, every time. Two end-to-end runs measured a binary from before the fixes
# they were meant to exercise: `zig build test` runs the tests and installs nothing,
# so `zig-out/bin/sideeye` sat at 09:51 while the source moved to 10:10, and the same
# failure was read twice as fresh evidence. An existence check on the binary cannot
# see that; building is the only thing that makes "the binary under test" and "the
# source under test" the same object.
( cd "$HERE" && zig build ) || fail "zig build failed; nothing was measured"
[ -x "$SIDEEYE" ] || fail "zig build produced no binary at $SIDEEYE"
[ -f "$SHIM" ] || fail "zig build produced no shim at $SHIM"
newest_src=$(ls -t "$HERE"/src/*.zig | head -1)
[ "$SIDEEYE" -nt "$newest_src" ] || fail "binary is older than $newest_src after a build; refusing to measure a stale artifact"

sudo -v || fail "sudo unavailable; nothing was measured"

# --- toys -------------------------------------------------------------------------
cat > "$WORK/libc_toy.c" <<'EOF'
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(void) {
    const char *d = getenv("PROBE_STATE"); if (!d) d = "./state";
    char p[1024]; snprintf(p, sizeof(p), "%s/keep", d);
    int fd = open(p, O_CREAT | O_WRONLY | O_TRUNC, 0600);
    if (fd < 0) { perror("open"); return 1; }
    if (write(fd, "ok\n", 3) != 3) { perror("write"); return 1; }
    if (close(fd) != 0) { perror("close"); return 1; }
    return 0;
}
EOF
cat > "$WORK/mkstemp_toy.c" <<'EOF'
/* The creation happens inside libc, past the PLT, so the shim never sees it —
 * measured on macOS, spike/fsusage/RESULTS-mkstemp.md. The write IS visible, so the
 * two accounts differ by exactly the creation. */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(void) {
    const char *d = getenv("PROBE_STATE"); if (!d) d = "./state";
    char t[1024]; snprintf(t, sizeof(t), "%s/tmp-XXXXXX", d);
    int fd = mkstemp(t);
    if (fd < 0) { perror("mkstemp"); return 1; }
    if (write(fd, "ok\n", 3) != 3) { perror("write"); return 1; }
    if (close(fd) != 0) { perror("close"); return 1; }
    return 0;
}
EOF
cat > "$WORK/rawchild_toy.c" <<'EOF'
/* #405's shape: the parent writes through libc so the recording is not empty, then
 * forks raw and the child writes through raw syscalls. Neither the shim nor a
 * pid-filtered fs_usage sees the child. `syscall(SYS_fork)` returns the pid in both
 * processes on arm64 and libc caches getpid(), so the discrimination has to go
 * through syscall(SYS_getpid) — measured. */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>
int main(void) {
    const char *d = getenv("PROBE_STATE"); if (!d) d = "./state";
    char pp[1024], cp[1024];
    snprintf(pp, sizeof(pp), "%s/from-parent", d);
    snprintf(cp, sizeof(cp), "%s/from-raw-child", d);
    int fd = open(pp, O_CREAT | O_WRONLY | O_TRUNC, 0600);
    if (fd < 0) { perror("open"); return 1; }
    if (write(fd, "p\n", 2) != 2) { perror("write"); return 1; }
    close(fd);
    long before = syscall(SYS_getpid);
    long r = syscall(SYS_fork);
    if (r < 0) { fprintf(stderr, "raw fork failed\n"); return 3; }
    if (syscall(SYS_getpid) != before) {
        long c = syscall(SYS_open, cp, O_CREAT | O_WRONLY | O_TRUNC, 0600);
        if (c >= 0) { syscall(SYS_write, c, "c\n", 2); syscall(SYS_close, c); }
        syscall(SYS_exit, 0);
        _exit(0);
    }
    int st; waitpid((pid_t)r, &st, 0);
    return 0;
}
EOF
for t in libc_toy mkstemp_toy rawchild_toy; do
    "$CC" -O0 -o "$WORK/$t" "$WORK/$t.c" 2>/dev/null || fail "could not build $t"
done

# kdebug is a single system-wide resource: an fs_usage left holding it makes every later
# start fail with `ktrace_start: Resource busy`, and the failure surfaces downstream as
# an unrelated refusal or an empty capture. One measured run of this script read an
# empty Probe 0 capture as "a shell child is invisible" when the truth was that the
# probe's fs_usage had never started — an orphan from a previous binary still held the
# resource until its -t bound. Called before EVERY start, probe included. Waits for the
# resource itself, not for a duration.
ensure_no_fs_usage() {
    pgrep -x fs_usage >/dev/null 2>&1 || return 0
    sudo -n /usr/bin/pkill -INT -x fs_usage 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x fs_usage >/dev/null 2>&1 || return 0
        sleep 1
    done
    sudo -n /usr/bin/pkill -KILL -x fs_usage 2>/dev/null; sleep 2
    pgrep -x fs_usage >/dev/null 2>&1 && fail "an fs_usage survived and still holds kdebug; nothing after this could start"
    return 0
}

run() {  # run <name> <toy> <extra-args...>
    local name="$1" toy="$2"; shift 2
    ensure_no_fs_usage
    local st="$WORK/state-$name"; mkdir -p "$st"
    PROBE_STATE="$st" "$SIDEEYE" explore --state "$st" --operation "$WORK/$toy" \
        --shim "$SHIM" --work "$WORK/w-$name" --json "$WORK/$name.json" "$@" \
        > "$WORK/$name.txt" 2>&1
    echo $?
}
field() { python3 -c "
import json,sys
try: print(json.load(open(sys.argv[1])).get(sys.argv[2]))
except Exception: print('(no json)')" "$WORK/$1.json" "$2"; }

echo "=================================================================="
echo "Probe 0 — does the launch flag actually lift fs_usage's default exclusions?"
echo "  The man page names Terminal, sshd, sh, csh, tcsh and zsh as excluded by"
echo "  default, and says -e excludes fs_usage itself (plus any list given). It does"
echo "  NOT say -e lifts the defaults. Measured here rather than assumed, because a"
echo "  child that execs /bin/sh would otherwise be missing from the capture."
PROBE_CAP="$WORK/probe0.capture"
ensure_no_fs_usage
sudo -n /usr/bin/fs_usage -w -e -t 8 -f filesys > "$PROBE_CAP" 2>/dev/null &
PROBE_PID=$!
sleep 2
/bin/sh -c "cat /etc/hostconfig > /dev/null 2>&1; : > $WORK/probe0-marker" 2>/dev/null
sleep 1
ensure_no_fs_usage
[ -s "$PROBE_CAP" ] || fail "Probe 0's capture is empty: fs_usage did not run, so nothing here is a measurement"
SH_LINES=$(grep -cE '[[:space:]]sh\.[0-9]+$' "$PROBE_CAP" 2>/dev/null); SH_LINES=${SH_LINES:-0}
MARKER_LINES=$(grep -c "probe0-marker" "$PROBE_CAP" 2>/dev/null); MARKER_LINES=${MARKER_LINES:-0}
echo "  lines attributed to a process named sh: $SH_LINES"
echo "  lines naming the marker the shell wrote: $MARKER_LINES"
if [ "$SH_LINES" -gt 0 ]; then
    echo "  RESULT: -e lifts the defaults (sh is visible)"
elif [ "$MARKER_LINES" -gt 0 ]; then
    echo "  RESULT: the shell's own lines are excluded, but its writes are visible under"
    echo "          another name — scope-by-path still sees the mutation"
else
    echo "  RESULT: NEITHER — a shell child is invisible to this capture. The blind spot"
    echo "          #405 describes survives for targets that exec a shell, and the docs"
    echo "          must say so."
fi

echo "=================================================================="
echo "Check 1 — a verified PASS stands on macOS"
echo "  predicate: exit 0 AND oracle_verified true, with --oracle-fs-usage"
echo "  control:   the same toy without the flag refuses (completeness_not_verified)"
rc_ctl=$(run c1ctl libc_toy)
rc=$(run c1 libc_toy --oracle-fs-usage)
echo "  control exit=$rc_ctl reason=$(field c1ctl unknown_reason)"
echo "  flagged exit=$rc oracle_verified=$(field c1 oracle_verified) verdict=$(field c1 verdict)"
[ "$rc_ctl" = "2" ] || fail "control did not refuse; the check discriminates nothing"
[ "$rc" = "0" ] || { sed -n '1,12p' "$WORK/c1.txt"; fail "check 1: expected exit 0"; }
[ "$(field c1 oracle_verified)" = "True" ] || fail "check 1: oracle_verified is not true"
echo "  PASS"

echo "=================================================================="
echo "Check 2 — the oracle catches what the shim missed, in this run"
echo "  predicate: exit 2 AND oracle_verified false AND a divergence reason"
rc2=$(run c2 mkstemp_toy --oracle-fs-usage)
echo "  exit=$rc2 reason=$(field c2 unknown_reason) oracle_verified=$(field c2 oracle_verified)"
[ "$rc2" = "2" ] || { sed -n '1,12p' "$WORK/c2.txt"; fail "check 2: expected exit 2"; }
case "$(field c2 unknown_reason)" in
    oracle_missed_operation|oracle_saw_phantom) ;;
    *) fail "check 2: expected a divergence, got $(field c2 unknown_reason)" ;;
esac
echo "  PASS"

echo "=================================================================="
echo "Check 3 — a second process nobody saw stops the run"
echo "  predicate: exit 2 with the flag"
echo "  control:   WITHOUT the flag the same toy reaches PASS exit 0 saying"
echo "             'single process' — the shipped defect (#405), so this check"
echo "             is the only thing catching it"
rc3ctl=$(run c3ctl rawchild_toy --allow-unverified)
echo "  control exit=$rc3ctl verdict=$(field c3ctl verdict) processes=$(field c3ctl processes)"
rc3=$(run c3 rawchild_toy --oracle-fs-usage)
echo "  flagged exit=$rc3 reason=$(field c3 unknown_reason)"
[ "$rc3ctl" = "0" ] || echo "  NOTE: control did not reproduce #405 here (exit $rc3ctl); check 3 still stands on its own"
[ "$rc3" = "2" ] || { sed -n '1,12p' "$WORK/c3.txt"; fail "check 3: expected exit 2"; }
echo "  PASS"

echo "=================================================================="
echo "all three checks passed"
echo "artifacts: $WORK"
