# The criterion-1 fourth-cohort image: the two frozen targets plus what
# the engine and the probes need. Same discipline as cohorts 1-3: the apt
# layer is pinned by BUILD, not by manifest — the base tag is mutable and
# the apt installs are unversioned, so a rebuild may drift. The two
# targets are exact-pinned (below), so target drift is not possible
# without editing this file or the fetched inputs it re-verifies. What
# actually ran is recorded in probes/*.txt and each target's RUNLOG.
#
# All build inputs are fetched on the HOST by ./fetch-artifacts.sh into
# ./artifacts/ (gitignored): this machine's TLS-intercepting proxy breaks
# in-container pip/curl certificate verification (measured 2026-08-21,
# cohort-2 image build). apt survives — it is plain HTTP — which is why
# the OCaml toolchain below installs normally.
#
# BOTH targets are BUILT FROM SOURCE here, for two different disclosed
# reasons the PROTOCOL carries:
#   - himalaya's distributed binaries are musl-static cross-builds, which
#     LD_PRELOAD cannot enter; the self-build is glibc-dynamic with the
#     same v2.1.0 tree and the same default feature set — the delta to
#     the distributed artifact is linkage, not features.
#   - unison publishes no aarch64-linux binary at all (measured
#     2026-08-23: macOS arm64 and x86_64/i386 Linux only), so on this
#     architecture a build from the pinned source IS the install path.
# Each runtime binary is asserted dynamically linked against glibc; a
# silently-static build fails at image build, not at the first probe.
#
# arm64-only, on purpose: the rust tarball is aarch64 and the engine this
# cohort mounts is the cross-built aarch64-linux pair. On an x86_64 host
# the version checks fail loudly at build time.

FROM debian:trixie-slim AS build-himalaya

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        xz-utils \
        gcc \
        libc6-dev \
    && rm -rf /var/lib/apt/lists/*
# gcc/libc6-dev: himalaya's default rustls-ring feature compiles C
# sources at build time.

# Rust 1.98.0 (stable, 2026-08-18): the same combined standalone tarball
# and channel-manifest sha256 pin as cohort 3. Only the three components
# a build needs are installed; the toolchain lives and dies in this
# stage — the runtime image carries the himalaya binary, not cargo.
COPY artifacts/rust-1.98.0-aarch64-unknown-linux-gnu.tar.xz /tmp/rust.tar.xz
RUN echo "ac9283184301aeed06ecc9f5aa4c1be7041e18a1b197b6cb6c5d162d98f566da  /tmp/rust.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/rust.tar.xz -C /tmp \
    && /tmp/rust-1.98.0-aarch64-unknown-linux-gnu/install.sh --prefix=/usr/local \
        --components=rustc,cargo,rust-std-aarch64-unknown-linux-gnu \
    && rm -rf /tmp/rust.tar.xz /tmp/rust-1.98.0-aarch64-unknown-linux-gnu \
    && cargo --version && rustc --version

# himalaya v2.1.0, built offline from the commit-verified tree. The tree
# is re-verified here against the digest fetch-artifacts.sh computed from
# the checkout whose HEAD matched the pinned tag commit (git metadata is
# excluded on both sides, and .dockerignore keeps it out of the context).
# The verification runs BEFORE the vendor config is written into the
# tree, so the bytes verified are the bytes that were pinned. cargo then
# re-verifies every vendored crate against the checksums in the tree's
# own committed Cargo.lock — a tampered vendor/ fails the offline build.
COPY artifacts/himalaya-src /build/himalaya-src
COPY artifacts/vendor /build/vendor
COPY artifacts/himalaya-src.digest /build/himalaya-src.digest
RUN cd /build/himalaya-src \
    && got=$(find . -type f -not -path './.git/*' -print0 | sort -z \
        | xargs -0 -n 64 sha256sum | sha256sum | cut -d' ' -f1) \
    && want=$(cat /build/himalaya-src.digest) \
    && { [ "$got" = "$want" ] \
        || { echo "himalaya-src digest mismatch: got $got wanted $want"; exit 1; }; } \
    && mkdir -p .cargo \
    && printf '[source.crates-io]\nreplace-with = "vendored-sources"\n\n[source.vendored-sources]\ndirectory = "/build/vendor"\n' \
        > .cargo/config.toml \
    && cargo build --release --locked --offline \
    && ./target/release/himalaya --version

FROM debian:trixie-slim AS build-unison

RUN apt-get update && apt-get install -y --no-install-recommends \
        ocaml \
        gcc \
        libc6-dev \
        make \
    && rm -rf /var/lib/apt/lists/*
# INSTALL.md's prerequisites: a C99 compiler, OCaml >= 4.08 (trixie ships
# 5.3.0), make. lablgtk3 is deliberately absent — its presence is what
# triggers the GUI build, so leaving it out selects the text UI.

COPY artifacts/unison-src /build/unison-src
COPY artifacts/unison-src.digest /build/unison-src.digest
RUN cd /build/unison-src \
    && got=$(find . -type f -not -path './.git/*' -print0 | sort -z \
        | xargs -0 -n 64 sha256sum | sha256sum | cut -d' ' -f1) \
    && want=$(cat /build/unison-src.digest) \
    && { [ "$got" = "$want" ] \
        || { echo "unison-src digest mismatch: got $got wanted $want"; exit 1; }; } \
    && make \
    && ./src/unison -version

FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        strace \
        python3 \
        ca-certificates \
        libfaketime \
        gcc \
        libc6-dev \
    && rm -rf /var/lib/apt/lists/*
# gcc/libc6-dev: the probe harness compiles its toys, the condition-8
# visibility logger, and pin-getpid.c in-container. python3: the
# preflight analyser. libfaketime: carried from cohort 2 (#200) so a
# determinism wall CAN be lifted by declared apparatus without
# rebuilding the image — using it is a per-target owner decision
# (PROTOCOL: apparatus policy), never a default. No pip layer: cohort
# 4's slate carries no Python target.

# The self-built targets, and the assertion that justifies self-building:
# each binary must be dynamically linked against glibc (himalaya's
# distributed musl-static artifact is exactly what the shim cannot
# enter, and a static unison would reproduce that wall by accident).
COPY --from=build-himalaya /build/himalaya-src/target/release/himalaya /usr/local/bin/himalaya
COPY --from=build-unison /build/unison-src/src/unison /usr/local/bin/unison
RUN himalaya --version \
    && ldd /usr/local/bin/himalaya \
    && ldd /usr/local/bin/himalaya | grep -q 'libc\.so\.6' \
    && unison -version \
    && ldd /usr/local/bin/unison \
    && ldd /usr/local/bin/unison | grep -q 'libc\.so\.6'
