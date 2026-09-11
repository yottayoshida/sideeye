#!/bin/sh
# #555: loading the shim refuses a thread whose stack is smaller than the shim's static TLS.
# Run in the image with the release tarball mounted at /se. No Sideeye run is involved —
# only the preload — so what this shows is a property of loading the library.
#
#   docker run --rm -v <tarball dir>:/se:ro sideeye-dogfood:2026-09-11 sh /hostap/probe-tls.sh
set -u
cat > /tmp/t.c <<'EOF'
#include <pthread.h>
#include <stdio.h>
#include <string.h>
static void *f(void *a) { return a; }
int main(void) {
    size_t sizes[] = { 128 * 1024, 256 * 1024, 384 * 1024, 512 * 1024 };
    for (int i = 0; i < 4; i++) {
        pthread_attr_t at; pthread_t t;
        pthread_attr_init(&at);
        pthread_attr_setstacksize(&at, sizes[i]);
        int rc = pthread_create(&t, &at, f, NULL);
        printf("stack %4zu KiB: pthread_create %s\n", sizes[i] / 1024, rc ? strerror(rc) : "ok");
        if (!rc) pthread_join(t, NULL);
    }
    return 0;
}
EOF
cc -O0 -o /tmp/t /tmp/t.c -lpthread || exit 2
echo "PTHREAD_STACK_MIN $(getconf PTHREAD_STACK_MIN)"
echo "## plain"; /tmp/t
echo "## LD_PRELOAD=libsideeye_shim.so"; LD_PRELOAD=/se/libsideeye_shim.so /tmp/t
# The real target: node's SIGUSR1 watchdog thread asks for max(32 KiB, PTHREAD_STACK_MIN).
echo "## node -e 1"; node -e 1; echo "rc=$?"
echo "## LD_PRELOAD=libsideeye_shim.so node -e 1"; LD_PRELOAD=/se/libsideeye_shim.so node -e 1; echo "rc=$?"
