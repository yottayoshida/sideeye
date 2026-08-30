/* R2 の新規 Critical を実際に組む:
 *   親: libc で普通に1つ書く（記録される → state_changed_without_ops を発火させない）
 *   子: syscall(SYS_fork) で作り、getpid() の変化で自分が子だと判別し、syscall 直で state に書く
 * shim が子の生成も子の書き込みも見なければ、preflight は「accepted」と答えるはず。 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

int main(void) {
    const char *dir = getenv("PROBE_STATE"); if (!dir) dir = "./state";
    char ppath[1024], cpath[1024];
    snprintf(ppath, sizeof(ppath), "%s/from-parent", dir);
    snprintf(cpath, sizeof(cpath), "%s/from-raw-child", dir);

    int pfd = open(ppath, O_CREAT | O_WRONLY | O_TRUNC, 0600);
    if (pfd < 0) { perror("parent open"); return 1; }
    if (write(pfd, "parent\n", 7) != 7) { perror("parent write"); return 1; }
    close(pfd);

    long before = syscall(SYS_getpid);   /* libc のキャッシュを回避 */
    long r = syscall(SYS_fork);
    if (r < 0) { fprintf(stderr, "raw fork failed\n"); return 3; }
    if (syscall(SYS_getpid) != before) {
        /* 子。libc を一切通さずに書く */
        long fd = syscall(SYS_open, cpath, O_CREAT | O_WRONLY | O_TRUNC, 0600);
        if (fd >= 0) { syscall(SYS_write, fd, "rawchild\n", 9); syscall(SYS_close, fd); }
        syscall(SYS_exit, 0);
        _exit(0);
    }
    int st; waitpid((pid_t)r, &st, 0);
    fprintf(stderr, "parent done, child pid=%ld\n", r);
    return 0;
}
