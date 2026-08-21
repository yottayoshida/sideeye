# The criterion-1 second-cohort image (#183): the five frozen targets plus
# what the engine and the probes need. Like the cohort-1 image, and stated
# the same way: pinned by BUILD, not by manifest — the base tag is mutable
# and the apt installs are unversioned, so a rebuild may drift. What
# actually ran is recorded in probes/*.txt and each target's RUNLOG.
#
# Release artifacts (mercurial sdist, jj, bun) are fetched on the HOST by
# ./fetch-artifacts.sh into ./artifacts/ (gitignored) and copied in: the
# development machine sits behind a TLS-intercepting proxy whose CA a stock
# container does not trust — in-container pip failed certificate
# verification against PyPI (measured 2026-08-21); in-container curl shares
# the same trust store and is expected to fail the same way (inference,
# not measured — curl was dropped from the image instead). The pins live in
# the fetch script; this file re-verifies every copy so the build does not
# have to trust the context.
#
# arm64-only, on purpose: the jj and Bun binaries below are aarch64 and the
# engine this cohort mounts is the cross-built aarch64-linux pair. On an
# x86_64 host the version checks fail loudly at build time.
#
# Mercurial comes from PyPI at the current upstream stable (7.2.4,
# 2026-08-11) rather than apt, because a finding on a stale distro build
# would have to be re-measured on current anyway (PROTOCOL: Versions).
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        borgbackup \
        keepassxc \
        strace \
        python3 \
        python3-pip \
        python3-dev \
        python3-setuptools \
        python3-setuptools-scm \
        python3-wheel \
        gcc \
        git \
        ca-certificates \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# Mercurial 7.2.4 from the PyPI sdist (PyPI's published sha256; C
# extensions build with gcc above). --no-index --no-deps make the
# no-network claim an enforced property, not a hope; --no-build-isolation
# uses the apt-installed setuptools/setuptools-scm/wheel instead of
# fetching a build environment. --break-system-packages: a single-purpose
# container, not a distro environment to protect.
COPY artifacts/mercurial-7.2.4.tar.gz /tmp/
RUN echo "85839e0f39e6cb893a88932aa36ef661759f3c5c5de4551ad26bd9df53cb71a2  /tmp/mercurial-7.2.4.tar.gz" | sha256sum -c - \
    && pip3 install --break-system-packages --no-build-isolation --no-index --no-deps /tmp/mercurial-7.2.4.tar.gz \
    && rm /tmp/mercurial-7.2.4.tar.gz \
    && hg version -q

# Jujutsu v0.44.0, aarch64-musl release binary (first-download pin, see
# fetch-artifacts.sh).
COPY artifacts/jj-v0.44.0-aarch64-unknown-linux-musl.tar.gz /tmp/jj.tar.gz
RUN echo "60d42fa2a9abaa445eff10cd2087458562aaad5a54b90309e5a3787ecc985ff2  /tmp/jj.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/jj.tar.gz -C /usr/local/bin --strip-components=1 ./jj \
    && rm /tmp/jj.tar.gz \
    && jj --version

# Bun 1.4.0, aarch64-glibc release binary (hash from upstream
# SHASUMS256.txt).
COPY artifacts/bun-linux-aarch64.zip /tmp/bun.zip
RUN echo "4b1a332ee861983eb93bcfe6f770fff94e3e31b2c388bdaea3c8ed35e58eed0e  /tmp/bun.zip" | sha256sum -c - \
    && unzip -j /tmp/bun.zip -d /usr/local/bin bun-linux-aarch64/bun \
    && chmod 755 /usr/local/bin/bun \
    && rm /tmp/bun.zip \
    && bun --version
