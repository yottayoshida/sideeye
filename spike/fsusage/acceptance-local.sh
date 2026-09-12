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
WORK="$(mktemp -d "$HOME/fsusage-acceptance-XXXXXX")"
OUT="$WORK/out"
SIDEEYE="$OUT/bin/sideeye"
SHIM="$OUT/lib/libsideeye_shim.dylib"
CC=/usr/bin/cc

fail() { echo "FAIL: $*"; exit 1; }

# Build here, every time, into a prefix that did not exist a moment ago. Two end-to-end
# runs measured a binary from before the fixes they were meant to exercise: `zig build
# test` runs the tests and installs nothing, so `zig-out/bin/sideeye` sat at 09:51 while
# the source moved to 10:10, and the same failure was read twice as fresh evidence.
# An existence check on `zig-out` cannot see that. Neither can an mtime comparison
# against `src/`: Zig's install step copies the cached artifact and gives the copy the
# artifact's mtime (`std.Io.Dir.updateFile`), so under a warm cache with unchanged
# sources the installed binary is legitimately older than a fresh checkout — which is
# what CI measured on the first PR after #406 that did not touch `src/`. An empty
# prefix is the check that survives the cache: whatever is in it was installed by
# this invocation from this tree, or it is not there.
( cd "$HERE" && zig build --prefix "$OUT" ) || fail "zig build failed; nothing was measured"
[ -x "$SIDEEYE" ] || fail "zig build installed no binary at $SIDEEYE"
[ -f "$SHIM" ] || fail "zig build installed no shim at $SHIM"

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
cat > "$WORK/dprintf_toy.c" <<'EOF'
/* The WRITE happens inside libc, past the PLT, so the shim never sees it. The open IS
 * visible, because the program issues it, so the two accounts differ by exactly the
 * write — which is what makes this a divergence the oracle catches and not a run with
 * nothing recorded at all.
 *
 * This used to be a `mkstemp` toy, and the creation was the invisible half. #39 closed
 * that: `mkstemp` is reimplemented in the shim as of contract v13, so this check's
 * negative control had to move to a member of the same class that is STILL a wall.
 * `dprintf` is one by decision — glibc splits a large write at 8192 bytes, so a
 * replacement writing once would delete a crash point the real program has — and
 * `spike/libc-internal/RESULTS.md` carries the measurement. If a later change takes
 * `dprintf` too, this control has to move again rather than be deleted: a check that
 * pins "the oracle catches what the shim missed" needs something the shim misses. */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(void) {
    const char *d = getenv("PROBE_STATE"); if (!d) d = "./state";
    char t[1024]; snprintf(t, sizeof(t), "%s/log.txt", d);
    int fd = open(t, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) { perror("open"); return 1; }
    if (dprintf(fd, "ok %d\n", 1) < 0) { perror("dprintf"); return 1; }
    if (close(fd) != 0) { perror("close"); return 1; }
    return 0;
}
EOF
# The raw-child fixture is the TRACKED one, not a copy. It used to be a heredoc here,
# and a third copy lived in spike/fsusage/phase0/ — three files, one claim, hand-synced,
# and they had already drifted (`PROBE_STATE` only versus `TOY_STATE` then `PROBE_STATE`;
# a raw-fork fallback present in one and absent in another). Check 3 below and
# `spike/acceptance.sh` check 2af assert the same thing about the same shape, so they had
# better be asserting it about the same program. The tracked fixture reads both variable
# spellings, which is why this can hand it `PROBE_STATE` unchanged.
cp "$HERE/spike/toys/toy_rawchild.c" "$WORK/rawchild_toy.c" ||
    fail "the tracked #405 fixture is missing: spike/toys/toy_rawchild.c"
for t in libc_toy dprintf_toy rawchild_toy; do
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
# The account moves with the witness (#405). Same toy, same binary, and the two runs
# differ in the flag *and* in whether a witness read — so this pair does NOT discriminate
# an implementation that rewords by reading the flag: it would emit these same two
# strings. Review named that, and the discrimination lives on the Linux side instead,
# where `spike/acceptance.sh` checks 2k and 2ae drive a witness that read an empty
# capture and one that reported a boundary — both with the flag on, both refusing the
# single-process wording. What this pair pins is narrower and still worth pinning: the
# two states macOS reaches without extra apparatus say different, specific things.
ctl_p=$(field c1ctl processes)
flg_p=$(field c1 processes)
[ "$ctl_p" != "$flg_p" ] || fail "check 1: the processes account did not move with the witness: $ctl_p"
case "$ctl_p" in *"not established"*) ;; *) fail "check 1: the unwitnessed run did not say the question was unestablished: $ctl_p" ;; esac
case "$flg_p" in *"fs_usage capture"*) ;; *) fail "check 1: the witnessed run does not name what fs_usage covered: $flg_p" ;; esac
# fs_usage drops whole processes by name, so its silence is never the single-process
# assertion — ADR 0031 §2a is the ruling and this is the leg that holds the code to it.
case "$flg_p" in *"single process"*) fail "check 1: fs_usage's silence was published as an assertion: $flg_p" ;; esac
case "$ctl_p" in *"single process"*) fail "check 1: an unwitnessed run asserted a single process: $ctl_p" ;; esac
echo "  processes without a witness: $ctl_p"
echo "  processes under fs_usage:    $flg_p"
echo "  PASS"

echo "=================================================================="
echo "Check 2 — the oracle catches what the shim missed, in this run"
echo "  predicate: exit 2 AND oracle_verified false AND a divergence reason"
rc2=$(run c2 dprintf_toy --oracle-fs-usage)
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
echo "  control:   WITHOUT the flag the same toy now refuses too, by path rather than by"
echo "             witness (state_changed_unaccounted, ADR 0032). It reached PASS exit 0"
echo "             with the child's file in the judged directory until 2026-08-30 — that"
echo "             was #405's detection half, and it is closed"
rc3ctl=$(run c3ctl rawchild_toy --allow-unverified)
echo "  control exit=$rc3ctl verdict=$(field c3ctl verdict) reason=$(field c3ctl unknown_reason)"
rc3=$(run c3 rawchild_toy --oracle-fs-usage)
echo "  flagged exit=$rc3 reason=$(field c3 unknown_reason)"
# The control was a soft NOTE while the gap was open, because a leg cannot assert a
# defect it is documenting. Now that the gap is closed it is a hard assert: the two
# paths refuse for DIFFERENT reasons, and that difference is the point — with the flag
# a witness sees the second process, without it only the unexplained path is visible.
[ "$rc3ctl" = "2" ] || { sed -n '1,12p' "$WORK/c3ctl.txt"; fail "check 3 control: expected exit 2 (state_changed_unaccounted); a PASS here is #405's detection half reopening"; }
[ "$(field c3ctl unknown_reason)" = "state_changed_unaccounted" ] || fail "check 3 control: expected state_changed_unaccounted, got $(field c3ctl unknown_reason)"
case "$(field c3ctl message)" in *from-raw-child*) ;; *) fail "check 3 control: the refusal does not name the unexplained path: $(field c3ctl message)" ;; esac
# The report half (#409) still holds on the same run: the account does not answer a
# question nothing looked at.
ctl3_p=$(field c3ctl processes)
case "$ctl3_p" in *"single process"*) fail "check 3 control: an unwitnessed run asserted a single process: $ctl3_p" ;; esac
case "$ctl3_p" in *"raw syscall"*) ;; *) fail "check 3 control: the account does not say what the shim cannot see: $ctl3_p" ;; esac
[ "$rc3" = "2" ] || { sed -n '1,12p' "$WORK/c3.txt"; fail "check 3: expected exit 2"; }
[ "$(field c3 unknown_reason)" = "child_touched_state_dir" ] || fail "check 3: expected child_touched_state_dir, got $(field c3 unknown_reason) — a refusal for another reason would leave this check green over a parser failure"
echo "  PASS"

echo "=================================================================="
echo "Check 4 — a boundary the shim saw is not tolerated under fs_usage"
echo "  predicate: exit 2 AND boundary_without_oracle. fs_usage excludes processes by"
echo "             name (the shells), so no child can be accounted for"
cat > "$WORK/libcchild_toy.c" <<'EOF'
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>
int main(void) {
    const char *d = getenv("PROBE_STATE"); if (!d) d = "./state";
    char pp[1024]; snprintf(pp, sizeof(pp), "%s/from-parent", d);
    int fd = open(pp, O_CREAT | O_WRONLY | O_TRUNC, 0600);
    if (fd < 0) return 1; write(fd, "p\n", 2); close(fd);
    pid_t c = fork();
    if (c == 0) _exit(0);
    int st; waitpid(c, &st, 0);
    return 0;
}
EOF
"$CC" -O0 -o "$WORK/libcchild_toy" "$WORK/libcchild_toy.c" 2>/dev/null || fail "could not build libcchild_toy"
rc4=$(run c4 libcchild_toy --oracle-fs-usage)
echo "  exit=$rc4 reason=$(field c4 unknown_reason)"
[ "$rc4" = "2" ] || { sed -n '1,12p' "$WORK/c4.txt"; fail "check 4: expected exit 2"; }
[ "$(field c4 unknown_reason)" = "boundary_without_oracle" ] || fail "check 4: expected boundary_without_oracle, got $(field c4 unknown_reason)"
echo "  PASS"

echo "=================================================================="
echo "Check 5 — a chdir followed by a raw relative openat into the state refuses"
echo "  predicate: exit 2 (the reader does not follow cwd; a relative operand after"
echo "             chdir is unplaceable). Review's false-PASS construction, run for real"
cat > "$WORK/chdir_toy.c" <<'EOF'
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>
int main(void) {
    const char *d = getenv("PROBE_STATE"); if (!d) d = "./state";
    char pp[1024]; snprintf(pp, sizeof(pp), "%s/from-parent", d);
    int fd = open(pp, O_CREAT | O_WRONLY | O_TRUNC, 0600);   /* recorded: keeps the zero-op guard quiet */
    if (fd < 0) return 1; write(fd, "p\n", 2); close(fd);
    /* move to the state's parent, then create INSIDE the state through a relative raw openat */
    char parent[1024]; snprintf(parent, sizeof(parent), "%s", d);
    char *slash = strrchr(parent, '/'); if (!slash) return 3; *slash = 0;
    const char *base = slash + 1;
    if (chdir(parent) != 0) return 4;
    char rel[1024]; snprintf(rel, sizeof(rel), "%s/missed", base);
    long r = syscall(SYS_openat, -2, rel, O_CREAT | O_WRONLY | O_TRUNC, 0600);
    if (r >= 0) { syscall(SYS_write, r, "m\n", 2); syscall(SYS_close, r); }
    return 0;
}
EOF
"$CC" -O0 -o "$WORK/chdir_toy" "$WORK/chdir_toy.c" 2>/dev/null || fail "could not build chdir_toy"
rc5=$(run c5 chdir_toy --oracle-fs-usage)
echo "  exit=$rc5 reason=$(field c5 unknown_reason)"
[ "$rc5" = "2" ] || { sed -n '1,12p' "$WORK/c5.txt"; fail "check 5: expected exit 2 — a PASS here is the false PASS review constructed"; }
echo "  PASS"

echo "=================================================================="
echo "Check 6 — a worker thread's writes are the subject's (#544)"
echo "  predicate: oracle_verified true AND the account says one thread of the subject"
echo "             wrote, on a target whose state-directory writes ALL come from a"
echo "             thread other than the one this oracle identifies the subject by"
echo "             (whoever opened the trace write-capably)"
echo "  verdict:   asked for, not required — #569 takes it from this shape at a measured"
echo "             rate. Any refusal other than kill_did_not_land fails the check"
echo "  control:   a second writing thread of the same process still refuses"
echo "             multiple_threads_detected — the v16 rule, decided from the trace"
cat > "$WORK/worker_toy.c" <<'EOF'
/* Every state-directory write happens on a worker thread; the main thread only starts and
 * joins it. The main thread is the one that opened the trace, which is how src/fsusage.zig
 * identifies the subject — so this toy's only writes are the ones that reader attributed
 * to another party before #544, and the run refused. */
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
static int writefile(const char *d, const char *name) {
    char p[1024]; snprintf(p, sizeof(p), "%s/%s", d, name);
    int fd = open(p, O_CREAT | O_WRONLY | O_TRUNC, 0600);
    if (fd < 0) { perror("open"); return 1; }
    if (write(fd, "ok\n", 3) != 3) { perror("write"); return 1; }
    if (close(fd) != 0) { perror("close"); return 1; }
    return 0;
}
static void *worker(void *arg) { return writefile((const char *)arg, "keep") ? (void *)1 : NULL; }
int main(void) {
    const char *d = getenv("PROBE_STATE"); if (!d) d = "./state";
    pthread_t t;
    if (pthread_create(&t, NULL, worker, (void *)d) != 0) return 1;
    void *rv; if (pthread_join(t, &rv) != 0) return 1;
    return rv == NULL ? 0 : 1;
}
EOF
cat > "$WORK/twowriters_toy.c" <<'EOF'
/* The control. Identical but for one line: the main thread writes as well, so the process
 * has two writing threads and the v16 rule refuses.
 *
 * What this does NOT do is discriminate #544: the refusal comes from `second_writer_thread`
 * in the shim's trace, several statements before the oracle block that change lives in, so
 * an implementation calling every thread the subject reaches the same exit for the same
 * reason. Check 7 is the leg that separates those, and the `named`/`unnamed` pair in
 * src/fsusage.zig is the unit-level one. This control is here because a second writing
 * thread must keep refusing, which is worth pinning on its own. */
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
static int writefile(const char *d, const char *name) {
    char p[1024]; snprintf(p, sizeof(p), "%s/%s", d, name);
    int fd = open(p, O_CREAT | O_WRONLY | O_TRUNC, 0600);
    if (fd < 0) { perror("open"); return 1; }
    if (write(fd, "ok\n", 3) != 3) { perror("write"); return 1; }
    if (close(fd) != 0) { perror("close"); return 1; }
    return 0;
}
static void *worker(void *arg) { return writefile((const char *)arg, "keep") ? (void *)1 : NULL; }
int main(void) {
    const char *d = getenv("PROBE_STATE"); if (!d) d = "./state";
    pthread_t t;
    if (pthread_create(&t, NULL, worker, (void *)d) != 0) return 1;
    if (writefile(d, "also-main")) return 1;
    void *rv; if (pthread_join(t, &rv) != 0) return 1;
    return rv == NULL ? 0 : 1;
}
EOF
for t in worker_toy twowriters_toy; do
    "$CC" -O0 -pthread -o "$WORK/$t" "$WORK/$t.c" 2>/dev/null || fail "could not build $t"
done
rc6=$(run c6 worker_toy --oracle-fs-usage)
c6_ver=$(field c6 oracle_verified)
c6_reason=$(field c6 unknown_reason)
c6_proc=$(field c6 processes)
echo "  exit=$rc6 oracle_verified=$c6_ver verdict=$(field c6 verdict) reason=$c6_reason"
# The two assertions that are about THIS change, and they are unconditional. A build that
# did not read the worker's writes as the subject's cannot reach either: the oracle would
# have a writer the shim's account does not, so `oracle_verified` would be false and the
# run would refuse child_touched_state_dir or oracle_saw_nothing instead.
[ "$c6_ver" = "True" ] || { sed -n '1,12p' "$WORK/c6.txt"; fail "check 6: oracle_verified is not true — the worker's writes were not read as the subject's"; }
case "$c6_proc" in *"1 thread id(s) of the subject's own process wrote"*) ;; *) fail "check 6: the account does not say one thread of the subject wrote: $c6_proc" ;; esac
# The verdict, which this leg asks for and does not require, because #569 can take it away
# from a target of exactly this shape. Measured before this exception was written: the same
# operations from a worker thread refuse kill_did_not_land 9 times in 12 at nine crash
# points and 1 in 12 at two, while the identical program without the thread refuses 0 in 12
# at either count. It is older than this change (2 in 9 on b175d4b) and independent of this
# oracle (the measurements used none). Tolerated BY NAME: any other refusal fails, so this
# does not become a leg that passes on anything.
if [ "$rc6" = "0" ]; then
    echo "  the run reached a verdict"
elif [ "$rc6" = "2" ] && [ "$c6_reason" = "kill_did_not_land" ]; then
    echo "  NOTE: verified, then refused kill_did_not_land (#569) — the attribution this leg tests held; the kill did not land"
else
    sed -n '1,12p' "$WORK/c6.txt"
    fail "check 6: exit $rc6 reason=$c6_reason — expected a verdict, or kill_did_not_land (#569) and nothing else"
fi
rc6ctl=$(run c6ctl twowriters_toy --oracle-fs-usage)
echo "  control exit=$rc6ctl reason=$(field c6ctl unknown_reason)"
[ "$rc6ctl" = "2" ] || { sed -n '1,12p' "$WORK/c6ctl.txt"; fail "check 6 control: expected exit 2 — two writing threads must still refuse"; }
[ "$(field c6ctl unknown_reason)" = "multiple_threads_detected" ] || fail "check 6 control: expected multiple_threads_detected, got $(field c6ctl unknown_reason)"
echo "  PASS"

echo "=================================================================="
echo "Check 7 — a thread the shim did not record is refused as a thread, not as a child"
echo "  predicate: exit 2 AND multiple_threads_detected, on a target whose worker writes"
echo "             through raw syscalls. The shim records the thread being created and"
echo "             nothing it wrote, so the worker is NOT on the list handed to the"
echo "             reader; the oracle sees a tid nothing attributes (#544, ADR 0060)"
echo "  why it is here: check 6's own control passes without this change — two writing"
echo "             threads are caught by the v16 rule from the trace, before the flag is"
echo "             consulted. THIS is the leg that fails if the refusal goes back to"
echo "             calling a thread another process (child_touched_state_dir)"
cat > "$WORK/rawworker_toy.c" <<'EOF'
/* The main thread writes through libc, so the run has a recorded account. The worker
 * writes through raw syscalls, so the shim records nothing of its operations — it is not
 * on the list handed to src/fsusage.zig, and the oracle sees a tid nothing attributes.
 * The shim DID record the thread being created and no process boundary, which is the
 * evidence the refusal is chosen on. Catching what the shim missed is what this oracle is
 * for, so this shape is the main case rather than a corner. */
#define _GNU_SOURCE
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>
static void *worker(void *arg) {
    const char *d = (const char *)arg;
    char p[1024]; snprintf(p, sizeof(p), "%s/raw", d);
    long fd = syscall(SYS_openat, -2 /* AT_FDCWD */, p, O_CREAT | O_WRONLY | O_TRUNC, 0600);
    if (fd < 0) return (void *)1;
    syscall(SYS_write, (int)fd, "r\n", 2);
    syscall(SYS_close, (int)fd);
    return NULL;
}
int main(void) {
    const char *d = getenv("PROBE_STATE"); if (!d) d = "./state";
    char p[1024]; snprintf(p, sizeof(p), "%s/keep", d);
    int fd = open(p, O_CREAT | O_WRONLY | O_TRUNC, 0600);
    if (fd < 0) { perror("open"); return 1; }
    if (write(fd, "ok\n", 3) != 3) { perror("write"); return 1; }
    if (close(fd) != 0) { perror("close"); return 1; }
    pthread_t t;
    if (pthread_create(&t, NULL, worker, (void *)d) != 0) return 1;
    void *rv; if (pthread_join(t, &rv) != 0) return 1;
    return rv == NULL ? 0 : 1;
}
EOF
"$CC" -O0 -pthread -o "$WORK/rawworker_toy" "$WORK/rawworker_toy.c" 2>/dev/null || fail "could not build rawworker_toy"
rc7=$(run c7 rawworker_toy --oracle-fs-usage)
# Read once. Each `field` call starts a python3, and this check asks for the same three
# values a dozen times between here and its PASS.
c7_reason=$(field c7 unknown_reason)
c7_msg=$(field c7 message)
c7_proc=$(field c7 processes)
echo "  exit=$rc7 reason=$c7_reason"
[ "$rc7" = "2" ] || { sed -n '1,12p' "$WORK/c7.txt"; fail "check 7: expected exit 2 — a writer the shim never recorded must refuse"; }
[ "$c7_reason" = "multiple_threads_detected" ] || fail "check 7: expected multiple_threads_detected, got $c7_reason — child_touched_state_dir here is the refusal ADR 0055 declined to publish, calling a thread another process"
# The message must not assert the half this witness cannot see. fs_usage names a thread and
# knows no process for it, so "process N" is a claim the run did not establish.
case "$c7_msg" in *"mutated the judged directory"*) ;; *) fail "check 7: the refusal does not name the unattributed writer: $c7_msg" ;; esac
# Matched on a phrase unique to each sentence rather than on word order. The two refusals
# share "mutated the judged directory in the oracle's account and recorded nothing of its
# own", so a glob like *"process "*"mutated"* only works while "process" happens to come
# first — it would pass silently the day anything is prepended or the sentence is
# rearranged.
case "$c7_msg" in *"calling it a process would assert"*) ;; *) fail "check 7: the refusal does not carry the thread-naming witness's limit: $c7_msg" ;; esac
case "$c7_msg" in *"A child that never loaded the shim"*) fail "check 7: the refusal is the one that asserts a process: $c7_msg" ;; esac
# And the account beside it must say the same thing. The refusal message and the
# `processes` field are rendered by different code, so one can be corrected while the
# other keeps asserting that the writer was a process — which would be a report
# contradicting itself in two of its own fields (#544).
case "$c7_proc" in *"knows no process for it"*) ;; *) fail "check 7: the processes account does not carry this witness's limit: $c7_proc" ;; esac
case "$c7_proc" in *"a process other than the subject operated"*) fail "check 7: the account calls an unattributable id a process: $c7_proc" ;; esac
echo "  PASS"

echo "=================================================================="
echo "all seven checks passed"
echo "artifacts: $WORK"
