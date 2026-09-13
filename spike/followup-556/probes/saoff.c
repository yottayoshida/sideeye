/* glibc's struct sigaction, as a caller of libc sigaction() lays it out: where sa_mask sits and
 * how big it is, and that SIGSYS's bit is where sigaddset puts it. */
#define _GNU_SOURCE
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    struct sigaction sa;
    printf("sizeof(struct sigaction)=%zu offsetof(sa_handler)=%zu offsetof(sa_mask)=%zu sizeof(sa_mask)=%zu offsetof(sa_flags)=%zu",
           sizeof sa, offsetof(struct sigaction, sa_handler), offsetof(struct sigaction, sa_mask), sizeof sa.sa_mask,
           offsetof(struct sigaction, sa_flags));
#ifdef __x86_64__
    printf(" offsetof(sa_restorer)=%zu", offsetof(struct sigaction, sa_restorer));
#endif
    printf("\n");
    memset(&sa, 0, sizeof sa);
    sigaddset(&sa.sa_mask, SIGSYS);
    unsigned char *b = (unsigned char *)&sa;
    for (size_t i = 0; i < sizeof sa; i++) if (b[i]) printf("SIGSYS (%d) set in byte %zu of the struct, value 0x%02x\n", SIGSYS, i, b[i]);
    return 0;
}
