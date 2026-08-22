# The criterion-1 third-cohort image (#209): the five frozen sweet-spot
# targets plus what the engine and the probes need. Stated the same way as
# the cohort-1 and cohort-2 images: the apt layer is pinned by BUILD, not
# by manifest — the base tag is mutable and the apt installs are
# unversioned, so a rebuild may drift. The five targets themselves are
# exact-pinned (below), so target drift is not possible without editing
# this file. What actually ran is recorded in probes/*.txt and each
# target's RUNLOG.
#
# Every target installs at the CURRENT upstream stable (2026-08-22), not
# the distro version — a finding on a stale build would have to be
# re-measured on current anyway (cohort-2 PROTOCOL, Versions), so the
# latest-stable recheck that walls and FAILs require is inherent here.
#
# All release artifacts are fetched on the HOST by ./fetch-artifacts.sh
# into ./artifacts/ (gitignored) and copied in: this machine's
# TLS-intercepting proxy breaks in-container pip/curl certificate
# verification (measured 2026-08-21, cohort-2 image build). The pins live
# in fetch-artifacts.sh (rust: channel-manifest sha256) and in the
# committed uv lock (Python: PyPI-published hashes, enforced again below
# by pip's own --require-hashes at install time), so the build does not
# have to trust the context.
#
# arm64-only, on purpose: the rust tarballs are aarch64 and the engine
# this cohort mounts is the cross-built aarch64-linux pair. On an x86_64
# host the version checks fail loudly at build time.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        strace \
        python3 \
        python3-pip \
        python3-setuptools \
        python3-wheel \
        ca-certificates \
        xz-utils \
        libfaketime \
    && rm -rf /var/lib/apt/lists/*
# libfaketime: carried from cohort 2 (#200) so a determinism wall CAN be
# lifted by declared apparatus without rebuilding the image — but using it
# is a per-target owner decision (PROTOCOL: apparatus policy), never a
# default.

# Rust 1.98.0 (stable, 2026-08-18): the combined standalone tarball
# bundles rustfmt-preview alongside rustc/std/cargo — measured in the
# artifact's own `components` file (2026-08-22; the R1 review caught the
# earlier claim that it did not, which had read rustup's network
# component model instead of the shipped artifact). One tarball, one pin;
# the install selects exactly the four components the cohort needs.
# rustc is installed because `cargo metadata` may invoke it.
COPY artifacts/rust-1.98.0-aarch64-unknown-linux-gnu.tar.xz /tmp/rust.tar.xz
RUN echo "ac9283184301aeed06ecc9f5aa4c1be7041e18a1b197b6cb6c5d162d98f566da  /tmp/rust.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/rust.tar.xz -C /tmp \
    && /tmp/rust-1.98.0-aarch64-unknown-linux-gnu/install.sh --prefix=/usr/local \
        --components=rustc,cargo,rust-std-aarch64-unknown-linux-gnu,rustfmt-preview \
    && rm -rf /tmp/rust.tar.xz /tmp/rust-1.98.0-aarch64-unknown-linux-gnu \
    && cargo --version && rustc --version && rustfmt --version

# black 26.5.1, poetry 2.4.1, papis 0.16.0 with their full locked closure
# (74 packages: 72 wheels + 2 sdist-only, bibtexparser/python-doi — no
# wheels exist at their locked versions, measured 2026-08-22).
# --require-hashes re-verifies every copied file against the PyPI-published
# hashes in the committed lock, so a tampered artifacts/ fails here.
# --no-index makes the no-network claim an enforced property;
# --no-build-isolation builds the two pure-Python sdists with apt's
# setuptools. --break-system-packages: a single-purpose container, not a
# distro environment to protect. --ignore-installed: the apt layer ships a
# Debian-owned typing_extensions with no RECORD file, which pip cannot
# uninstall (measured, first build 2026-08-22); the locked versions land
# in /usr/local, which precedes dist-packages on sys.path, and the Debian
# copies are left untouched.
COPY artifacts/wheels /tmp/wheels
COPY pins-wheels.txt pins-sdist.txt /tmp/
RUN pip3 install --break-system-packages --no-build-isolation --no-index \
        --ignore-installed --find-links /tmp/wheels --require-hashes \
        -r /tmp/pins-wheels.txt -r /tmp/pins-sdist.txt \
    && rm -rf /tmp/wheels /tmp/pins-wheels.txt /tmp/pins-sdist.txt \
    && black --version && poetry --version && papis --version
