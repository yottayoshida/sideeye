# #559's second half, measured on ansible: ansible-core under strace, nothing else. The same file
# built the image `sideeye-559-proto:2026-09-13` the go/no-go prototype ran in, and this run reuses it.
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends strace file python3 ca-certificates procps util-linux ansible-core
RUN ansible --version | head -1 && strace -V | head -1
WORKDIR /w
