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
# Not the build's default flags when CI names the job's build: there the pair under test is the
# one the release ships, and a build here that lost the flags would measure Debug, green.
[ "${GITHUB_ACTIONS:-}" != true ] || [ -n "${SIDEEYE_BUILD_SAME_AS:-}" ] || fail "in CI, SIDEEYE_BUILD_SAME_AS must name the job's build; nothing was measured"
# shellcheck disable=SC2086 # a flag list, split on purpose
( cd "$HERE" && zig build ${SIDEEYE_BUILD_FLAGS:-} --prefix "$OUT" ) || fail "zig build failed; nothing was measured"
[ -x "$SIDEEYE" ] || fail "zig build installed no binary at $SIDEEYE"
[ -f "$SHIM" ] || fail "zig build installed no shim at $SHIM"
if [ -n "${SIDEEYE_BUILD_SAME_AS:-}" ]; then
    cmp -s "$SIDEEYE" "$SIDEEYE_BUILD_SAME_AS/bin/sideeye" && cmp -s "$SHIM" "$SIDEEYE_BUILD_SAME_AS/lib/$(basename "$SHIM")" \
        || fail "the pair built here is not the one at $SIDEEYE_BUILD_SAME_AS (were SIDEEYE_BUILD_FLAGS passed?); nothing was measured"
fi

sudo -v || fail "sudo unavailable; nothing was measured"

# --- toys -------------------------------------------------------------------------
cat > "$WORK/libc_toy.c" <<'EOF'
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/xattr.h>
#include <unistd.h>
int main(void) {
    const char *d = getenv("PROBE_STATE"); if (!d) d = "./state";
    const char *log = getenv("PROBE_LOG");
    if (log) {
        int lfd = open(log, O_CREAT | O_WRONLY | O_APPEND, 0600);
        if (lfd < 0 || write(lfd, "started\n", 8) != 8 || close(lfd) != 0) { perror("log"); return 1; }
    }
    char p[1024]; snprintf(p, sizeof(p), "%s/keep", d);
    int fd = open(p, O_CREAT | O_WRONLY, 0600); /* in place, over the bytes `keep` holds (ADR 0091) */
    if (fd < 0) { perror("open"); return 1; }
    if (write(fd, "ok\n", 3) != 3) { perror("write"); return 1; }
    if (getenv("PROBE_XATTR")) {
        if (setxattr(p, "org.sideeye.probe", "1", 1, 0, 0) != 0) { perror("setxattr"); return 1; }
        if (fsetxattr(fd, "org.sideeye.probe", "2", 1, 0, 0) != 0) { perror("fsetxattr"); return 1; }
    }
    if (close(fd) != 0) { perror("close"); return 1; }
    const char *linger = getenv("PROBE_LINGER_S"); /* in this image: an exec'd sleep is a boundary fs_usage refuses */
    if (linger) sleep((unsigned)atoi(linger));
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
# Checks 1 and 6 need a verdict, and since ADR 0091 a run whose operation only creates files,
# with no checker, is refused `nothing_could_fail` — both toys were that until then. `keep` is
# put in the state before the run and the toys rewrite its three bytes in place (no O_TRUNC):
# the same crash points, a path the atomicity invariant judges, and no world that can hold
# anything else. The other checks assert refusals that come first and are left as they were.
seed_keep() { mkdir -p "$WORK/state-$1" && printf 'ok\n' > "$WORK/state-$1/keep"; }
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
seed_keep c1ctl
rc_ctl=$(run c1ctl libc_toy)
seed_keep c1
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
c2_reason=$(field c2 unknown_reason)
case "$c2_reason" in
    oracle_missed_operation)
        c2_next=$(field c2 next_step)
        case "$c2_next" in *"--observe syscalls"*) ;; *) fail "check 2: the step does not name --observe syscalls: $c2_next" ;; esac
        case "$c2_next" in *Linux*) ;; *) fail "check 2: the step does not name a Linux run: $c2_next" ;; esac
        case "$c2_next" in *"docs/ci-quickstart.md"*) ;; *) fail "check 2: the step does not link the CI quickstart: $c2_next" ;; esac ;;
    oracle_saw_phantom) ;;
    *) fail "check 2: expected a divergence, got $c2_reason" ;;
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
case "$(field c3ctl next_step)" in *"--observe syscalls"*Linux*|*Linux*"--observe syscalls"*) ;; *) fail "check 3 control: the step does not name --observe syscalls on a Linux run: $(field c3ctl next_step)" ;; esac
# The report half (#409) still holds on the same run: the account does not answer a
# question nothing looked at.
ctl3_p=$(field c3ctl processes)
case "$ctl3_p" in *"single process"*) fail "check 3 control: an unwitnessed run asserted a single process: $ctl3_p" ;; esac
case "$ctl3_p" in *"raw syscall"*) ;; *) fail "check 3 control: the account does not say what the shim cannot see: $ctl3_p" ;; esac
[ "$rc3" = "2" ] || { sed -n '1,12p' "$WORK/c3.txt"; fail "check 3: expected exit 2"; }
[ "$(field c3 unknown_reason)" = "child_touched_state_dir" ] || fail "check 3: expected child_touched_state_dir, got $(field c3 unknown_reason) — a refusal for another reason would leave this check green over a parser failure"
# Shown, not asserted: which wall this raw-fork child meets on a runner has not been read yet.
echo "  next_step opens: $(field c3 next_step | cut -c1-60)"
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
c4_next=$(field c4 next_step)
case "$c4_next" in *"--oracle <strace> on Linux"*) ;; *) fail "check 4: the step does not name strace on Linux: $c4_next" ;; esac
case "$c4_next" in *"docs/ci-quickstart.md"*) ;; *) fail "check 4: the step does not link the CI quickstart: $c4_next" ;; esac
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
echo "  verdict:   required, exit 0. Until #569 this shape refused kill_did_not_land at a"
echo "             measured rate and the leg tolerated that one reason by name"
echo "  control:   a second writing thread of the same process still refuses"
echo "             multiple_threads_detected — the main thread writes after creating the"
echo "             worker and before joining it, so no creation or join the shim recorded"
echo "             orders the two writes (v18, ADR 0067), decided from the trace"
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
    int fd = open(p, O_CREAT | O_WRONLY, 0600); /* in place, over the bytes `keep` holds (ADR 0091) */
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
/* The control. Identical but for one line: the main thread writes as well — after creating
 * the worker and before joining it, so nothing the shim recorded orders the two writes and
 * the thread rule refuses (v16 refused on the count; v18 refuses on the missing edge, and
 * this line's position between the create and the join is what keeps it refused).
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
seed_keep c6
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
# The verdict, required since #569. Until then this leg tolerated kill_did_not_land by name:
# the shim's group kill, fired from the worker that reached the crash point, was taken by
# another thread on macOS and the worker ran on to the `_exit` behind it. This toy's two crash
# points met that about 1 run in 12, so this assertion guards against the defect coming back
# rather than showing the fix — spike/thread-kill-lands.sh, with nine crash points and three
# shapes, is the leg that turned red without the fix.
[ "$rc6" = "0" ] || { sed -n '1,12p' "$WORK/c6.txt"; fail "check 6: exit $rc6 reason=$c6_reason — expected a verdict"; }
echo "  the run reached a verdict"
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
echo "Check 8 — a state file written through a shared mapping is refused under fs_usage (#689)"
echo "  predicate: write, protect and many exit 2 unsupported_syscall_observed, each naming how"
echo "             the mapping became writable (many: past the shim's table); read (bbolt's shape: a read-only shared map, the"
echo "             writes through pwrite) reaches a verdict"
echo "  why here:  fs_usage's reader files mmap among the read-only calls and never sees an"
echo "             mprotect, so on this platform the refusal is the shim's (contract v19, ADR"
echo "             0098). Through v18 a run storing through such a mapping passed."
cat > "$WORK/mmap_toy.c" <<'EOF'
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
/* argv[1]: write | protect | read | many. Two pages of db, stored or pwritten one byte each.
 * many: 33 read-only shared views first, past the shim's 32 slots, then an anonymous page made
 * writable. The ftruncate is a recorded mutation, so the zero-operations guard is not what
 * refuses. */
int main(int argc, char **argv) {
    const char *dir = getenv("PROBE_STATE");
    if (!dir || argc < 2) return 2;
    char p[1024];
    snprintf(p, sizeof p, "%s/db", dir);
    int fd = open(p, O_RDWR);
    if (fd < 0) return 1;
    long pg = sysconf(_SC_PAGESIZE);
    size_t len = (size_t)pg * 2;
    if (ftruncate(fd, (off_t)len) != 0) return 1;
    if (strcmp(argv[1], "many") == 0) {
        for (int i = 0; i < 33; i++)
            if (mmap(NULL, (size_t)pg, PROT_READ, MAP_SHARED, fd, 0) == MAP_FAILED) return 1;
        char *a = mmap(NULL, (size_t)pg, PROT_READ, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (a == MAP_FAILED) return 1;
        if (mprotect(a, (size_t)pg, PROT_READ | PROT_WRITE) != 0) return 1;
        a[0] = 1;
        if (pwrite(fd, "X", 1, 0) != 1) return 1;
    } else if (strcmp(argv[1], "read") == 0) {
        char *m = mmap(NULL, len, PROT_READ, MAP_SHARED, fd, 0);
        if (m == MAP_FAILED) return 1;
        char seen = m[0];
        if (munmap(m, len) != 0 || seen != 'A') return 1;
        if (pwrite(fd, "X", 1, 0) != 1 || pwrite(fd, "Y", 1, (off_t)pg) != 1) return 1;
    } else {
        int writable = strcmp(argv[1], "write") == 0;
        char *m = mmap(NULL, len, writable ? (PROT_READ | PROT_WRITE) : PROT_READ, MAP_SHARED, fd, 0);
        if (m == MAP_FAILED) return 1;
        if (!writable && mprotect(m, len, PROT_READ | PROT_WRITE) != 0) return 1;
        m[0] = 'X';
        m[pg] = 'Y';
        if (munmap(m, len) != 0) return 1;
    }
    return close(fd) == 0 ? 0 : 1;
}
EOF
cc -O0 -o "$WORK/mmap_toy" "$WORK/mmap_toy.c" || fail "check 8: the toy did not build"
PG=$(getconf PAGESIZE)
for shape in write protect many read; do
    mkdir -p "$WORK/state-c8$shape"
    head -c $((PG * 2)) /dev/zero | tr '\0' A > "$WORK/state-c8$shape/db"
    rc8=$(run "c8$shape" "mmap_toy $shape" --oracle-fs-usage)
    reason=$(field "c8$shape" unknown_reason)
    msg=$(field "c8$shape" message)
    echo "  $shape: exit=$rc8 reason=$reason"
    case $shape in
        write) want='mmap(PROT_WRITE|MAP_SHARED)' ;;
        protect) want='mprotect(PROT_WRITE) on a shared mapping of a state file' ;;
        many) want='mprotect(PROT_WRITE) after more shared mappings of state files than the shim tracks' ;;
        read) want='' ;;
    esac
    if [ -n "$want" ]; then
        [ "$rc8" = "2" ] || { sed -n '1,12p' "$WORK/c8$shape.txt"; fail "check 8 $shape: expected exit 2, got $rc8"; }
        [ "$reason" = "unsupported_syscall_observed" ] || fail "check 8 $shape: expected unsupported_syscall_observed, got $reason"
        case "$msg" in *"$want"*) ;; *) fail "check 8 $shape: the refusal does not name $want: $msg" ;; esac
    else
        # A verdict, and one the second witness checked: a refusal of every shared mapping
        # fails here, and so does a run the oracle did not verify.
        { [ "$rc8" = "0" ] || [ "$rc8" = "1" ]; } || { sed -n '1,12p' "$WORK/c8read.txt"; fail "check 8 read: expected a verdict, got exit $rc8 ($reason)"; }
        [ "$(field c8read oracle_verified)" = "True" ] || fail "check 8 read: the verdict is not oracle_verified"
    fi
done
echo "  PASS"

echo "=================================================================="
echo "Check 9 — a write through a standard descriptor is judged (#796)"
echo "  predicate: each toy reaches a verdict (exit 0 or 1) with oracle_verified true"
echo "  shapes:    print (stdout and stderr the engine handed over), dup2 (the state file"
echo "             moved onto 1 the way GNU dd moves of=, a summary on 2), outside (a file"
echo "             outside the state moved onto 1 — the control that dup2 is followed, not"
echo "             every unknown descriptor taken as the state's)"
cat > "$WORK/stdio_toy.c" <<'EOF'
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
    const char *d = getenv("PROBE_STATE"); if (!d) d = "./state";
    const char *mode = getenv("STDIO_MODE"); if (!mode) mode = "print";
    char p[1024]; snprintf(p, sizeof(p), "%s/keep", d);
    if (strcmp(mode, "outside") == 0) {
        const char *o = getenv("OUTSIDE_LOG"); if (!o) return 1;
        int lf = open(o, O_WRONLY | O_CREAT | O_APPEND, 0600); if (lf < 0) return 1;
        if (dup2(lf, 1) != 1) return 1;
        close(lf);
        if (write(1, "log\n", 4) != 4) return 1;
    }
    int fd = open(p, O_WRONLY); /* in place, as check 1's toy */
    if (fd < 0) { perror("open"); return 1; }
    if (strcmp(mode, "dup2") == 0) {
        if (dup2(fd, 1) != 1) return 1;
        close(fd);
        fd = 1;
    }
    if (write(fd, "ok\n", 3) != 3) return 1;
    if (fd != 1) close(fd);
    if (strcmp(mode, "print") == 0) { printf("done\n"); fflush(stdout); }
    fprintf(stderr, "3 bytes copied\n");
    return 0;
}
EOF
cc -O0 -o "$WORK/stdio_toy" "$WORK/stdio_toy.c" || fail "check 9: the toy did not build"
for shape in print dup2 outside; do
    seed_keep "c9$shape"
    # The outside file is named without passing through the state directory: the reader
    # places an absolute operand by its text and does not resolve `..` in it.
    rc9=$(STDIO_MODE=$shape OUTSIDE_LOG="$WORK/outside-c9.log" run "c9$shape" stdio_toy --oracle-fs-usage)
    echo "  $shape: exit=$rc9 verdict=$(field "c9$shape" verdict) oracle_verified=$(field "c9$shape" oracle_verified) reason=$(field "c9$shape" unknown_reason)"
    { [ "$rc9" = "0" ] || [ "$rc9" = "1" ]; } || { sed -n '1,12p' "$WORK/c9$shape.txt"; fail "check 9 $shape: expected a verdict, got exit $rc9"; }
    [ "$(field "c9$shape" oracle_verified)" = "True" ] || fail "check 9 $shape: the verdict is not oracle_verified"
done
# The same work directory a second time: fs_usage's stderr file is opened exclusively, so one the
# first run left behind must not stop the second.
seed_keep c9print
rc9=$(STDIO_MODE=print OUTSIDE_LOG="$WORK/outside-c9.log" run c9print stdio_toy --oracle-fs-usage)
echo "  print, same --work again: exit=$rc9 verdict=$(field c9print verdict) oracle_verified=$(field c9print oracle_verified)"
{ [ "$rc9" = "0" ] || [ "$rc9" = "1" ]; } || { sed -n '1,12p' "$WORK/c9print.txt"; fail "check 9: a second run in the same --work got exit $rc9"; }
echo "  PASS"

echo "=================================================================="
echo "Check 10 — the verdict does not depend on how --work is spelled (#795)"
echo "  predicate: check 1's toy, with --work reached through /tmp, through /var, and relative,"
echo "             is exit 0 and oracle_verified true each time, as check 1 is"
echo "  red before, measured on main at e371ffe4 for /tmp and /var: the trace path went through the link;"
echo "             the relative leg was not measured before"
c10_tmp="/tmp/sideeye-c10-$$"
c10_var="/var/tmp/sideeye-c10-$$"
[ "$(cd /tmp && pwd -P)" != /tmp ] || fail "check 10: /tmp is not a link here, so the leg measures nothing"
[ "$(cd /var && pwd -P)" != /var ] || fail "check 10: /var is not a link here, so the leg measures nothing"
for leg in tmp var rel; do
    ensure_no_fs_usage
    st="$WORK/state-c10$leg"; seed_keep "c10$leg"
    case $leg in
        tmp) w="$c10_tmp" ;;
        var) w="$c10_var" ;;
        rel) w="w-c10rel" ;;
    esac
    (cd "$WORK" && PROBE_STATE="$st" "$SIDEEYE" explore --state "$st" --operation "$WORK/libc_toy" \
        --shim "$SHIM" --work "$w" --json "$WORK/c10$leg.json" --oracle-fs-usage > "$WORK/c10$leg.txt" 2>&1)
    rc10=$?
    echo "  $leg ($w): exit=$rc10 verdict=$(field "c10$leg" verdict) oracle_verified=$(field "c10$leg" oracle_verified) reason=$(field "c10$leg" unknown_reason)"
    [ "$rc10" = "0" ] || { sed -n '1,12p' "$WORK/c10$leg.txt"; fail "check 10 $leg: expected exit 0, got $rc10"; }
    [ "$(field "c10$leg" oracle_verified)" = "True" ] || fail "check 10 $leg: the verdict is not oracle_verified"
done
rm -rf "$c10_tmp" "$c10_var"
echo "  PASS"

echo "=================================================================="
echo "Check 11 — a write outside the state through /var's link is not a hole (#795)"
echo "  predicate: check 1's toy, also appending a line to a log under \$TMPDIR as given,"
echo "             is exit 0 and oracle_verified true, as check 1 is"
[ -n "${TMPDIR:-}" ] || fail "check 11: TMPDIR is not set, so the leg measures nothing"
[ "$(cd "$TMPDIR" && pwd -P)" != "${TMPDIR%/}" ] || fail "check 11: TMPDIR is not reached through a link here, so the leg measures nothing"
c11_log="${TMPDIR%/}/sideeye-c11-$$.log"
seed_keep c11
rc11=$(PROBE_LOG="$c11_log" run c11 libc_toy --oracle-fs-usage)
echo "  exit=$rc11 verdict=$(field c11 verdict) oracle_verified=$(field c11 oracle_verified) reason=$(field c11 unknown_reason)"
[ "$rc11" = "0" ] || { sed -n '1,12p' "$WORK/c11.txt"; fail "check 11: expected exit 0, got $rc11"; }
[ "$(field c11 oracle_verified)" = "True" ] || fail "check 11: the verdict is not oracle_verified"
rm -f "$c11_log"
echo "  PASS"

echo "=================================================================="
echo "Check 12 — a recording longer than 90 s is judged (#896)"
echo "  predicate: check 1's toy, waiting 100 s after its write, is exit 0 and oracle_verified true"
echo "  before #896 fs_usage stopped at its own 90 s and the run was refused oracle_saw_nothing"
seed_keep c12
t12=$(date +%s)
rc12=$(PROBE_LINGER_S=100 run c12 libc_toy --oracle-fs-usage)
echo "  exit=$rc12 verdict=$(field c12 verdict) oracle_verified=$(field c12 oracle_verified) reason=$(field c12 unknown_reason) took=$(( $(date +%s) - t12 )) s"
[ "$rc12" = "0" ] || { sed -n '1,12p' "$WORK/c12.txt"; fail "check 12: expected exit 0, got $rc12"; }
[ "$(field c12 oracle_verified)" = "True" ] || fail "check 12: the verdict is not oracle_verified"
echo "  PASS"

echo "=================================================================="
echo "Check 13 — an engine killed by SIGKILL leaves no fs_usage behind (#896)"
echo "  predicate: within 10 s of SIGKILL to the engine during the recording, no fs_usage runs"
echo "  before #896 it ran on to its own -t, which the engine cannot shorten once it is dead"
ensure_no_fs_usage
seed_keep c13
st13="$WORK/state-c13"; log13="$WORK/c13.log"; rm -f "$log13"
PROBE_STATE="$st13" PROBE_LOG="$log13" PROBE_LINGER_S=100 "$SIDEEYE" explore --state "$st13" --operation "$WORK/libc_toy" \
    --shim "$SHIM" --work "$WORK/w-c13" --oracle-fs-usage > "$WORK/c13.txt" 2>&1 &
eng13=$!
t13=$(date +%s)
for _ in $(seq 1 60); do [ -s "$log13" ] && break; sleep 1; done
[ -s "$log13" ] || { kill -9 "$eng13" 2>/dev/null; fail "check 13: the recording never started, so nothing was measured"; }
sleep 5
cap13=$(wc -c < "$WORK/w-c13/oracle.txt" 2>/dev/null || echo 0)
el13=$(( $(date +%s) - t13 ))
pgrep -x fs_usage > /dev/null || { kill -9 "$eng13" 2>/dev/null; fail "check 13: no fs_usage was running before the kill, so nothing was measured"; }
diag13() { ps -ax -o pid,ppid,pgid,ruid,uid,stat,comm | grep -E "fs_usage|sudo|sideeye" | grep -v grep | sed 's/^/    /'; }
sudo13=$(pgrep -P "$eng13" -x sudo | head -1)
echo "  diag: before the kill (engine $eng13, sudo ${sudo13:-none}):"; diag13
kill -0 -- "-${sudo13:-0}" 2>/dev/null; echo "  diag: kill -0 to sudo's group as this user: rc=$?"
kill -9 "$eng13"
gone=no
for _ in $(seq 1 10); do pgrep -x fs_usage > /dev/null || { gone=yes; break; }; sleep 1; done
echo "  diag: 10 s after the kill:"; diag13
if [ "$gone" = no ] && [ -n "$sudo13" ]; then
    kill -TERM -- "-$sudo13" 2>/dev/null; echo "  diag: SIGTERM to sudo's group as this user: rc=$?"
    sleep 5
    if pgrep -x fs_usage > /dev/null; then echo "  diag: fs_usage still runs 5 s after that SIGTERM"; else echo "  diag: that SIGTERM stopped fs_usage"; fi
    if pgrep -x fs_usage > /dev/null; then
        kill -TERM "$sudo13" 2>/dev/null; echo "  diag: SIGTERM to sudo's pid as this user: rc=$?"
        sleep 5
        if pgrep -x fs_usage > /dev/null; then echo "  diag: fs_usage still runs 5 s after the pid's SIGTERM"; else echo "  diag: the pid's SIGTERM stopped fs_usage"; fi
        echo "  diag: after it:"; diag13
    fi
fi
pkill -x libc_toy 2>/dev/null || true
echo "  fs_usage gone within 10 s: $gone; its capture held $cap13 bytes after about $el13 s ($(( cap13 / (el13 > 0 ? el13 : 1) )) bytes/s)"
[ "$gone" = yes ] || { ensure_no_fs_usage; fail "check 13: fs_usage outlived the killed engine"; }
echo "  PASS"

echo "=================================================================="
echo "Check 14 — an engine killed by SIGKILL during the handshake leaves no fs_usage behind (#896)"
echo "  predicate: killed while its opening sentinel is in the state, no fs_usage runs 10 s later"
ensure_no_fs_usage
seed_keep c14
st14="$WORK/state-c14"
PROBE_STATE="$st14" PROBE_LINGER_S=100 "$SIDEEYE" explore --state "$st14" --operation "$WORK/libc_toy" \
    --shim "$SHIM" --work "$WORK/w-c14" --oracle-fs-usage > "$WORK/c14.txt" 2>&1 &
eng14=$!
seen14=no
for _ in $(seq 1 300); do
    if ls "$st14"/.sideeye-fsusage-open.* > /dev/null 2>&1; then seen14=yes; break; fi
    sleep 0.05
done
kill -9 "$eng14" 2>/dev/null
gone14=no
for _ in $(seq 1 10); do pgrep -x fs_usage > /dev/null || { gone14=yes; break; }; sleep 1; done
pkill -x libc_toy 2>/dev/null || true
if [ "$seen14" = no ]; then
    ensure_no_fs_usage
    echo "  NOT MEASURED: the handshake ended before its sentinel was seen; the kill landed after it"
else
    echo "  killed during the handshake; fs_usage gone within 10 s: $gone14"
    [ "$gone14" = yes ] || { ensure_no_fs_usage; fail "check 14: fs_usage outlived an engine killed during the handshake"; }
    echo "  PASS"
fi

echo "=================================================================="
echo "Check 15 — an extended-attribute write on a state file is set aside as metadata (#947)"
echo "  predicate: with PROBE_XATTR the toy also calls setxattr and fsetxattr on keep; the run"
echo "             PASSes oracle-verified and metadata_writes names both calls"
echo "  control:   check 1's run, the same toy without PROBE_XATTR: metadata_writes names neither"
seed_keep c15
rc=$(PROBE_XATTR=1 run c15 libc_toy --oracle-fs-usage)
echo "  control metadata_writes=$(field c1 metadata_writes)"
echo "  xattr   exit=$rc oracle_verified=$(field c15 oracle_verified) metadata_writes=$(field c15 metadata_writes)"
case "$(field c1 metadata_writes)" in *setxattr*) fail "check 15: the control names an attribute write it never made" ;; esac
[ "$rc" = 0 ] || { sed -n '1,12p' "$WORK/c15.txt"; fail "check 15: the run with attribute writes did not PASS"; }
[ "$(field c15 oracle_verified)" = True ] || fail "check 15: the PASS is not oracle-verified"
case "$(field c15 metadata_writes)" in *"fsetxattr"*) ;; *) fail "check 15: metadata_writes does not name fsetxattr" ;; esac
# Anchored on the separator: `fsetxattr x1` contains `setxattr x` too.
case "$(field c15 metadata_writes)" in *": setxattr x"* | *", setxattr x"*) ;; *) fail "check 15: metadata_writes does not name setxattr" ;; esac
echo "  PASS"

echo "=================================================================="
echo "all fifteen checks passed"
echo "artifacts: $WORK"
