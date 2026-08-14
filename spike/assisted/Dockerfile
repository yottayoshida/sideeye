# The assisted-discovery experiment image (#118): the five fixed targets
# plus what the engine and the pass target need. Not a sealed image — the
# experiment is assisted, not blind — but pinned the same way so runs stay
# reproducible.
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
