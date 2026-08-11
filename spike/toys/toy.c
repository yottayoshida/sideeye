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
 *   TOY_SPAWN_WRITES  posix_spawn a shell that writes into the state directory.
 *                     The child never loads the shim's view of the world it was born
 *                     into (new image), and only an oracle can account for it; refuse.
 *   TOY_DETACH        fork a child that calls setsid, escaping the engine's process
 *                     group, then exits. The engine cannot claim to have stopped it.
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
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
    return write_file(key, "key=1\n") == 0 ? 0 : 1;
}

static int cmd_rotate(void) {
    char key[4096], tmp[4096];
    join_path(key, sizeof key, KEY_NAME);
    join_path(tmp, sizeof tmp, TMP_NAME);

    /* A read-only open of state before any mutation. The result is deliberately unused:
     * the point is the open itself, which must not consume a crash-point address. */
    if (getenv("TOY_READ_FIRST")) {
        char buf[256];
        (void)read_key(buf, sizeof buf);
    }

    maybe_leave_the_supported_region();

    if (write_file(tmp, "key=2\n") != 0) return 1;

#ifdef BUGGY
    /* The window: between these two calls there is no key on disk at all. */
    if (unlink(key) != 0 && errno != ENOENT) return 1;
#endif

    if (rename(tmp, key) != 0) return 1;
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
        fprintf(stderr, "usage: %s init|rotate|doctor|load-key\n", argv[0]);
        return 2;
    }
    if (strcmp(argv[1], "init") == 0) return cmd_init();
    if (strcmp(argv[1], "rotate") == 0) return cmd_rotate();
    if (strcmp(argv[1], "doctor") == 0) return cmd_doctor();
    if (strcmp(argv[1], "load-key") == 0) return cmd_load_key();
    fprintf(stderr, "unknown command: %s\n", argv[1]);
    return 2;
}
