# Ground for the loop-closure experiment (DESIGN §17, second criterion).
#
# The spike image plus what building timewarrior needs. git is for `git apply`
# (the positive control applies the known patch) and for timewarrior's own CMake
# version probing on the local checkout — no network use at run time: every
# container in this experiment runs with --network none, and the clone happens
# on the host, where the corporate TLS interception is already trusted.
#
# The base image is not on any registry. If it is missing, build it first from
# the sideeye repo root:  docker build -t sideeye-spike:latest spike/
FROM sideeye-spike:latest

RUN apt-get update \
 && apt-get install -y --no-install-recommends cmake g++ make git \
 && rm -rf /var/lib/apt/lists/*
