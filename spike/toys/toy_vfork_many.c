/* A single-threaded tool that starts many short children through vfork and execve, the way
 * CPython's subprocess does on Linux, and then rewrites its one state file in place.
 *
 *   toy init                 out.txt holds "old"
 *   toy [N]                  N vfork+execve(/bin/true) children (default 70), then
 *                            open(O_TRUNC) and write "done": a kill between the two leaves
 *                            the file empty
 *   toy self-exec-fails [N]  as above, with the subject's own execve of a missing file first;
 *                            the call fails and the subject goes on
 *   toy close-fds [N]        as above, with each child closing descriptors 3..63 before its
 *                            execve
 *   toy threads K N          K threads at once, each starting N such children that close
 *                            descriptors 3..63, then the rewrite from the main thread
 *
 * The state directory is TOY_STATE, which the engine sets.
 */
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static int put(const char *path, const char *text, int flags) {
    int fd = open(path, O_WRONLY | flags, 0644);
    if (fd < 0) { perror("open"); return 1; }
    size_t n = strlen(text);
    if (write(fd, text, n) != (ssize_t)n) { perror("write"); return 1; }
    return close(fd);
}

static int start_children(int n, int close_fds) {
    char *const child[] = { "/bin/true", NULL };
    for (int i = 0; i < n; i++) {
        pid_t p = vfork();
        if (p < 0) { perror("vfork"); return 1; }
        if (p == 0) {
            if (close_fds) for (int fd = 3; fd < 64; fd++) close(fd);
            execve(child[0], child, environ);
            _exit(127);
        }
        int status;
        if (waitpid(p, &status, 0) != p || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
            fprintf(stderr, "child %d did not exit 0\n", i);
            return 1;
        }
    }
    return 0;
}

static int per_thread;

static void *starter(void *unused) {
    (void)unused;
    return (void *)(long)start_children(per_thread, 1);
}

int main(int argc, char **argv) {
    const char *d = getenv("TOY_STATE");
    if (!d) d = "./state";
    char out[1024];
    snprintf(out, sizeof(out), "%s/out.txt", d);
    if (argc > 1 && strcmp(argv[1], "init") == 0) return put(out, "old\n", O_CREAT | O_TRUNC);

    if (argc > 3 && strcmp(argv[1], "threads") == 0) {
        int k = atoi(argv[2]);
        per_thread = atoi(argv[3]);
        pthread_t t[16];
        if (k < 1 || k > 16) return 2;
        for (int i = 0; i < k; i++) pthread_create(&t[i], NULL, starter, NULL);
        long bad = 0;
        for (int i = 0; i < k; i++) { void *r; pthread_join(t[i], &r); bad |= (long)r; }
        if (bad) return 1;
        return put(out, "done\n", O_TRUNC);
    }

    int arg = 1;
    int self_exec_fails = 0, close_fds = 0;
    if (argc > arg && strcmp(argv[arg], "self-exec-fails") == 0) { self_exec_fails = 1; arg++; }
    else if (argc > arg && strcmp(argv[arg], "close-fds") == 0) { close_fds = 1; arg++; }
    int n = argc > arg ? atoi(argv[arg]) : 70;

    if (self_exec_fails) {
        char *const missing[] = { "/nonexistent-sideeye-toy", NULL };
        execve(missing[0], missing, environ);
    }
    if (start_children(n, close_fds)) return 1;
    return put(out, "done\n", O_TRUNC);
}
