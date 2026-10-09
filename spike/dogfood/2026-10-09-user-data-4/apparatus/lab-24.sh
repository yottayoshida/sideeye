#!/bin/sh
# Lab 24: does the shim make std::thread fail when the thread is started from a shared library's
# static constructor, before the shim's own initialisation? iconvert aborts with std::system_error
# "Unknown error -1" under the shim with no clone reaching the kernel (lab-23.txt), and the shim's
# callPthreadCreate returns -1 when the real pthread_create was never resolved (shim/src/common.zig).
# Three programs: a thread started in main; one started by a global object in a shared library the
# executable links; and a std::ifstream of /dev/urandom read by such an object (ROOT's abort,
# lab-16.txt). Each by hand and with only the shim preloaded.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1009 sh /ap/lab-24.sh
set -u
SHIM=$(dirname "$(cat /install.path)")/libsideeye_shim.so
mkdir -p /tmp/l24 && cd /tmp/l24
cat > main.cc <<'CC'
#include <thread>
#include <cstdio>
int main() { std::thread t([]{ std::puts("thread in main: ran"); }); t.join(); return 0; }
CC
cat > lib.cc <<'CC'
#include <thread>
#include <cstdio>
struct Pool { Pool() { std::thread t([]{ std::puts("thread in a library constructor: ran"); }); t.join(); } };
static Pool pool;
CC
cat > uses.cc <<'CC'
#include <cstdio>
int main() { std::puts("main reached"); return 0; }
CC
c++ -O0 -o main main.cc -pthread && c++ -O0 -shared -fPIC -o libpool.so lib.cc -pthread && \
  c++ -O0 -o uses uses.cc -L. -Wl,-rpath,/tmp/l24 -Wl,--no-as-needed -lpool -pthread || { echo "compile failed"; exit 1; }
cat > rnd.cc <<'CC'
#include <fstream>
#include <cstdio>
struct Seed { Seed() { std::ifstream u{"/dev/urandom"}; char b[16]; u.read(b, 16); std::printf("ifstream in a library constructor: %s\n", u.good() ? "read 16 bytes" : "FAILED"); } };
static Seed seed;
CC
c++ -O0 -shared -fPIC -o librnd.so rnd.cc && c++ -O0 -o usesrnd uses.cc -L. -Wl,-rpath,/tmp/l24 -Wl,--no-as-needed -lrnd || { echo "compile failed"; exit 1; }
for mode in plain shim; do
    if [ "$mode" = shim ]; then P="$SHIM"; else P=""; fi
    echo "== $mode"
    LD_PRELOAD=$P ./main; echo "main exit $?"
    LD_PRELOAD=$P ./uses; echo "uses exit $?"
    LD_PRELOAD=$P ./usesrnd; echo "usesrnd exit $?"
done
