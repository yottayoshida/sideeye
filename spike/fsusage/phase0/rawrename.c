/* 反証チェック3の前提確認: libc の rename() を通らず syscall(2) 直で rename できるか。
 * shim は syscall() を interpose しない(Linux 側の実測と同じ機構)ので、
 * これが動くなら「shim に見えない rename」の toy が成立する。 */
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "usage: rawrename <src> <dst>\n"); return 2; }
    long rc = syscall(SYS_rename, argv[1], argv[2]);
    fprintf(stderr, "syscall(SYS_rename) = %ld\n", rc);
    return rc == 0 ? 0 : 1;
}
