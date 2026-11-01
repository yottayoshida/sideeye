/* A library whose constructor draws randomness before the program's main: linked into
 * toy-ctorrand, it is initialised ahead of the preloaded libraries of an exec'd image. */
#include <sys/random.h>
#include <unistd.h>

__attribute__((constructor)) static void draw_early(void) {
    unsigned char b[8];
    if (getrandom(b, sizeof b, 0) != (ssize_t)sizeof b) _exit(89);
}
