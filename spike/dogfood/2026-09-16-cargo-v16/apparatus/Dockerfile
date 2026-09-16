# 2026-09-16 dogfood: cargo, re-met with the released v1.4.0 (trace contract v17) in both
# observation modes (#538). Sideeye itself is not in the image: the release tarball is
# mounted at /se. A run-specific image, like every dogfood run before it — not
# spike/Dockerfile, which is the blind-hunt campaign image pinned for #244.
# apt lists are not cleaned (omamori blocks the rm -rf string on the host side).
FROM rust:1.97.1-slim-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace python3 procps ca-certificates
RUN cargo --version && rustc --version && strace -V | head -1
WORKDIR /w
