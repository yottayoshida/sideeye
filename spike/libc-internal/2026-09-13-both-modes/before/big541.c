/* #541 plan probe: dprintf into the state, small and past glibc's 8192-byte buffer.
 * State directory from TOY_STATE, the way spike/toys/toy_mkstemp.c reads it.
 *   big541 init | small | large */
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *state_dir(void) {
    const char *d = getenv("TOY_STATE");
    return (d && *d) ? d : "./state";
}

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    char path[1024];
    if (strcmp(argv[1], "init") == 0) {
        mkdir(state_dir(), 0755);
        snprintf(path, sizeof path, "%s/key.json", state_dir());
        FILE *f = fopen(path, "w");
        if (!f) return 1;
        fputs("key=1\n", f);
        fclose(f);
        return 0;
    }
    size_t n = strcmp(argv[1], "large") == 0 ? 8999 : 12;
    char *body = malloc(n + 1);
    if (!body) return 1;
    memset(body, 'a', n - 1);
    body[n - 1] = '\n';
    body[n] = 0;
    snprintf(path, sizeof path, "%s/log.txt", state_dir());
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) { perror("open"); return 1; }
    if (dprintf(fd, "%s", body) < 0) { perror("dprintf"); return 1; }
    if (close(fd) != 0) { perror("close"); return 1; }
    return 0;
}
