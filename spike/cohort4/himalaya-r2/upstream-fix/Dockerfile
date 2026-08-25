# The cohort-4 image with ONE thing changed: himalaya is built against
# io-maildir 0.3.1, which carries the upstream fix for pimalaya/himalaya#738
# (pimalaya/io-maildir@b4e9080, "fix: clean tmp after copy").
#
# WHY THE RUNTIME LAYER IS THE COHORT IMAGE ITSELF rather than a rebuild of
# its Dockerfile: the cohort-4 Dockerfile says its apt layer is pinned by
# BUILD, not by manifest, so rebuilding it may drift. Starting FROM the
# already-built image and replacing exactly one file makes the delta between
# "the measured target" and "the fixed target" the himalaya binary and
# nothing else. strace, libfaketime, gcc, the unison binary and every shared
# library the pinned binary resolves against are the same bytes.
#
# WHAT THE SOURCE DELTA IS, measured rather than asserted: the tree copied in
# below differs from the frozen artifacts/himalaya-src by two lines of
# Cargo.lock, io-maildir's version and its checksum. `cargo vendor --locked`
# succeeded against that lock, which is the machine-checked statement that
# 0.3.1 has the same dependency closure as 0.3.0 — no other crate moves.
#
# THE COHORT'S DIGEST VERIFICATION IS NOT DROPPED, IT IS SPLIT. The cohort
# Dockerfile digests the whole tree against one pin, which this tree cannot
# match because its lock is knowingly different. The RUN below digests
# everything EXCEPT Cargo.lock against the frozen tree's digest computed the
# same way, and pins the lock separately by its own sha256 — so "the frozen
# checkout plus exactly this lock edit" is machine-checked rather than
# promised, and neither half is free to be anything else. Cargo's own
# re-check of every vendored crate against that lock still runs on top.
# Both pins were shown red before being trusted: appending one line to a
# source file stops the build here, before cargo runs.

FROM debian:trixie-slim AS build-himalaya

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        xz-utils \
        gcc \
        libc6-dev \
    && rm -rf /var/lib/apt/lists/*

# Same Rust tarball and same sha256 pin as the cohort-4 image.
COPY rust-1.98.0-aarch64-unknown-linux-gnu.tar.xz /tmp/rust.tar.xz
RUN echo "ac9283184301aeed06ecc9f5aa4c1be7041e18a1b197b6cb6c5d162d98f566da  /tmp/rust.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/rust.tar.xz -C /tmp \
    && /tmp/rust-1.98.0-aarch64-unknown-linux-gnu/install.sh --prefix=/usr/local \
        --components=rustc,cargo,rust-std-aarch64-unknown-linux-gnu \
    && rm -rf /tmp/rust.tar.xz /tmp/rust-1.98.0-aarch64-unknown-linux-gnu \
    && cargo --version && rustc --version

COPY himalaya-src /build/himalaya-src
COPY vendor /build/vendor

# The inputs are pinned the way the cohort Dockerfile pins its own, split in
# two so the split IS the claim. The tree digest is computed over every file
# EXCEPT Cargo.lock, and equals the frozen tree's digest computed the same way:
# that is the machine-checked statement that nothing but the lock differs from
# the pinned v2.1.0 checkout. The lock is then pinned separately by its own
# sha256, so the one file that does differ is not free to be anything.
#
# What this does NOT claim, and the record says so too: the compiled closure
# differs by a whole crate release, 0.3.0 to 0.3.1. Two lines of lock is the
# size of the edit, not the size of the change.
RUN cd /build/himalaya-src \
    && got=$(find . -type f -not -path './.git/*' -not -name Cargo.lock -print0 \
        | LC_ALL=C sort -z | xargs -0 -n 64 sha256sum | sha256sum | cut -d' ' -f1) \
    && want=1fc324cc27e3f30c4508a2d8736f0ec638f85b6e59b412f955b227b94efdd3d2 \
    && { [ "$got" = "$want" ] \
        || { echo "tree-minus-lock digest mismatch: got $got wanted $want"; exit 1; }; } \
    && echo "cc703172bc9339e27711daccbd56c833c44fd6cbae02a15e88af878321483d2f  Cargo.lock" \
        | sha256sum -c -

RUN cd /build/himalaya-src \
    && grep -q 'version = "0.3.1"' Cargo.lock \
    && mkdir -p .cargo \
    && printf '[source.crates-io]\nreplace-with = "vendored-sources"\n\n[source.vendored-sources]\ndirectory = "/build/vendor"\n' \
        > .cargo/config.toml \
    && cargo build --release --locked --offline \
    && ./target/release/himalaya --version

# The fix must be in the crate that was actually compiled, not merely in the
# lock file. Asserted on the vendored source cargo read, and asserted on the
# SEMANTICS rather than on a state-variant name: the names moved between the
# fix commit (AwaitCopy/AwaitRename) and the 0.3.1 release (Copy/Rename), so
# grepping the commit's identifiers against the release reports a false
# absence.
RUN grep -q 'self.target.tmp().join' /build/vendor/io-maildir/src/entry/copy.rs \
    && grep -q 'MaildirYield::WantsRename' /build/vendor/io-maildir/src/entry/copy.rs \
    && echo "io-maildir 0.3.1: copy stages in the target tmp/ and renames into place"

FROM sideeye-cohort4:latest

COPY --from=build-himalaya /build/himalaya-src/target/release/himalaya /usr/local/bin/himalaya
RUN himalaya --version \
    && ldd /usr/local/bin/himalaya \
    && ldd /usr/local/bin/himalaya | grep -q 'libc\.so\.6'
