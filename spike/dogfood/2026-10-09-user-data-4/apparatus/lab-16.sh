#!/bin/sh
# Lab 16: under the shim preloaded alone (no engine), does a read-only open of /dev/urandom reach the
# kernel? rootrm (ROOT 6.40.04 from conda-forge, built R__USE_URANDOM) aborts under the shim at
# TUUID.cxx:171 because GetCryptoRandom's `std::ifstream{"/dev/urandom"}` fails, and its strace shows
# no openat of /dev/urandom (transcripts/lab-16/rootrm-preload.strace, -plain.strace). Four spellings:
# open(2), fopen(3), std::ifstream, and Python's open, each with and without the shim.
#   docker run --rm --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-16.sh
set -u
O=/out/lab-16; mkdir -p "$O"
SHIM=$(dirname "$(cat /install.path)")/libsideeye_shim.so
mkdir -p /tmp/l16 && cd /tmp/l16
cat > c.c <<'C'
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
int main(void) {
    unsigned char b[16];
    int fd = open("/dev/urandom", O_RDONLY);
    printf("open: fd=%d read=%zd\n", fd, fd >= 0 ? read(fd, b, 16) : -1);
    FILE *f = fopen("/dev/urandom", "r");
    printf("fopen: %s read=%zu\n", f ? "ok" : "NULL", f ? fread(b, 1, 16, f) : 0);
    f = fopen("/dev/urandom", "rb");
    printf("fopen rb: %s\n", f ? "ok" : "NULL");
    return 0;
}
C
cat > x.cc <<'CC'
#include <fstream>
#include <iostream>
int main() {
    char b[16];
    std::ifstream u{"/dev/urandom"};
    std::cout << "ifstream open: " << (u ? "ok" : "FAILED") << std::endl;
    u.read(b, 16);
    std::cout << "ifstream read good: " << u.good() << std::endl;
    std::ifstream r{"/etc/hostname"};
    std::cout << "ifstream on a regular file: " << (r ? "ok" : "FAILED") << std::endl;
    return 0;
}
CC
cc -O0 -o c c.c && c++ -O0 -o x x.cc || { echo "compile failed"; exit 1; }
for mode in plain shim; do
    echo "== $mode"
    if [ "$mode" = shim ]; then P="$SHIM"; else P=""; fi
    LD_PRELOAD=$P ./c
    LD_PRELOAD=$P ./x
    LD_PRELOAD=$P python3 -c 'f=open("/dev/urandom","rb"); print("python open:", len(f.read(16)))'
    LD_PRELOAD=$P strace -f -qq -e trace=openat,open -o "$O/x-$mode.strace" ./x > /dev/null 2>&1
    echo "strace of x ($mode): $(grep -c urandom "$O/x-$mode.strace") openat of /dev/urandom"
done
