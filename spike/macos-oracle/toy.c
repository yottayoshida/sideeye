/* A fixed, self-accounting sequence of state-directory operations (#181).
 *
 * Every candidate oracle is judged against the same ground truth: this
 * program prints each operation to stdout BEFORE performing it, so a
 * capture can be checked for presence and first-appearance order of the
 * marker names without trusting the observer under test.
 *
 * The marker tokens are chosen so none is a substring of another in the
 * order check (marker-a.tmp / marker-b / marker-c), and they sit at the
 * END of their paths, because some observers truncate long paths from the
 * left and a token in the middle would vanish before the defect is real.
 */
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

static void say(const char *s) {
    printf("op %s\n", s);
    fflush(stdout);
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: toy <state-dir>\n");
        return 2;
    }
    char p1[1024], p2[1024], p3[1024], p4[1024], p5[1024];
    snprintf(p1, sizeof p1, "%s/marker-a.tmp", argv[1]);
    snprintf(p2, sizeof p2, "%s/marker-a", argv[1]);
    snprintf(p3, sizeof p3, "%s/marker-b", argv[1]);
    snprintf(p4, sizeof p4, "%s/marker-sub", argv[1]);
    snprintf(p5, sizeof p5, "%s/marker-sub/marker-c", argv[1]);

    say("open+write marker-a.tmp");
    int fd = open(p1, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return 3;
    write(fd, "payload", 7);
    close(fd);

    say("rename marker-a.tmp -> marker-a");
    rename(p1, p2);

    say("open+write marker-b");
    fd = open(p3, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return 3;
    write(fd, "doomed", 6);
    close(fd);

    say("unlink marker-b");
    unlink(p3);

    say("mkdir marker-sub");
    mkdir(p4, 0755);

    say("open+write marker-sub/marker-c");
    fd = open(p5, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return 3;
    write(fd, "nested", 6);
    close(fd);

    say("done");
    return 0;
}
