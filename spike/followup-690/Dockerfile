# #690: four targets whose result moved between runs of one define — tombi, mogrify, isort,
# dotter — re-measured with their traces kept. Sideeye is not installed: the branch's Linux
# build (with -Dtrace-ops) is mounted at /se, so the engine measured is the tree under review.
#
# Versions are the ones the recorded rows ran: tombi 1.5.6 (2026-10-02), dotter 0.13.5
# (2026-10-03), and Debian trixie's imagemagick and isort (the 2026-09-05..07 rows used the
# suite's packages; /versions.txt says which ones this build got).
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates curl imagemagick isort ffmpeg

# This machine's TLS-intercepting proxy (see build.sh). Empty when there is none.
COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

RUN set -eu; mkdir -p /opt/bin /tmp/dl; cd /tmp/dl; gh=https://github.com; \
    curl -fsSL -o tombi.tgz "$gh/tombi-toml/tombi/releases/download/v1.5.6/tombi-cli-1.5.6-aarch64-unknown-linux-musl.tar.gz"; \
    mkdir x-tombi && tar xzf tombi.tgz -C x-tombi; \
    install -m 755 "$(find x-tombi -type f -name tombi | head -1)" /opt/bin/tombi; \
    curl -fsSL -o dotter "$gh/SuperCuber/dotter/releases/download/v0.13.5/dotter-linux-arm64-musl"; \
    install -m 755 dotter /opt/bin/dotter; \
    cd / && rm -rf /tmp/dl; \
    { echo "tombi: $(/opt/bin/tombi --version)"; echo "dotter: $(/opt/bin/dotter --version)"; \
      echo "isort: $(isort --version | grep -i version | head -1)"; \
      echo "imagemagick: $(convert -version | head -1)"; echo "strace: $(strace -V | head -1)"; \
      echo "python3: $(python3 --version)"; } > /versions.txt 2>&1; cat /versions.txt

WORKDIR /work
