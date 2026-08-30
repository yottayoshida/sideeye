/*
 * 測定1: fs_usage は高負荷で行を落とすか。
 *
 * 状態ディレクトリのファイル1つに 1 バイトの write(2) を N 回発行するだけ。
 * ファイルシステムの churn（作成・改名・削除）を混ぜないのは、測りたいのが
 * 「イベントの量」であって「操作の種類」ではないため。
 *
 * 期待:
 *   shim の記録   = 1 (open) + N (write)
 *   fs_usage の行 = 同じ N 本の write 行（+ open 1 本 + observer の影）
 * 一致し続けるか、どの N から割れるかを見る。
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char *state_dir(void) {
    const char *d = getenv("PROBE_STATE");
    return (d && *d) ? d : "./state";
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: loadprobe <N>\n"); return 2; }
    long n = strtol(argv[1], NULL, 10);
    if (n <= 0) { fprintf(stderr, "N must be positive\n"); return 2; }

    char path[1024];
    snprintf(path, sizeof(path), "%s/load", state_dir());

    int fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0600);
    if (fd < 0) { perror("open"); return 1; }

    for (long i = 0; i < n; i++) {
        if (write(fd, "x", 1) != 1) { perror("write"); return 1; }
    }
    if (close(fd) != 0) { perror("close"); return 1; }

    /* 地上真実: 実際に何バイト書けたかは、呼び出し側がファイルサイズで確認できる */
    fprintf(stderr, "wrote %ld bytes to %s\n", n, path);
    return 0;
}
