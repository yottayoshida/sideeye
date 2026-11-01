/*   toy init     key.json holds "old"
 *   toy rotate   __open(key.json, O_WRONLY|O_TRUNC), __write "new", __close
 *   toy pwrite   __open(key.json, O_WRONLY|O_TRUNC), __pwrite64 "new" at 0, __close
 *   toy stdio    _IO_fopen(key.json, "w"), fputs "new", _IO_fflush, _IO_fclose
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

extern int __open(const char *path, int flags, ...);
extern ssize_t __write(int fd, const void *buf, size_t n);
extern ssize_t __pwrite64(int fd, const void *buf, size_t n, off64_t off);
extern int __close(int fd);
extern FILE *_IO_fopen(const char *path, const char *mode);
extern int _IO_fflush(FILE *stream);
extern int _IO_fclose(FILE *stream);

int main(int argc, char **argv) {
    const char *d = getenv("TOY_STATE");
    if (!d) d = "./state";
    char key[1024];
    snprintf(key, sizeof(key), "%s/key.json", d);
    const char *mode = argc > 1 ? argv[1] : "";
    if (strcmp(mode, "init") == 0) {
        int fd = open(key, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0 || write(fd, "old\n", 4) != 4) return 1;
        return close(fd);
    }
    if (strcmp(mode, "rotate") == 0 || strcmp(mode, "pwrite") == 0) {
        int fd = __open(key, O_WRONLY | O_TRUNC);
        if (fd < 0) { perror("__open"); return 1; }
        ssize_t n = strcmp(mode, "rotate") == 0 ? __write(fd, "new\n", 4) : __pwrite64(fd, "new\n", 4, 0);
        if (n != 4) { perror("write"); return 1; }
        return __close(fd);
    }
    if (strcmp(mode, "stdio") == 0) {
        FILE *f = _IO_fopen(key, "w");
        if (!f) { perror("_IO_fopen"); return 1; }
        if (fputs("new\n", f) < 0 || _IO_fflush(f) != 0) return 1;
        return _IO_fclose(f);
    }
    fprintf(stderr, "usage: toy init|rotate|pwrite|stdio\n");
    return 2;
}
