// Every line is an answer the kernel wrote back, so a pointer command whose argument the
// shim cut prints another one than a plain run does.
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/param.h>
#include <unistd.h>

static void say(const char *what, int rc) {
    printf("%s rc=%d errno=%s\n", what, rc, rc == -1 ? strerror(errno) : "-");
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: toy_fcntl <file to create>\n");
        return 2;
    }
    int fd = open(argv[1], O_RDWR | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        perror("open");
        return 1;
    }
    if (write(fd, "abc\n", 4) != 4) return 1;

    int fl = fcntl(fd, F_GETFL);
    printf("getfl accmode=%d append=%d\n", fl & O_ACCMODE, (fl & O_APPEND) != 0);
    say("setfl", fcntl(fd, F_SETFL, fl | O_APPEND));
    fl = fcntl(fd, F_GETFL);
    printf("getfl append=%d\n", (fl & O_APPEND) != 0);

    char path[MAXPATHLEN];
    memset(path, 0, sizeof path);
    say("getpath", fcntl(fd, F_GETPATH, path));
    const char *base = strrchr(path, '/');
    printf("getpath base=%s\n", base ? base + 1 : "(none)");

    struct flock lk;
    memset(&lk, 0, sizeof lk);
    lk.l_type = F_WRLCK;
    lk.l_whence = SEEK_SET;
    say("setlk", fcntl(fd, F_SETLK, &lk));
    struct flock probe;
    memset(&probe, 0, sizeof probe);
    probe.l_type = F_WRLCK;
    probe.l_whence = SEEK_SET;
    say("getlk", fcntl(fd, F_GETLK, &probe));
    printf("getlk type=%s\n", probe.l_type == F_UNLCK ? "unlck" : probe.l_type == F_WRLCK ? "wrlck" : "other");

    int dup = fcntl(fd, F_DUPFD, 100);
    printf("dupfd atleast100=%d\n", dup >= 100);
    say("setfd", fcntl(dup, F_SETFD, FD_CLOEXEC));
    printf("getfd cloexec=%d\n", (fcntl(dup, F_GETFD) & FD_CLOEXEC) != 0);

    say("fullfsync", fcntl(fd, F_FULLFSYNC));
    say("barrierfsync", fcntl(fd, F_BARRIERFSYNC));
    say("nocache", fcntl(fd, F_NOCACHE, 1));
    say("badfd", fcntl(-1, F_GETFL));
    say("badcmd", fcntl(fd, 99999));
    return 0;
}
