/*
 * A target that does something in one explored world and never in the recording: with
 * `branch`, the world the engine arms at crash point 2 first writes a file into the state
 * through syscall(2), which the shim never sees. The recording, the baseline and every other
 * world write only through libc. Without `branch` it is the control: the same rotation in
 * every run. `children` writes the temporary file from a child the parent waits for, and with
 * `branch` world 2 also starts a shell with an empty environment, so no shim, that writes
 * into the state.
 */

#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

static const char *state_dir(void) {
    const char *d = getenv("TOY_STATE");
    return (d && *d) ? d : "./state";
}

static void path_of(char *out, size_t n, const char *name) {
    snprintf(out, n, "%s/%s", state_dir(), name);
}

static int write_file(const char *name, const char *content) {
    char p[4096];
    path_of(p, sizeof p, name);
    int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    if (write(fd, content, strlen(content)) != (ssize_t)strlen(content)) return -1;
    fsync(fd);
    return close(fd);
}

static void raw_write(const char *name) {
    char p[4096];
    path_of(p, sizeof p, name);
    long fd = syscall(SYS_openat, AT_FDCWD, p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return;
    syscall(SYS_write, (int)fd, "unseen\n", 7);
    syscall(SYS_close, (int)fd);
}

static void unshimmed_child(void) {
    char cmd[4200], env0[4200];
    snprintf(cmd, sizeof cmd, "echo unseen > '%s/extra'", state_dir());
    snprintf(env0, sizeof env0, "TOY_STATE=%s", state_dir());
    char *const args[] = {"sh", "-c", cmd, NULL};
    char *const envp[] = {env0, NULL};
    pid_t p = fork();
    if (p == 0) {
        execve("/bin/sh", args, envp);
        _exit(127);
    }
    if (p > 0) waitpid(p, NULL, 0);
}

static int child_writes(const char *name, const char *content) {
    pid_t p = fork();
    if (p == 0) _exit(write_file(name, content) == 0 ? 0 : 1);
    int st = 0;
    if (p < 0 || waitpid(p, &st, 0) < 0) return -1;
    return WIFEXITED(st) && WEXITSTATUS(st) == 0 ? 0 : -1;
}

int main(int argc, char **argv) {
    if (argc < 2) return 64;
    if (strcmp(argv[1], "init") == 0) {
        mkdir(state_dir(), 0755);
        return write_file("key", "v1\n") == 0 ? 0 : 1;
    }
    int branch = 0, children = 0;
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "branch") == 0) branch = 1;
        if (strcmp(argv[i], "children") == 0) children = 1;
    }
    const char *at = getenv("SIDEEYE_KILL_AT");
    int in_world_2 = branch && at && strcmp(at, "2") == 0;
    if (in_world_2) {
        if (children)
            unshimmed_child();
        else
            raw_write("extra");
    }
    if (strcmp(argv[1], "rotate") != 0) return 64;
    if ((children ? child_writes("key.tmp", "v2\n") : write_file("key.tmp", "v2\n")) != 0) return 1;
    char from[4096], to[4096];
    path_of(from, sizeof from, "key.tmp");
    path_of(to, sizeof to, "key");
    return rename(from, to) == 0 ? 0 : 1;
}
