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
# The raw-child fixture is the TRACKED one, not a copy. It used to be a heredoc here,
# and a third copy lived in spike/fsusage/phase0/ — three files, one claim, hand-synced,
# and they had already drifted (`PROBE_STATE` only versus `TOY_STATE` then `PROBE_STATE`;
# a raw-fork fallback present in one and absent in another). Check 3 below and
# `spike/acceptance.sh` check 2af assert the same thing about the same shape, so they had
# better be asserting it about the same program. The tracked fixture reads both variable
# spellings, which is why this can hand it `PROBE_STATE` unchanged.
cp "$HERE/spike/toys/toy_rawchild.c" "$WORK/rawchild_toy.c" ||
    fail "the tracked #405 fixture is missing: spike/toys/toy_rawchild.c"
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
echo "all five checks passed"
echo "artifacts: $WORK"
