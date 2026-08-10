# Linux ground for the v0.1 spike.
#
# The image carries what the *toys* need to be built (a C compiler, rustc) and the
# oracle (strace). It deliberately does not carry Zig: sideeye and its shim are
# cross-compiled from the host with `zig build -Dtarget=…` and mounted in, which keeps
# one toolchain version in play instead of two.
FROM rust:1-slim-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc libc6-dev strace \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work
