#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int write_file(const char *path, const char *content, size_t len) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    size_t off = 0;
    while (off < len) {
        ssize_t w = write(fd, content + off, len - off);
        if (w <= 0) { close(fd); return -1; }
        off += (size_t)w;
    }
    if (fsync(fd) != 0) { close(fd); return -1; }
    return close(fd);
}

int main(int argc, char **argv) {
    const char *state = getenv("TOY_STATE");
    if (!state || argc != 2) {
        fprintf(stderr, "usage: TOY_STATE=<dir> toy-listing init|index\n");
        return 2;
    }
    char path[4096];
    char tmp[4096];
    if (snprintf(path, sizeof path, "%s/index", state) >= (int)sizeof path) return 2;
    if (snprintf(tmp, sizeof tmp, "%s/index.tmp", state) >= (int)sizeof tmp) return 2;

    if (strcmp(argv[1], "init") == 0) {
        if (mkdir(state, 0755) != 0 && errno != EEXIST) return 2;
        static const char *names[] = { "e", "d", "c", "b", "a" };
        for (size_t i = 0; i < sizeof names / sizeof names[0]; i++) {
            char p[4096];
            if (snprintf(p, sizeof p, "%s/%s", state, names[i]) >= (int)sizeof p) return 2;
            if (write_file(p, "x\n", 2) != 0) return 2;
        }
        return write_file(path, "none\n", 5) == 0 ? 0 : 2;
    }

    if (strcmp(argv[1], "index") == 0) {
        DIR *d = opendir(state);
        if (!d) return 2;
        char buf[4096];
        size_t n = 0;
        struct dirent *e;
        /* Not sorted: the order the directory gives is what the index records. */
        while ((e = readdir(d)) != NULL) {
            if (e->d_name[0] == '.' || strcmp(e->d_name, "index") == 0 || strcmp(e->d_name, "index.tmp") == 0) continue;
            size_t len = strlen(e->d_name);
            if (n + len + 1 > sizeof buf) { closedir(d); return 2; }
            memcpy(buf + n, e->d_name, len);
            n += len;
            buf[n++] = '\n';
        }
        closedir(d);
        if (write_file(tmp, buf, n) != 0) return 2;
        return rename(tmp, path) == 0 ? 0 : 2;
    }
    return 2;
}
