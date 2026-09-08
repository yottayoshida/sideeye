/* The spawn+wait that does not go through the PLT: system() forks and waits inside libc. */
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    const char *dir = argc > 1 ? argv[1] : "/w/state";
    char cmd[1024];
    snprintf(cmd, sizeof cmd, "printf s > %s/s", dir);
    if (system(cmd) != 0) return 1;
    return 0;
}
