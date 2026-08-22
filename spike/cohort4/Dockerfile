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
# cohort-2 image build).
#
# himalaya is BUILT FROM SOURCE here, on purpose and with a disclosure
# the PROTOCOL carries: the distributed binaries are musl-static
# cross-builds, which LD_PRELOAD cannot enter, so the measured binary is
# a glibc-dynamic self-build of the same v2.1.0 tree with the same
# default feature set — the delta to the distributed artifact is linkage,
# not features. The runtime stage asserts the built binary is in fact
# dynamically linked against glibc; a silently-static build fails there,
# not at the first probe.
#
# arm64-only, on purpose: the rust tarball is aarch64 and the engine this
# cohort mounts is the cross-built aarch64-linux pair. On an x86_64 host
# the version checks fail loudly at build time.

FROM debian:trixie-slim AS build

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

FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        strace \
        python3 \
        python3-pip \
        ca-certificates \
        libfaketime \
        gcc \
        libc6-dev \
    && rm -rf /var/lib/apt/lists/*
# gcc/libc6-dev: the probe harness compiles its toys and the condition-8
# visibility logger in-container. libfaketime: carried from cohort 2
# (#200) so a determinism wall CAN be lifted by declared apparatus
# without rebuilding the image — using it is a per-target owner decision
# (PROTOCOL: apparatus policy), never a default.

# The self-built target, and the assertion that justifies self-building:
# the binary must be dynamically linked against glibc (the distributed
# musl-static artifact is exactly what the shim cannot enter).
COPY --from=build /build/himalaya-src/target/release/himalaya /usr/local/bin/himalaya
RUN himalaya --version \
    && ldd /usr/local/bin/himalaya \
    && ldd /usr/local/bin/himalaya | grep -q 'libc\.so\.6'

# vdirsyncer 0.20.0 with its full locked closure (18 packages, all
# wheels — measured 2026-08-23, no sdist-only package in this closure).
# --require-hashes re-verifies every copied file against the
# PyPI-published hashes in the committed lock, so a tampered artifacts/
# fails here. --no-index makes the no-network claim an enforced property.
# --break-system-packages: a single-purpose container. --ignore-installed:
# the apt layer ships a Debian-owned typing_extensions with no RECORD
# file, which pip cannot uninstall (measured 2026-08-22, cohort-3 build);
# the locked versions land in /usr/local, which precedes dist-packages on
# sys.path.
COPY artifacts/wheels /tmp/wheels
COPY pins-wheels.txt pins-sdist.txt /tmp/
RUN pip3 install --break-system-packages --no-index \
        --ignore-installed --find-links /tmp/wheels --require-hashes \
        -r /tmp/pins-wheels.txt -r /tmp/pins-sdist.txt \
    && rm -rf /tmp/wheels /tmp/pins-wheels.txt /tmp/pins-sdist.txt \
    && vdirsyncer --version
