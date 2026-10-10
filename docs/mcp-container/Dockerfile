# syntax=docker/dockerfile:1
# Sideeye's MCP server in a container, to copy rather than to pull (#721, ADR 0114).
# docs/mcp.md, "Running it in a container", is the page for it: copy this file, add the tool
# your sideeye.toml runs at its end, build, and start it with the flags that page gives.
# The tool has to be inside the same image, which is why there is no published image to pull.
#
# The syntax line above has BuildKit fetch the Dockerfile frontend it builds with, instead of
# using whichever one the engine carries: ADD --checksum on an https source needs a newer
# frontend than some engines ship.
#
# What goes in is a release's own tarball — the bytes `docs/cli.md`'s install note points at —
# checked by ADD --checksum against the digest GitHub publishes for the asset. Nothing is read
# from an API and nothing is fetched when the container runs. Moving the version is three
# edits: SIDEEYE_VERSION and the two digests, each the asset's `digest` field on that release
# (`gh api repos/yottayoshida/sideeye/releases/tags/vX.Y.Z`). This repository's CI holds all
# three against the release, and the version against `.github/workflows/quickstart-release.yml`.
#
# Needs BuildKit, Docker's default builder: the per-architecture stages below and ADD
# --checksum are BuildKit's. It builds for linux/amd64 and linux/arm64, the two Linux assets.
# Keep it in a directory of its own with what your tool's lines copy in, apart from the
# directory you mount for the server: a build sends its whole directory as context, and the
# mount holds whatever a target left there.

ARG SIDEEYE_VERSION=v1.10.0

FROM scratch AS fetch-amd64
ARG SIDEEYE_VERSION
ADD --checksum=sha256:1edc377b5bf3f64429523dd6cdf0ef248bad9c3704c62d6766879b589b7c2496 \
    https://github.com/yottayoshida/sideeye/releases/download/${SIDEEYE_VERSION}/sideeye-${SIDEEYE_VERSION}-x86_64-linux.tar.gz \
    /sideeye.tar.gz

FROM scratch AS fetch-arm64
ARG SIDEEYE_VERSION
ADD --checksum=sha256:cb176c41df10611ec6eb2c255bf5d7f557edfb4159752e7f89959519c3c6a99a \
    https://github.com/yottayoshida/sideeye/releases/download/${SIDEEYE_VERSION}/sideeye-${SIDEEYE_VERSION}-aarch64-linux.tar.gz \
    /sideeye.tar.gz

# Only the stage for the platform being built is built.
FROM fetch-${TARGETARCH} AS fetch

# The binaries ask for glibc 2.28 or later, so another glibc base works too. Whatever base
# you pick, build your tool on it: a program linked against a newer glibc than the base
# carries can refuse to start (a toy compiled on Ubuntu 24.04 asks for GLIBC_2.38, which
# this base's 2.36 does not have). Pinned by its multi-architecture index digest; the
# strace below is the base's own package, which Debian moves only with stable updates.
FROM debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587

RUN apt-get update \
 && apt-get install -y --no-install-recommends strace \
 && rm -rf /var/lib/apt/lists/*

# The tarball unpacks into one directory named for the version and the architecture; it is
# laid out flat here instead, binary beside shim, which is where Sideeye looks for the shim
# first. --no-same-owner: the files belong to root, not to the uid that packed them.
RUN --mount=from=fetch,source=/sideeye.tar.gz,target=/tmp/sideeye.tar.gz \
    mkdir -p /opt/sideeye \
 && tar -xzf /tmp/sideeye.tar.gz --no-same-owner --strip-components=1 -C /opt/sideeye

# strace is the server's second witness: without SIDEEYE_MCP_ORACLE a would-be PASS refuses
# as completeness_not_verified (docs/mcp.md's table of variables).
ENV PATH=/opt/sideeye:$PATH \
    SIDEEYE_MCP_ORACLE=/usr/bin/strace

# ---- Your tool goes after this line ------------------------------------------------------
# Install or copy what your sideeye.toml's setup, operation and check run, built on this base.
