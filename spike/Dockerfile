# Linux ground for the v0.1 spike.
#
# The image carries what the *toys* need to be built (a C compiler, rustc), the oracle
# (strace) and a JSON parser (python3). It deliberately does not carry Zig: sideeye and
# its shim are cross-compiled from the host with `zig build -Dtarget=…` and mounted in,
# which keeps one toolchain version in play instead of two.
#
# python3 is not decoration: the acceptance suite reads the machine-readable report with
# a real parser, because grep succeeds on a truncated document and that is exactly the
# failure the check exists to catch.
FROM rust:1-slim-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc libc6-dev strace python3 \
 && rm -rf /var/lib/apt/lists/*

# Blind-hunt candidates (ADR 0012, between the seals): pinned installs, in the sealed
# priority order. apt versions are bookworm's; pip versions are pinned exactly. The
# trusted-host flags are the container-network TLS gotcha this repo has hit before —
# pip's TLS is MITM'd by the sandbox while apt's plain http passes.
# man-db and python3-pip serve the permitted-sources phase (--help / man only).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      abook hledger man-db python3-pip \
 && rm -rf /var/lib/apt/lists/*
RUN pip3 install --break-system-packages \
      --trusted-host pypi.org --trusted-host files.pythonhosted.org \
      topydo==0.14 khard==0.21.0 khal==0.14.0

WORKDIR /work
