/* Same-class probe for #556: a pre-exec child the shim is loaded into, reached through
 * glibc's posix_spawn. glibc resets the child's handlers with its internal
 * __libc_sigaction (not the PLT symbol the shim interposes), then runs the file
 * actions, then execs. A write-capable addopen is a trapped openat in that window.
 *
 *   spawn556 <state-dir>
 * Prints one line per case to stderr, then writes <state-dir>/o.txt so a preflight
 * has something to record. */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static void report(const char *tag, int rc, pid_t pid) {
    if (rc != 0) { fprintf(stderr, "%s -> posix_spawn failed: %s\n", tag, strerror(rc)); return; }
    int st;
    if (waitpid(pid, &st, 0) < 0) { fprintf(stderr, "%s -> waitpid: %s\n", tag, strerror(errno)); return; }
    if (WIFEXITED(st)) fprintf(stderr, "%s -> exited %d\n", tag, WEXITSTATUS(st));
    else if (WIFSIGNALED(st)) fprintf(stderr, "%s -> killed by signal %d\n", tag, WTERMSIG(st));
}

static void one(const char *tag, const char *prog, int flags, int use_open) {
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    if (use_open) posix_spawn_file_actions_addopen(&fa, 1, "/tmp/spawn556-out.txt", flags, 0644);
    char *argv[] = { (char *)prog, NULL };
    pid_t pid = 0;
    int rc = posix_spawn(&pid, prog, &fa, NULL, argv, environ);
    report(tag, rc, pid);
    posix_spawn_file_actions_destroy(&fa);
}

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    one("no file actions, /bin/true          ", "/bin/true", 0, 0);
    one("no file actions, missing program    ", "/nonexistent-tool", 0, 0);
    one("addopen O_RDONLY, /bin/true         ", "/bin/true", O_RDONLY, 1);
    one("addopen O_WRONLY|O_CREAT, /bin/true ", "/bin/true", O_WRONLY | O_CREAT | O_TRUNC, 1);
    char p[1024];
    snprintf(p, sizeof p, "%s/o.txt", argv[1]);
    FILE *f = fopen(p, "w");
    if (!f) return 1;
    fputs("x\n", f);
    fclose(f);
    return 0;
}
