/* Sleeps for argv[1] seconds. An operation the shim can enter on macOS, where /bin/sleep, an Apple
 * platform binary, sheds it. */
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    sleep((unsigned)atof(argv[1]));
    return 0;
}
