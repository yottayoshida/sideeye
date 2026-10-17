/*   toy init            key.json holds "old"
 *   toy rotate          open(key.json, O_WRONLY|O_TRUNC) with no mode, then write "new"
 *   toy sweep           closefrom(3) first, then the same rewrite
 *   toy sweep-range     close_range(3, ~0U, 0) first, then the same rewrite
 *   toy sweep-lowlimit  RLIMIT_NOFILE's soft value lowered to 256, closefrom(3), the rewrite
 *   toy spawn-lowlimit  the same limit, a vfork child that closefrom(3)s and _exits, the rewrite
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

static int rewrite(const char *path, int flags) {
    int fd = open(path, flags);
    if (fd < 0) { perror("open"); return 1; }
    if (write(fd, "new\n", 4) != 4) { perror("write"); return 1; }
    return close(fd);
}

static int lower_limit(void) {
    struct rlimit r;
    if (getrlimit(RLIMIT_NOFILE, &r) != 0) return 1;
    r.rlim_cur = 256;
    return setrlimit(RLIMIT_NOFILE, &r);
}

int main(int argc, char **argv) {
    const char *d = getenv("TOY_STATE");
    if (!d) d = "./state";
    char key[1024];
    snprintf(key, sizeof(key), "%s/key.json", d);
    /* Not a constant: the compiler would fold it and call plain open, never __open_2. */
    int flags = O_WRONLY | (argc > 1 ? O_TRUNC : 0);
    const char *mode = argc > 1 ? argv[1] : "";
    if (strcmp(mode, "init") == 0) {
        int fd = open(key, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0 || write(fd, "old\n", 4) != 4) return 1;
        return close(fd);
    }
    if (strcmp(mode, "sweep") == 0) closefrom(3);
    if (strcmp(mode, "sweep-range") == 0 && close_range(3, ~0U, 0) != 0) { perror("close_range"); return 1; }
    if (strcmp(mode, "sweep-lowlimit") == 0) {
        if (lower_limit() != 0) { perror("setrlimit"); return 1; }
        closefrom(3);
    }
    if (strcmp(mode, "spawn-lowlimit") == 0) {
        if (lower_limit() != 0) { perror("setrlimit"); return 1; }
        pid_t pid = vfork();
        if (pid < 0) { perror("vfork"); return 1; }
        if (pid == 0) {
            closefrom(3);
            _exit(0);
        }
        int status = 0;
        if (waitpid(pid, &status, 0) != pid || !WIFEXITED(status) || WEXITSTATUS(status) != 0) return 1;
    }
    return rewrite(key, flags);
}
