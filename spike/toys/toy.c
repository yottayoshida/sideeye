/*
 * A minimal stateful CLI, in the shape sideeye is meant to interrogate.
 *
 * Build twice from this one file:
 *   -DBUGGY=1  -> rotate deletes the current key before renaming the new one in,
 *                 so a crash inside that window leaves no key at all.
 *   (default)  -> rotate renames over the current key, which is atomic.
 *
 * `doctor` is deliberately shallow: it reports health from the existence of the
 * state directory and never checks whether the key can actually be read. That is
 * the self-contradiction check.sh cross-examines — the diagnostic says healthy
 * while the thing it is diagnosing is unusable.
 *
 * Environment:
 *   TOY_STATE      state directory (default ./state)
 *   TOY_FORK       if set, fork a trivial child before rotating (boundary case)
 *   TOY_SELFEXEC   write one state file, then exec this same binary; the rotate runs
 *                  in the second image (#123's judged shape: a tail-exec chain)
 *   TOY_FORKEXEC   fork a child that execs /bin/sh and writes into the state
 *                  directory (#123's still-refused shape: pass's mkdir/mv children)
 *   TOY_EXECL      like TOY_SELFEXEC but through execl, which the shim does not
 *                  interpose: no exec record, no carried count — the second image
 *                  announces itself again, which the engine must catch structurally
 *                  (the numbering-integrity check is the second net behind it)
 *   TOY_VFORK      if set, vfork a child that immediately execs — the only shape POSIX
 *                  sanctions. The shim once interposed vfork with an ordinary wrapper,
 *                  whose stack frame spans vfork's double return: the child clobbered it
 *                  on the shared stack and the parent resumed into the child's branch.
 *                  Exit 0 without the shim, exit 127 with it, no output either way —
 *                  silently wrong, not a crash. The wrapper is now a recorded boundary
 *                  followed by a guaranteed tail jump, and this toy is what pins that:
 *                  the target has to survive being observed.
 *   TOY_READ_FIRST if set, read the current key (a read-only open) before rotating.
 *                  A write-incapable open is not an address (ADR 0003): this toy must
 *                  reach the same crash point count as a plain rotate, and the old
 *                  behaviour — the read consuming crash point 1 — is the red the
 *                  acceptance check exists to show.
 *
 * The three below exist for the history-preservation form (ADR 0004). init creates the
 * files they touch, so each is present in the pre snapshot with non-empty content.
 *   TOY_APPEND          append one line to log.txt whose bytes differ every run (pid +
 *                       monotonic clock), through several small writes so a kill can
 *                       land mid-line. The shape of an audit log or journal — and the
 *                       measured shape of the first real target (#24). Under pre-or-post
 *                       this is structurally UNKNOWN (the re-run baseline never matches
 *                       the recorded final); under the history form it passes, judged
 *                       only on whether the bytes that predate the operation survive.
 *   TOY_APPEND_REWRITE  produce the same final content the way history dies: read all,
 *                       ftruncate to zero, write it back, then the new line. The world
 *                       killed between the truncate and the first write holds an empty
 *                       file. ftruncate is explicit so the counterexample's address
 *                       reads "after truncate", not "after open".
 *   TOY_NONDET_REWRITE  rewrite nondet.txt with different bytes every run. pre is not a
 *                       prefix of post, so the file stays on pre-or-post and the run
 *                       stays UNKNOWN — pinning that the relaxation for files that only
 *                       grow does not leak to files that are rewritten.
 *
 * The five below exist for stdio observation at flush granularity (ADR 0005).
 *   TOY_STDIO          a plain-"r" read (must consume no address), then the
 *                      git-COMMIT_EDITMSG shape: fopen "w", three fprintfs, one
 *                      implicit flush at fclose = [open, write, close].
 *   TOY_STDIO_FLUSH    fflush after each line — three write addresses — plus one
 *                      empty fflush, which issues no syscall and must not be recorded.
 *   TOY_STDIO_FREOPEN  fprintf, then freopen to a second state file while bytes are
 *                      pending: the wrapper must record [write, close, open] in the
 *                      order freopen issues the syscalls.
 *   TOY_STDIO_BIG      3000 lines overflow the buffer inside fprintf; those writes
 *                      bypass the flush wrappers by construction. Pins that the
 *                      boundary refuses (UNKNOWN) instead of quietly miscounting.
 *   TOY_STDIO_NOCLOSE  fprintf and never fclose: the bytes land in libc's exit-time
 *                      cleanup, internal and invisible. Pins the same boundary.
 *   TOY_STDIO_SEEK     the taskwarrior shape: an "r+" update stream made dirty and
 *                      then repositioned — libc flushes inside the fseek, so the seek
 *                      family are flush points too. init creates the file so it is in
 *                      the pre snapshot.
 *
 * The four below exist for typed path resolution and first-class links (ADR 0006).
 *   TOY_LINK           the git loose-object idiom: write a tmp, link it into its final
 *                      name, unlink the tmp — link is a first-class kill point.
 *   TOY_RELATIVE       the same idiom after chdir into the state directory, spelled
 *                      relative. Its resolved paths — and so its kill-point sequence —
 *                      must equal TOY_LINK's, whether strace annotates the cwd (aarch64)
 *                      or the legacy syscalls force it to be tracked (x86-64 CI).
 *   TOY_LINK_IN        link a source OUTSIDE the state directory to a name inside it.
 *                      A two-path operation touches the state directory when either end
 *                      is inside, and this pins that the outside->inside direction counts.
 *   TOY_SYMLINK        create a symlink inside the state directory. First-class since
 *                      contract v9 (#122): recorded as a kill point on the LINK PATH
 *                      (the target string is never resolved), restored as a link —
 *                      and a relative spelling still reaches the same class.
 *   TOY_CHMOD          chmod a state file during rotate. Recorded-only (#121): the
 *                      oracle observes it, the verdict excludes it, the report names
 *                      it — never `unsupported`, never a kill point.
 *   TOY_MKNOD          mknod a fifo inside the state directory: the control beside
 *                      TOY_CHMOD — an unmodelled syscall must still refuse, because
 *                      #121's exclusion is a defined list, not a loosened net.
 *   TOY_MKNOD_TRANSIENT  mknod a fifo, then remove it before rotating. The mknod is
 *                      invisible to the shim (not interposed); the remove's unlink IS
 *                      a recorded kill point — so the world killed before that unlink
 *                      holds a FIFO in its crashed snapshot while the initial and
 *                      final states are clean. The crashed-side window for #5.
 *   TOY_MKNOD_BASELINE mkfifo as rotate's very LAST act, but only when the flag file
 *                      named by TOY_ONCE_FLAG (outside the state directory, so restore
 *                      never resets it) already exists; the first completed run — the
 *                      recording — plants the flag instead. Killed worlds never reach
 *                      the last act, so only the baseline re-run leaves the FIFO:
 *                      the attribution case for #5's per-world refusal.
 *   TOY_NONDET_REMOVE  init writes nondet.txt; once the flag file named by TOY_ONCE_FLAG
 *                      exists (rotate's last act plants it, so the recording does), rotate
 *                      REPLACES its final rename with unlink(nondet.txt). Same op count as
 *                      the recording, so every kill still lands where it did; with no
 *                      trailing-op knob (TOY_MARKER and friends add ops after the rename)
 *                      killed worlds die at or before that op and keep the file, and only
 *                      the un-killed baseline re-run executes it: the `missing` kind of
 *                      baseline_violates_invariant, for #199's per-kind wording. Not an
 *                      extra op after the rename: the baseline is the world whose kill
 *                      would land on op n+1, and an interposed op there dies as
 *                      baseline_run_failed (measured 2026-09-03, with unlink and with
 *                      remove(3) alike on macOS).
 *   TOY_REMOVE         delete state through remove(3) — a file, a path that was never
 *                      created, and a directory. libc implements remove as unlink (then
 *                      rmdir on the directory errno) internally, without crossing the
 *                      PLT, so a shim that only interposes unlink is blind to all three
 *                      while the oracle sees every attempt. The timewarrior shape: its
 *                      AtomicFile cleanup removes each registered temp name at exit,
 *                      including names it never created.
 *
 * The four below exist for the L1 success marker (ADR 0008).
 *   TOY_MARKER          the correct shape: commit everything, print COMMITTED with an
 *                       explicit flush, then do benign trailing work (a scratch file in
 *                       neither the pre nor the post snapshot) so crash points exist on
 *                       the far side of the claim. Marker worlds must PASS.
 *   TOY_MARKER_EARLY    the bug shape: the claim precedes the commit. Worlds killed
 *                       between the flush and the rename hold old content while the
 *                       marker was already spoken — not_durable.
 *   TOY_MARKER_CREATES  claims success, then creates receipt.txt (a post-only file the
 *                       claim covers). The world killed before the create has the
 *                       marker and no receipt — not_durable pins the existence rule.
 *   TOY_MARKER_NOFLUSH  prints the marker with no flush. Every killed world loses the
 *                       buffer with the process, so zero crash worlds observe it — an
 *                       honestly vacuous L1 — while the recording run's exit-time flush
 *                       still delivers it, so the run is not marker_never_observed.
 *   TOY_EXTRA_FIRST     one extra state operation before everything else: the
 *                       prefix-insertion that must make a saved case refuse as
 *                       "case no longer applies" instead of silently verifying a
 *                       shifted address (ADR 0009).
 *   TOY_DUP2       state writes through the standard descriptors, in a fixed order:
 *                  a state file dup2'd onto fd 1 and written through write(1), the
 *                  same through fd 2, the same through fd 0, and finally a stdio leg
 *                  (stdout rebound to a state file, fprintf + fflush). A descriptor's
 *                  number must not exempt it from observation: before contract v8 the
 *                  shim skipped fd <= 2 unconditionally, and every one of these writes
 *                  was invisible — the acceptance table pins each leg separately so a
 *                  fix for fd 1 alone cannot pass.
 *   TOY_CLOSE_SWEEP=N  daemonize-style descriptor hygiene: close(3..N) before any
 *                  state work. A bound below the shim's trace-fd relocation floor
 *                  must leave the run's verdict untouched; a bound at or above it
 *                  closes the shim's own trace channel, and the run must refuse —
 *                  never keep writing trace records into whatever file inherits
 *                  the number.
 *   TOY_ANONFD     open and close descriptors that are provably not files: eventfd
 *                  and epoll on Linux (fstat type bits zero — the kernel's
 *                  anon-inode spelling), kqueue on macOS (stats as a FIFO). Must be
 *                  invisible to the verdict: none can be state-directory content.
 *   TOY_EXIT_STATUS=N  rotate exits N after completing all of its state work — the
 *                  git-convention shape (#3). Without --expect-status N the run must
 *                  refuse as recording_run_failed naming both statuses; with it, the
 *                  same run explores normally and the baseline is held to N too.
 *   TOY_THREAD     if set, create and join a trivial thread before rotating
 *   TOY_FORK_LATE  if set, fork a child that outlives the parent and writes into the
 *                  state directory after a delay, then rotate without waiting for it.
 *                  The parent finishing (or being killed) must not leave that write to
 *                  land: it would arrive while the engine is snapshotting, restoring or
 *                  running the checker, and the verdict would describe a moment nobody
 *                  chose. Used to check that the engine confines the whole process group.
 *
 * The four below exist for boundary tolerance: same binary, one variable of difference,
 * so an engine that decided by anything other than what the child actually did cannot
 * pass their acceptance checks.
 *   TOY_FORK_WRITES   fork a child that writes into the state directory and wait for
 *                     it. The child's operation has no crash-point address; must refuse.
 *   TOY_SPAWN         posix_spawn a process that touches nothing and wait for it.
 *                     Tolerable: the subject's account remains complete.
 *   TOY_FORK_WORLD    the same quiet fork as TOY_FORK, taken only when SIDEEYE_KILL_AT
 *                     is set — inside crash worlds, never in the recording run. The
 *                     recording-global boundary story then says "no boundary" while
 *                     every explored world crosses one: the arming case for the
 *                     per-world quiescence observation (#46).
 *   TOY_SPAWN_WRITES  posix_spawn a shell that writes into the state directory.
 *                     The child never loads the shim's view of the world it was born
 *                     into (new image), and only an oracle can account for it; refuse.
 *   TOY_DETACH        fork a child that calls setsid, escaping the engine's process
 *                     group, then exits. The engine cannot claim to have stopped it.
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#ifdef __linux__
#include <sys/epoll.h>
#include <sys/eventfd.h>
#endif
#ifdef __APPLE__
#include <sys/event.h>
#endif
#include <pthread.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

#define KEY_NAME "key.json"
#define TMP_NAME "key.json.tmp"

static const char *state_dir(void) {
    const char *d = getenv("TOY_STATE");
    return (d && *d) ? d : "./state";
}

static void join_path(char *out, size_t n, const char *name) {
    snprintf(out, n, "%s/%s", state_dir(), name);
}

static int write_file(const char *path, const char *content) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    size_t len = strlen(content);
    size_t off = 0;
    while (off < len) {
        ssize_t w = write(fd, content + off, len - off);
        if (w <= 0) { close(fd); return -1; }
        off += (size_t)w;
    }
    if (fsync(fd) != 0) { close(fd); return -1; }
    if (close(fd) != 0) return -1;
    return 0;
}

/* The git loose-object idiom: write a temp, link it into place, drop the temp. */
static int link_idiom(const char *tmp, const char *dst) {
    if (write_file(tmp, "object\n") != 0) return -1;
    if (link(tmp, dst) != 0) return -1;
    if (unlink(tmp) != 0) return -1;
    return 0;
}

static int read_key(char *buf, size_t n) {
    char path[4096];
    join_path(path, sizeof path, KEY_NAME);
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    ssize_t r = read(fd, buf, n - 1);
    close(fd);
    if (r <= 0) return -1;
    buf[r] = '\0';
    return 0;
}

static void *noop_thread(void *arg) {
    (void)arg;
    return NULL;
}

/* Optional boundary behaviour, requested through the environment so one binary
 * can play both the supported and the unsupported target. */
static void maybe_leave_the_supported_region(void) {
    if (getenv("TOY_FORK")) {
        pid_t p = fork();
        if (p == 0) _exit(0);
        if (p > 0) { int st; waitpid(p, &st, 0); }
    }
    /* World-only boundary: the engine sets SIDEEYE_KILL_AT in crash worlds and never
     * in the recording run, so this fork exists in every explored world while the
     * recording's account honestly says "single process". */
    if (getenv("TOY_FORK_WORLD")) {
        const char *ka = getenv("SIDEEYE_KILL_AT");
        if (ka && *ka) {
            pid_t p = fork();
            if (p == 0) _exit(0);
            if (p > 0) { int st; waitpid(p, &st, 0); }
        }
    }
    /* vfork's child may only _exit or exec; anything else is undefined. Exec is the
     * whole reason vfork exists, so that is what this does.
     *
     * The argv is static and fully initialised at compile time: after vfork the child
     * may modify nothing but the pid_t holding the return value, and building the array
     * in the child would write into the very frame the suspended parent resumes from —
     * the same class of corruption this toy exists to catch in the shim.
     *
     * macOS has no /bin/true; only /usr/bin/true. With the wrong path the exec fails,
     * the child falls through to _exit(127), and the toy still looks fine because the
     * parent discards the child's status — the test quietly measures less than it says. */
#ifdef __APPLE__
#define TOY_TRUE "/usr/bin/true"
#else
#define TOY_TRUE "/bin/true"
#endif
    if (getenv("TOY_VFORK")) {
        static char *const av[] = { (char *)TOY_TRUE, NULL };
        pid_t p = vfork();
        if (p == 0) {
            execv(TOY_TRUE, av);
            _exit(127);
        }
        if (p > 0) { int st; waitpid(p, &st, 0); }
    }
    if (getenv("TOY_THREAD")) {
        pthread_t t;
        if (pthread_create(&t, NULL, noop_thread, NULL) == 0) pthread_join(t, NULL);
    }
    /* Deliberately not waited for. The child sleeps past anything the parent will do,
     * so its write lands only if the engine let it survive. */
    if (getenv("TOY_FORK_LATE")) {
        pid_t p = fork();
        if (p == 0) {
            char late[4096];
            join_path(late, sizeof late, "late.txt");
            usleep(300 * 1000);
            write_file(late, "written after the parent was gone\n");
            _exit(0);
        }
    }
    /* The refusal case for a forked child: it writes where only the subject may. */
    if (getenv("TOY_FORK_WRITES")) {
        pid_t p = fork();
        if (p == 0) {
            char child_file[4096];
            join_path(child_file, sizeof child_file, "from-child.txt");
            write_file(child_file, "a child wrote this\n");
            _exit(0);
        }
        if (p > 0) { int st; waitpid(p, &st, 0); }
    }
    /* The tolerable spawn: a new process and a new image, touching nothing. */
    if (getenv("TOY_SPAWN")) {
        static char *const av[] = { (char *)TOY_TRUE, NULL };
        pid_t sp;
        if (posix_spawn(&sp, TOY_TRUE, NULL, NULL, av, environ) == 0) {
            int st;
            waitpid(sp, &st, 0);
        }
    }
    /* The refusal case for a spawned child — and deliberately one the shim cannot see.
     * The environment passed to the child is empty: no LD_PRELOAD, no shim, no records.
     * TOY_FORK_WRITES pins the shim-side witness (its child inherits the shim); this
     * one pins the oracle, which is the only observer of a child that never loaded
     * anything — the reason boundary tolerance requires an oracle at all. */
    if (getenv("TOY_SPAWN_WRITES")) {
        char cmd[4200];
        snprintf(cmd, sizeof cmd, "echo spawned > %s/spawned.txt", state_dir());
        char *const av[] = { (char *)"sh", (char *)"-c", cmd, NULL };
        char *const ev[] = { NULL };
        pid_t sp;
        if (posix_spawn(&sp, "/bin/sh", NULL, NULL, av, ev) == 0) {
            int st;
            waitpid(sp, &st, 0);
        }
    }
    /* The escape: a child that leaves the process group the engine relies on. */
    if (getenv("TOY_DETACH")) {
        pid_t p = fork();
        if (p == 0) {
            setsid();
            _exit(0);
        }
        if (p > 0) { int st; waitpid(p, &st, 0); }
    }
}

static int cmd_init(void) {
    if (mkdir(state_dir(), 0755) != 0 && errno != EEXIST) return 1;
    char key[4096];
    join_path(key, sizeof key, KEY_NAME);
    if (write_file(key, "key=1\n") != 0) return 1;
    /* The history-form toys need their files in the *pre* snapshot with non-empty
     * content: a file absent from pre is outside L0, and one empty in pre stays on
     * the standard rule by design (ADR 0004). */
    if (getenv("TOY_APPEND") || getenv("TOY_APPEND_REWRITE")) {
        char log[4096];
        join_path(log, sizeof log, "log.txt");
        if (write_file(log, "born\n") != 0) return 1;
    }
    if (getenv("TOY_NONDET_REWRITE") || getenv("TOY_NONDET_REMOVE")) {
        char nd[4096];
        join_path(nd, sizeof nd, "nondet.txt");
        if (write_file(nd, "seed\n") != 0) return 1;
    }
    if (getenv("TOY_SPLIT_REWRITE")) {
        char d[4096], p[4096];
        join_path(d, sizeof d, "derived.txt");
        join_path(p, sizeof p, "primary.txt");
        if (write_file(d, "derived-old\n") != 0) return 1;
        if (write_file(p, "primary-old\n") != 0) return 1;
    }
    if (getenv("TOY_STDIO_SEEK")) {
        char sk[4096];
        join_path(sk, sizeof sk, "stdio-seek.txt");
        if (write_file(sk, "0123456789\n") != 0) return 1;
    }
    return 0;
}

/* The once-flag named by TOY_ONCE_FLAG lives outside the state directory, so restore
 * never resets it: the first run that completes plants it and every later run sees it.
 * Shared by every "only the baseline re-run does X" knob (TOY_MKNOD_BASELINE,
 * TOY_NONDET_REMOVE); an unset name means no flag, so nothing is planted or seen. */
static int once_flag_planted(void) {
    const char *flag = getenv("TOY_ONCE_FLAG");
    return flag && *flag && access(flag, F_OK) == 0;
}
static int plant_once_flag(void) { /* 0 on success or when there is nothing to plant */
    const char *flag = getenv("TOY_ONCE_FLAG");
    if (!flag || !*flag || access(flag, F_OK) == 0) return 0;
    int fd = open(flag, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return 1;
    close(fd);
    return 0;
}

static int cmd_rotate(void) {
    char key[4096], tmp[4096];
    join_path(key, sizeof key, KEY_NAME);
    join_path(tmp, sizeof tmp, TMP_NAME);

    /* The poetry shape, shrunk (#231, ADR 0020): two in-place truncate-and-write
     * rewrites, derived first, primary second — exactly four kill points (open,
     * write, open, write; no fsync, so the numbering matches the declared k=2 /
     * k=4). The split checker (check-split.sh) judges only the primary, so the
     * derived file's mid-write world is an L0-only precision-limit observation
     * standing physically ahead of the checker-red world: the overall earliest
     * and the claim exhibit are forced apart. Replaces the key rotate. */
    if (getenv("TOY_SPLIT_REWRITE")) {
        char d[4096], p[4096];
        join_path(d, sizeof d, "derived.txt");
        join_path(p, sizeof p, "primary.txt");
        int fd = open(d, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0) return 1;
        if (write(fd, "derived-new\n", 12) != 12) { close(fd); return 1; }
        if (close(fd) != 0) return 1;
        fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0) return 1;
        if (write(fd, "primary-new\n", 12) != 12) { close(fd); return 1; }
        if (close(fd) != 0) return 1;
        return 0;
    }

    /* A read-only open of state before any mutation. The result is deliberately unused:
     * the point is the open itself, which must not consume a crash-point address. */
    /* Before everything else, so a saved case's whole prefix shifts by one. */
    if (getenv("TOY_EXTRA_FIRST")) {
        char ex[4096];
        join_path(ex, sizeof ex, "extra.txt");
        if (write_file(ex, "extra\n") != 0) return 1;
    }

    if (getenv("TOY_READ_FIRST")) {
        char buf[256];
        (void)read_key(buf, sizeof buf);
    }

    /* Daemonize-style descriptor hygiene, first thing, the way a service would. */
    if (getenv("TOY_CLOSE_SWEEP")) {
        int hi = atoi(getenv("TOY_CLOSE_SWEEP"));
        for (int fd = 3; fd <= hi; fd++) close(fd);
    }

    /* Descriptors that are provably not files; opening and closing them must not
     * move the verdict. */
    if (getenv("TOY_ANONFD")) {
#ifdef __linux__
        int efd = eventfd(0, 0);
        int epfd = epoll_create1(0);
        if (efd < 0 || epfd < 0) return 1;
        close(efd);
        close(epfd);
#else
        int kq = kqueue();
        if (kq < 0) return 1;
        close(kq);
#endif
    }

    /* State writes through the standard descriptors. Each leg saves the original
     * descriptor with dup, rebinds the number to a state file, writes through the
     * bare number, and restores — so the engine's stdout capture keeps working
     * between legs and the toy stays honest about where its output goes. */
    if (getenv("TOY_DUP2")) {
        static const int std_fds[] = { 1, 2, 0 };
        static const char *const names[] = { "dup-fd1.txt", "dup-fd2.txt", "dup-fd0.txt" };
        for (int i = 0; i < 3; i++) {
            char p[4096];
            join_path(p, sizeof p, names[i]);
            int saved = dup(std_fds[i]);
            int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (saved < 0 || fd < 0) return 1;
            if (dup2(fd, std_fds[i]) < 0) return 1;
            close(fd);
            if (write(std_fds[i], "via std fd\n", 11) != 11) return 1;
            if (dup2(saved, std_fds[i]) < 0) return 1;
            close(saved);
        }
        /* The stdio leg: the same rebinding, driven through the FILE* layer the shim
         * observes at flush granularity (ADR 0005). fileno(stdout) is 1 here. */
        {
            char p[4096];
            join_path(p, sizeof p, "dup-stdio.txt");
            int saved = dup(1);
            int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (saved < 0 || fd < 0) return 1;
            if (dup2(fd, 1) < 0) return 1;
            close(fd);
            fprintf(stdout, "via stdio on rebound stdout\n");
            if (fflush(stdout) != 0) return 1;
            if (dup2(saved, 1) < 0) return 1;
            close(saved);
        }
    }

    /* Append one line whose bytes no run repeats, in several small writes. */
    if (getenv("TOY_APPEND")) {
        char log[4096];
        join_path(log, sizeof log, "log.txt");
        int fd = open(log, O_WRONLY | O_APPEND);
        if (fd < 0) return 1;
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        char line[128];
        int len = snprintf(line, sizeof line, "append pid=%d t=%ld.%09ld\n",
                           (int)getpid(), (long)ts.tv_sec, (long)ts.tv_nsec);
        for (int off = 0; off < len; off += 8) {
            int chunk = len - off < 8 ? len - off : 8;
            if (write(fd, line + off, (size_t)chunk) != chunk) { close(fd); return 1; }
        }
        if (close(fd) != 0) return 1;
    }

    /* The same final content, produced the way history dies. */
    if (getenv("TOY_APPEND_REWRITE")) {
        char log[4096], old[4096];
        join_path(log, sizeof log, "log.txt");
        int rfd = open(log, O_RDONLY);
        if (rfd < 0) return 1;
        ssize_t oldlen = read(rfd, old, sizeof old);
        close(rfd);
        if (oldlen < 0) return 1;
        int fd = open(log, O_WRONLY);
        if (fd < 0) return 1;
        if (ftruncate(fd, 0) != 0) { close(fd); return 1; }
        if (write(fd, old, (size_t)oldlen) != oldlen) { close(fd); return 1; }
        const char *line = "appended\n";
        if (write(fd, line, strlen(line)) != (ssize_t)strlen(line)) { close(fd); return 1; }
        if (close(fd) != 0) return 1;
    }

    /* The git-COMMIT_EDITMSG shape, with a read control in front. */
    if (getenv("TOY_STDIO")) {
        char key[4096], sp[4096];
        join_path(key, sizeof key, KEY_NAME);
        join_path(sp, sizeof sp, "stdio.txt");
        FILE *rf = fopen(key, "r"); /* must not consume a crash-point address */
        if (!rf) return 1;
        (void)fgetc(rf);
        fclose(rf);
        FILE *f = fopen(sp, "w");
        if (!f) return 1;
        for (int i = 0; i < 3; i++) fprintf(f, "line %d\n", i);
        if (fclose(f) != 0) return 1;
    }

    if (getenv("TOY_STDIO_FLUSH")) {
        char sp[4096];
        join_path(sp, sizeof sp, "stdio.txt");
        FILE *f = fopen(sp, "w");
        if (!f) return 1;
        for (int i = 0; i < 3; i++) {
            fprintf(f, "line %d\n", i);
            if (fflush(f) != 0) { fclose(f); return 1; }
        }
        /* An empty flush issues no write(2) and must not be recorded as one. */
        if (fflush(f) != 0) { fclose(f); return 1; }
        if (fclose(f) != 0) return 1;
    }

    if (getenv("TOY_STDIO_FREOPEN")) {
        char a[4096], b[4096];
        join_path(a, sizeof a, "stdio-a.txt");
        join_path(b, sizeof b, "stdio-b.txt");
        FILE *f = fopen(a, "w");
        if (!f) return 1;
        fprintf(f, "into a\n"); /* pending at the freopen: [write, close, open] */
        f = freopen(b, "w", f);
        if (!f) return 1;
        fprintf(f, "into b\n");
        if (fclose(f) != 0) return 1;
    }

    if (getenv("TOY_STDIO_BIG")) {
        char sp[4096];
        join_path(sp, sizeof sp, "stdio.txt");
        FILE *f = fopen(sp, "w");
        if (!f) return 1;
        for (int i = 0; i < 3000; i++) fprintf(f, "0123456789\n");
        if (fclose(f) != 0) return 1;
    }

    if (getenv("TOY_STDIO_NOCLOSE")) {
        char sp[4096];
        join_path(sp, sizeof sp, "stdio.txt");
        FILE *f = fopen(sp, "w");
        if (!f) return 1;
        fprintf(f, "never closed\n");
        /* Deliberately no fclose. */
    }

    if (getenv("TOY_STDIO_SEEK")) {
        char sk[4096];
        join_path(sk, sizeof sk, "stdio-seek.txt");
        FILE *f = fopen(sk, "r+");
        if (!f) return 1;
        fprintf(f, "AB"); /* dirty the stream, then reposition: libc flushes here */
        if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return 1; }
        if (fclose(f) != 0) return 1; /* nothing pending; a close, not a write */
    }

    if (getenv("TOY_LINK")) {
        char tmp[4096], dst[4096];
        join_path(tmp, sizeof tmp, "obj.tmp");
        join_path(dst, sizeof dst, "obj.final");
        if (link_idiom(tmp, dst) != 0) return 1;
    }

    if (getenv("TOY_RELATIVE")) {
        /* The same idiom, spelled relative after entering the state directory. */
        if (chdir(state_dir()) != 0) return 1;
        if (link_idiom("obj.tmp", "obj.final") != 0) return 1;
    }

    if (getenv("TOY_LINK_IN")) {
        /* Source outside the state directory, new name inside it. */
        char src[4096] = "/tmp/toy-link-src.XXXXXX";
        int sfd = mkstemp(src);
        if (sfd < 0) return 1;
        if (write(sfd, "x\n", 2) != 2) { close(sfd); return 1; }
        close(sfd);
        char dst[4096];
        join_path(dst, sizeof dst, "linked-in");
        if (link(src, dst) != 0) { unlink(src); return 1; }
        unlink(src);
    }

    if (getenv("TOY_SYMLINK")) {
        char lnk[4096];
        join_path(lnk, sizeof lnk, "sym");
        if (symlink("key.json", lnk) != 0) return 1;
    }

    /* Delete through remove(3): the syscalls happen inside libc, behind the PLT. */
    if (getenv("TOY_REMOVE")) {
        char scratch[4096], gone[4096], dir[4096];
        join_path(scratch, sizeof scratch, "scratch.txt");
        int fd = open(scratch, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0) return 1;
        if (write(fd, "x\n", 2) != 2) { close(fd); return 1; }
        if (close(fd) != 0) return 1;
        if (remove(scratch) != 0) return 1;
        /* A remove of a path that was never created: the attempt must still be an
         * address on both accounts, or they desync right here. */
        join_path(gone, sizeof gone, "never-made.tmp");
        if (remove(gone) == 0 || errno != ENOENT) return 1;
        /* A directory: glibc probes with unlink, takes EISDIR, then rmdir. */
        join_path(dir, sizeof dir, "subdir");
        if (mkdir(dir, 0755) != 0) return 1;
        if (remove(dir) != 0) return 1;
    }

    /* An ownership/permission write on state: recorded-only since #121 (option b) —
     * the oracle observes it, excludes it from judgement, and the report says so.
     * Before #121 this single call sent the whole run to unsupported_syscall_observed
     * (the devtodo shape from the #118 cohort). */
    if (getenv("TOY_CHMOD")) {
        char p[4096];
        join_path(p, sizeof p, "key.json");
        if (chmod(p, 0600) != 0) return 1;
    }

    /* An unmodelled state-touching syscall: must stay an unsupported refusal — #121's
     * exclusion is a defined list, not a loosened net. */
    if (getenv("TOY_MKNOD")) {
        char f[4096];
        join_path(f, sizeof f, "fifo");
        if (mknod(f, S_IFIFO | 0644, 0) != 0) return 1;
    }

    /* A special file that exists only inside the operation: the mknod is invisible to
     * the shim, the remove's unlink is a recorded kill point — the world killed before
     * that unlink holds the FIFO while initial and final are clean (#5). */
    if (getenv("TOY_MKNOD_TRANSIENT")) {
        char f[4096];
        join_path(f, sizeof f, "transient-fifo");
        if (mknod(f, S_IFIFO | 0644, 0) != 0) return 1;
        if (remove(f) != 0) return 1;
    }

    /* A rewrite that no run repeats — the class the history form must NOT tolerate. */
    if (getenv("TOY_NONDET_REWRITE")) {
        char nd[4096];
        join_path(nd, sizeof nd, "nondet.txt");
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        char content[128];
        snprintf(content, sizeof content, "run pid=%d t=%ld.%09ld\n",
                 (int)getpid(), (long)ts.tv_sec, (long)ts.tv_nsec);
        if (write_file(nd, content) != 0) return 1;
    }

    /* The L1 bug shapes: the success claim precedes the commit (ADR 0008). */
    if (getenv("TOY_MARKER_EARLY")) {
        printf("COMMITTED\n");
        fflush(stdout);
    }
    if (getenv("TOY_MARKER_CREATES")) {
        printf("COMMITTED\n");
        fflush(stdout);
        char rc[4096];
        join_path(rc, sizeof rc, "receipt.txt");
        if (write_file(rc, "ok\n") != 0) return 1;
    }

    maybe_leave_the_supported_region();

    if (write_file(tmp, "key=2\n") != 0) return 1;

#ifdef BUGGY
    /* The window: between these two calls there is no key on disk at all. */
    if (unlink(key) != 0 && errno != ENOENT) return 1;
#endif

    if (getenv("TOY_NONDET_REMOVE") && once_flag_planted()) {
        /* #199's `missing` kind: in place of the commit, not after it, so the op count
         * matches the recording and every kill lands where it did. With no trailing-op
         * knob set, killed worlds die at or before this op and keep nondet.txt; the
         * un-killed baseline removes it. */
        char nd[4096];
        join_path(nd, sizeof nd, "nondet.txt");
        if (unlink(nd) != 0) return 1;
    } else if (rename(tmp, key) != 0) return 1;

    /* The correct L1 shape: claim success only after the commit, then do benign
     * trailing work so crash points exist on the far side of the claim. The scratch
     * file is in neither the pre nor the post snapshot, so only the marker windows
     * make these addresses interesting. */
    if (getenv("TOY_MARKER") || getenv("TOY_MARKER_NOFLUSH")) {
        printf("COMMITTED\n");
        if (getenv("TOY_MARKER")) fflush(stdout);
        char scr[4096];
        join_path(scr, sizeof scr, "post-marker.tmp");
        if (write_file(scr, "x\n") != 0) return 1;
        if (unlink(scr) != 0) return 1;
    }
    /* The very last act, so no killed world ever reaches it: the recording (first
     * completed run) plants the flag, and only the baseline re-run — the other run
     * that finishes — sees it and leaves the FIFO (#5's attribution case). */
    if (getenv("TOY_MKNOD_BASELINE")) {
        if (once_flag_planted()) {
            char f[4096];
            join_path(f, sizeof f, "baseline-fifo");
            if (mknod(f, S_IFIFO | 0644, 0) != 0) return 1;
        } else if (plant_once_flag() != 0) return 1;
    }

    /* The flag for TOY_NONDET_REMOVE is planted here, as the last act, so only a run
     * that completes — the recording — plants it; the substitution it arms sits at the
     * final rename above, in place of an op, not after the last one (#199). */
    if (getenv("TOY_NONDET_REMOVE") && plant_once_flag() != 0) return 1;

    /* Last, after every state operation: the git-convention shape, where a run that
     * did all its work still reports a non-zero status by design. */
    if (getenv("TOY_EXIT_STATUS")) return atoi(getenv("TOY_EXIT_STATUS"));
    return 0;
}

/* Reports health from the directory alone. Never opens the key. */
static int cmd_doctor(void) {
    struct stat st;
    if (stat(state_dir(), &st) == 0 && S_ISDIR(st.st_mode)) {
        printf("healthy\n");
        return 0;
    }
    printf("unhealthy\n");
    return 0;
}

static int cmd_load_key(void) {
    char buf[256];
    if (read_key(buf, sizeof buf) != 0) return 1;
    if (strncmp(buf, "key=", 4) != 0) return 1;
    printf("%s", buf);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s init|rotate|rotate-msg|doctor|load-key\n", argv[0]);
        return 2;
    }
    if (strcmp(argv[1], "init") == 0) return cmd_init();
    /* rotate-msg <message>: rotates only when <message> is the exact byte string
     * "note with spaces" — one argv element carrying spaces. The split-on-space
     * string form cannot spell that argument (it arrives split into three
     * elements and argc lands at 5), so a rotate reached through this command is
     * structural evidence the argv form (#95, ADR 0019) delivered its elements
     * verbatim. Anything else exits 1 before touching the state. */
    if (strcmp(argv[1], "rotate-msg") == 0) {
        if (argc != 3 || strcmp(argv[2], "note with spaces") != 0) {
            fprintf(stderr, "rotate-msg requires exactly one argument, the exact string \"note with spaces\"\n");
            return 1;
        }
        return cmd_rotate();
    }
    /* TOY_SELFEXEC: the tail-exec CLI shape #123 judges. Stage 1 writes one state
     * file (so the carried operation count is non-trivial), then replaces this
     * image with itself; the whole rotate runs in the SECOND image. Stage 2 is
     * marked through the environment so the chain has exactly two links. A failed
     * exec exits loudly instead of falling through to a single-image rotate that
     * would fake the chain. */
    if (strcmp(argv[1], "rotate") == 0 && getenv("TOY_SELFEXEC") && !getenv("TOY_SELFEXEC_STAGE2")) {
        char staged[4096];
        join_path(staged, sizeof staged, "staged.txt");
        if (write_file(staged, "stage one was here\n") != 0) return 1;
        setenv("TOY_SELFEXEC_STAGE2", "1", 1);
        execv(argv[0], argv);
        _exit(127);
    }
    /* TOY_EXECL: the same chain through execl, which the shim does NOT interpose —
     * no exec record, no carried count. The second image restarts numbering at 1,
     * and the engine's records-vs-max check must refuse rather than address a
     * world by a duplicated number. */
    if (strcmp(argv[1], "rotate") == 0 && getenv("TOY_EXECL") && !getenv("TOY_EXECL_STAGE2")) {
        char staged[4096];
        join_path(staged, sizeof staged, "staged.txt");
        if (write_file(staged, "stage one was here\n") != 0) return 1;
        setenv("TOY_EXECL_STAGE2", "1", 1);
        execl(argv[0], argv[0], "rotate", (char *)NULL);
        _exit(127);
    }
    /* TOY_FORKEXEC: the shape the slice still refuses — a CHILD execs and mutates
     * the judged state (pass's mkdir/mv children, measured in #123). The child
     * inherits the full environment, shim included: the refusal must come from
     * the judge seeing it, not from the child being invisible. The parent then
     * rotates normally, so the run holds both a subject mutation and a child's. */
    if (strcmp(argv[1], "rotate") == 0 && getenv("TOY_FORKEXEC")) {
        char cmd[4200];
        snprintf(cmd, sizeof cmd, "echo forked > %s/forked.txt", state_dir());
        pid_t p = fork();
        if (p == 0) {
            execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
            _exit(127);
        }
        if (p > 0) { int st; waitpid(p, &st, 0); }
    }
    if (strcmp(argv[1], "rotate") == 0) return cmd_rotate();
    if (strcmp(argv[1], "doctor") == 0) return cmd_doctor();
    if (strcmp(argv[1], "load-key") == 0) return cmd_load_key();
    fprintf(stderr, "unknown command: %s\n", argv[1]);
    return 2;
}
