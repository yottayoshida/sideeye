#!/bin/sh
# #556 narrowed design: which `how` glibc uses around posix_spawn and pthread_create.
set -u
echo "libc: $(ldd --version 2>&1 | head -1)   arch: $(uname -m)"
cat > /tmp/pt.c <<'C'
#include <pthread.h>
#include <spawn.h>
#include <sys/wait.h>
extern char **environ;
static void *f(void *a) { return a; }
int main(void) {
  pthread_t t; pthread_create(&t, 0, f, 0); pthread_join(t, 0);
  char *argv[] = {"/bin/true", 0}; pid_t p; posix_spawn(&p, "/bin/true", 0, 0, argv, environ); waitpid(p, 0, 0);
  return 0;
}
C
gcc -O0 -o /tmp/pt /tmp/pt.c -lpthread || exit 2
strace -f -e trace=rt_sigprocmask,clone,clone3,execve -o /tmp/pt.txt /tmp/pt > /dev/null 2>&1
grep -v "execve(\"/tmp/pt\"" /tmp/pt.txt | sed 's/0x[0-9a-f]*/ADDR/g' | cut -c1-170
