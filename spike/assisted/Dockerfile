# The assisted-discovery experiment image (#118): the five fixed targets
# plus what the engine and the pass target need. Not a sealed image, and —
# stated precisely (R1 finding 13) — pinned by BUILD, not by manifest: the
# base tag is mutable and the apt installs are unversioned, so a rebuild
# may drift. What the cohort actually ran is recorded in RESULTS.md
# (buku 4.7+ds-1, pass 1.7.4, calcurse 4.7.1, stow 2.3.1,
# devtodo 0.1.20+git20200830, bookworm-slim as of 2026-08-14).
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        buku \
        pass \
        calcurse \
        stow \
        devtodo \
        strace \
        python3 \
        gnupg \
        git \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# pass needs a signing-capable key; a throwaway test key is generated at
# container start by the run scripts, never baked into the image.
