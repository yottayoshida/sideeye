/* toy-stack: how much of a thread's stack the target spends, with and without the shim
 * (#555). acceptance runs it bare and under a recording shim and compares.
 *
 * Usage: toy-stack <directory>
 *
 * Every thread it starts does the same interposed work inside <directory>: open
 * /dev/null, create a file, write it (write and pwritev2), close it, rename it, unlink it,
 * make and remove a directory, and exec a path that does not exist. The rename walks the
 * shim's two-path chain; the failed exec walks the exec carry, which rebuilds the whole
 * environment and then returns.
 *
 * The depth is what the calls reach below the thread's own frame, and nothing else. The
 * number is a high-water mark, so anything deeper than the shim's own chain hides it, and
 * this was measured hiding it twice (#555): the first version formatted its paths with
 * snprintf in the thread, and the bare run's deepest point was snprintf's (review); the
 * second patterned the stack once, before the thread started, and on x86_64 the thread's
 * own start-up and exit went deeper than the calls — a ReleaseSafe shim measured +0.
 * So the paths are built in main, and the thread re-patterns everything below its stack
 * pointer immediately before the calls and reads it back immediately after.
 *
 * Output, one fact per line:
 *   shim=yes|no        whether libsideeye_shim is mapped into this process
 *   sigframe=<bytes>   the kernel's minimum signal stack size (AT_MINSIGSTKSZ), which a
 *                      trapped write under --observe syscalls adds on top of the shim's own;
 *                      printed before any thread starts, so a thread that dies cannot take
 *                      it with it
 *   min=<bytes> ok     a thread whose stack is sysconf(_SC_THREAD_STACK_MIN) ran the work
 *                      to the end (or "create <error>" / "work <step>" when it did not)
 *   depth=<bytes>      how far below the thread's own frame the same calls reached, in a
 *                      256 KiB stack the toy supplied itself
 *
 * Exits 0 when both threads ran the work to the end. The output is the evidence; the exit
 * status only says whether the work survived. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/auxv.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <unistd.h>

#ifndef AT_MINSIGSTKSZ
#define AT_MINSIGSTKSZ 51
#endif

extern char **environ;

static char path_a[4096], path_b[4096], path_d[4096];
static char *const exec_argv[] = {"toy-stack-exec", NULL};
static struct iovec iov = {"y\n", 2};
/* The depth thread's stack; NULL while the minimum-stack thread runs. */
static unsigned char *stk_lo;
static size_t touched;

static inline unsigned char *stack_pointer(void) {
    unsigned char *sp;
#if defined(__x86_64__)
    __asm__ volatile("mov %%rsp, %0" : "=r"(sp));
#elif defined(__aarch64__)
    __asm__ volatile("mov %0, sp" : "=r"(sp));
#else
#error "toy-stack reads its stack pointer on x86_64 and aarch64 only"
#endif
    return sp;
}

static void *work(void *res) {
    /* Below the stack pointer, with a little room: nothing of this frame lives there, and
     * the loop makes no call, so writing it moves nothing this function still needs. */
    volatile unsigned char *top = NULL, *q;
    if (stk_lo) {
        top = stack_pointer() - 16;
        for (q = stk_lo; q < top; q++) *q = 0xA5;
    }
    int step = 0;
    int n = open("/dev/null", O_RDONLY);
    if (n >= 0) close(n);
    int fd = open(path_a, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) step = 1;
    else if (write(fd, "x\n", 2) != 2) step = 2;
    else if (pwritev2(fd, &iov, 1, 2, 0) != 2) step = 3;
    if (fd >= 0 && close(fd) != 0 && step == 0) step = 4;
    if (step == 0 && rename(path_a, path_b) != 0) step = 5;
    if (step == 0 && unlink(path_b) != 0) step = 6;
    if (step == 0 && mkdir(path_d, 0755) != 0) step = 7;
    if (step == 0 && rmdir(path_d) != 0) step = 8;
    if (step == 0 && (execve("/nonexistent/toy-stack", exec_argv, environ) != -1 || errno != ENOENT)) step = 9;
    if (top) {
        for (q = stk_lo; q < top && *q == 0xA5; q++)
            ;
        touched = (size_t)(top - q);
    }
    *(int *)res = step;
    return NULL;
}

static int shim_mapped(void) {
    FILE *f = fopen("/proc/self/maps", "r");
    if (!f) return -1;
    char line[4096];
    int found = 0;
    while (fgets(line, sizeof line, f))
        if (strstr(line, "libsideeye_shim")) found = 1;
    fclose(f);
    return found;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: toy-stack <directory>\n");
        return 64;
    }
    if ((size_t)snprintf(path_a, sizeof path_a, "%s/stack-a.txt", argv[1]) >= sizeof path_a
        || (size_t)snprintf(path_b, sizeof path_b, "%s/stack-b.txt", argv[1]) >= sizeof path_b
        || (size_t)snprintf(path_d, sizeof path_d, "%s/stack-d", argv[1]) >= sizeof path_d) {
        fprintf(stderr, "toy-stack: directory name too long\n");
        return 64;
    }
    /* Unbuffered: a thread that overflows its stack kills the process, and the lines
     * already printed are what says how far it got. */
    setvbuf(stdout, NULL, _IONBF, 0);
    int failed = 0;

    int m = shim_mapped();
    printf("shim=%s\n", m == 1 ? "yes" : m == 0 ? "no" : "unknown");
    printf("sigframe=%lu\n", getauxval(AT_MINSIGSTKSZ));

    /* The platform's minimum stack. glibc refuses a smaller one outright, and the
     * refusal is monotonic in the size, so this one row stands for every size above it. */
    size_t min = (size_t)sysconf(_SC_THREAD_STACK_MIN);
    pthread_attr_t at;
    pthread_t t;
    int res = -1;
    pthread_attr_init(&at);
    int rc = pthread_attr_setstacksize(&at, min);
    if (rc == 0) rc = pthread_create(&t, &at, work, &res);
    if (rc != 0) {
        printf("min=%zu create %s\n", min, strerror(rc));
        failed = 1;
    } else {
        pthread_join(t, NULL);
        if (res == 0) printf("min=%zu ok\n", min);
        else {
            printf("min=%zu work %d\n", min, res);
            failed = 1;
        }
    }
    pthread_attr_destroy(&at);

    /* The depth: a stack of our own, so the thread knows where its bottom is and can
     * pattern it (work, above). */
    const size_t sz = 256 * 1024;
    unsigned char *stk = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_STACK, -1, 0);
    if (stk == MAP_FAILED) {
        printf("depth=unknown mmap %s\n", strerror(errno));
        return 1;
    }
    stk_lo = stk;
    pthread_attr_init(&at);
    res = -1;
    rc = pthread_attr_setstack(&at, stk, sz);
    if (rc == 0) rc = pthread_create(&t, &at, work, &res);
    if (rc != 0) {
        printf("depth=unknown create %s\n", strerror(rc));
        failed = 1;
    } else {
        pthread_join(t, NULL);
        printf("depth=%zu\n", touched);
        if (res != 0) {
            printf("depth-work %d\n", res);
            failed = 1;
        }
    }
    pthread_attr_destroy(&at);
    return failed;
}
