/*
 * 測定2: macOS で mkstemp(3) の創成が shim に見えるか。
 *
 * 差分だけが創成手段になるように、2つのモードを1つのバイナリに入れる。
 * どちらも「状態ディレクトリにファイルを1つ作り、13 バイト書き、閉じる」で、
 * 違うのは創成が open(2) を通るか mkstemp(3) の内側かだけ。
 *
 *   open     : open(O_CREAT|O_RDWR|O_EXCL) + write + close   ← 陽性対照
 *   mkstemp  : mkstemp() + write + close                      ← 被験
 *
 * 観測される状態変更操作の数が open で N、mkstemp で N-1 なら、
 * 差の1つが「見えていない創成」。Linux では #39 で実測済み
 * (spike/cohort4/mkstemp-class.txt)。macOS は機構からの推論のままだった。
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
    if (argc < 2) { fprintf(stderr, "usage: mkprobe open|mkstemp\n"); return 2; }

    char path[1024];
    int fd;

    if (!strcmp(argv[1], "open")) {
        /* unlink は置かない。mkstemp 側に対応する操作が無く、差が創成手段だけで
         * なくなるため（最初の測定でこの非対称を自分で入れ、差が 1 でなく 2 になった） */
        snprintf(path, sizeof(path), "%s/via-open", state_dir());
        fd = open(path, O_CREAT | O_RDWR | O_EXCL, 0600);
        if (fd < 0) { perror("open"); return 1; }
    } else if (!strcmp(argv[1], "mkstemp")) {
        snprintf(path, sizeof(path), "%s/via-mkstemp-XXXXXX", state_dir());
        fd = mkstemp(path);
        if (fd < 0) { perror("mkstemp"); return 1; }
    } else {
        fprintf(stderr, "unknown mode\n"); return 2;
    }

    /* 両モードで同一の書き込み。これは自分で発行するので必ず見えるはず。
     * PROBE_NOWRITE=1 で書き込みを外すと、観測されるのは創成だけになる */
    if (!getenv("PROBE_NOWRITE"))
        if (write(fd, "hello, world\n", 13) != 13) { perror("write"); return 1; }
    if (close(fd) != 0) { perror("close"); return 1; }

    /* 作られたことの地上真実: 呼び出し側が確認できるようにパスを出す */
    fprintf(stderr, "created: %s\n", path);
    return 0;
}
