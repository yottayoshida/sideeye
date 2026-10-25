# The box for the 2026-10-25 shipped-v1160 run: Sideeye v1.16.0 installed the way
# docs/ci-quickstart.md tells a project to install it, and the twenty candidates beside it.
# Base copied from 2026-10-12 shipped-v1120's Dockerfile; its tool layers are not carried over.
#
# A FAIL measured on a packaged build is void if upstream has moved
# (spike/upstream-report-template.md), so each tool is taken from its own latest release for
# linux/arm64 as GitHub, PyPI and npm answered on 2026-10-25, unless a layer says otherwise.
#
# Built by build.sh. Network at build only; every gate, explore and replay runs `--network none`.
# linux/arm64 (this machine's Docker).
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 python3-venv python3-dev ca-certificates procps bash git curl unzip xz-utils bzip2 \
      build-essential pkg-config dosfstools libfaketime faketime

COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    PATH=/opt/bin:/opt/py/bin:/opt/node/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
RUN mkdir -p /opt/bin /tmp/dl && python3 -m venv /opt/py

COPY install-sideeye.sh /opt/install-sideeye.sh
RUN sh /opt/install-sideeye.sh v1.16.0 /opt/se > /install.path 2>/install.log; \
    echo "installer exit: $?"; \
    echo "stdout: [$(cat /install.path)]"; \
    grep -E 'digest|sideeye ' /install.log || true
RUN "$(cat /install.path)" version

# The device the defines may declare in `apparatus` (docs/apparatus.md) for a tool that draws random
# bytes into what it saves: pin-random.so, copied from 2026-10-12.
COPY pin-random.c /opt/pin/pin-random.c
RUN gcc -shared -fPIC -O2 -o /opt/pin/pin-random.so /opt/pin/pin-random.c -ldl && \
    python3 -c "import sys; sys.stdout.buffer.write(bytes((i * 131 + 7) % 256 for i in range(1 << 20)))" > /opt/pin/urandom.bin && echo "OK pin-random.so"

# ---- the candidates (added once the sets are fixed; SELECTION.md) ----
