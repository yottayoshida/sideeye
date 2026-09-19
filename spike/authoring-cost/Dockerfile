# The machine an authoring run happens on (#618, PROTOCOL.md beside this file).
# Build from the repository root so README.md is in the context:
#   docker build -f spike/authoring-cost/Dockerfile --build-arg TARGET=<pkg> -t sideeye-authoring-<pkg> .
# Run network-off. The build needs the network; the run must not.
FROM debian:bookworm-slim

# The slim image excludes documentation through dpkg config, which would have made this study
# measure something else: the task asks the subject to read the target's own documentation, and
# a card's `documented` backing cites it. Measured while probing: `dos2unix`'s image held no
# /usr/share/man at all. The exclusions are removed BEFORE the target is installed, so its pages
# land, and `man-db` is here as apparatus — never as a target (it is in pool-scratch.txt and
# excluded there by the freshness predicate).
RUN rm -f /etc/dpkg/dpkg.cfg.d/docker /etc/dpkg/dpkg.cfg.d/excludes \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl strace coreutils python3 man-db less \
 && rm -rf /var/lib/apt/lists/*

RUN useradd -m user
WORKDIR /home/user/authoring

# The engine, pinned by the digest GitHub publishes. The tag, the asset and the digest are
# PASSED IN rather than written here: `spike/unknown-rate/engine-pins.tsv` owns those values
# (its `g3` row), and a second copy here would let the pin move while this image quietly kept
# the old build. The launcher and the probe read that row and hand it over; the defaults below
# only exist so a bare `docker build` still produces something, and they are checked against the
# pin by the caller. -k tolerates a TLS MITM in the build sandbox because integrity comes from
# the digest, not from the channel.
# The tarball is left packed on purpose: unpacking it is part of what the subject does.
ARG ENGINE_TAG=v1.5.0
ARG ENGINE_ASSET=sideeye-v1.5.0-aarch64-linux.tar.gz
ARG ENGINE_SHA256=f81c58a3eb632a352bba067457c8a0331ff9df91e914f0a39561da384b024815
RUN curl -sLk -o "$ENGINE_ASSET" \
      "https://github.com/yottayoshida/sideeye/releases/download/$ENGINE_TAG/$ENGINE_ASSET" \
 && echo "$ENGINE_SHA256  $ENGINE_ASSET" | sha256sum -c -

# The front page at the measured commit, verbatim: the only Sideeye documentation this apparatus
# supplies. The subject may reach others (PROTOCOL.md, "One leg only").
COPY README.md /home/user/authoring/README.md

# What makes the revisions evidence rather than prose (PROTOCOL.md, "Evidence").
#
# A PATH shim over `sideeye` was the first design and was wrong twice: the subject unpacks the
# engine itself, so a shim announces that the tool is already installed — changing the task —
# and an invocation by path walks around it anyway. This watches the artefact instead of the
# invocation: every second, any TOML under the subject's home that changed since the last look
# is copied to /home/user/revisions/NN.toml in order. It sees a define the subject wrote and
# never ran, which is the first wrong reading #618 asks for and a shim cannot capture.
COPY spike/authoring-cost/watch-defines.py /usr/local/bin/watch-defines.py
RUN mkdir -p /home/user/revisions \
 && chmod 0755 /usr/local/bin/watch-defines.py \
 && chown -R user:user /home/user

# The target LAST, with its own ARG: everything above is identical for all four shapes, so the
# apparatus layers and the engine download are built once and reused. With `ARG TARGET` at the
# top — where it was first written — each of the four probe builds repeated the apt install and
# the tarball fetch. The run's meta records the version that was installed; pinning one here
# would rot silently.
ARG TARGET
RUN apt-get update \
 && apt-get install -y --no-install-recommends "$TARGET" \
 && rm -rf /var/lib/apt/lists/*

USER user
# A real machine has these; `docker exec` does not set them, and a tool that asks who you are
# (fossil does, and refuses without an answer) would meet an apparatus artefact rather than
# its own behaviour. Measured while probing the selection: `fossil init` exits 1 with "Cannot
# figure out who you are!" in a box without USER. Friction this study counts has to be the
# target's, not the container's.
ENV USER=user HOME=/home/user
# The watcher is the container's main process: if it dies, the box dies, and a run whose
# evidence stopped being collected halfway is void rather than short.
CMD ["python3", "/usr/local/bin/watch-defines.py", "/home/user", "/home/user/revisions"]
