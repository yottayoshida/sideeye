# The box for the fourth round of 2026-10-09 follow-ups: the released Sideeye v1.10.0 beside the three targets
# #678 left (upx, argocd, prefsCleaner), each to run on a FAT filesystem whose mount fixes the modes and owner
# they need, and lz4. The base is 2026-10-09 follow-ups 3's, copied.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 python3-venv python3-dev ca-certificates procps bash git curl unzip xz-utils bzip2 \
      build-essential pkg-config zstd

COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

RUN for p in nodejs npm libfaketime faketime; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt

ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    PATH=/opt/bin:/opt/py/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
RUN mkdir -p /opt/bin /tmp/dl /tmp/src && python3 -m venv /opt/py

COPY install-sideeye.sh /opt/install-sideeye.sh
RUN sh /opt/install-sideeye.sh v1.10.0 /opt/se > /install.path 2>/install.log; \
    echo "installer exit: $?"; \
    echo "stdout: [$(cat /install.path)]"; \
    grep -E 'digest|sideeye ' /install.log || true
RUN "$(cat /install.path)" version

RUN apt-get install -y --no-install-recommends dosfstools lz4 > /tmp/apt-1.log 2>&1 && echo "OK dosfstools lz4" || { echo MISSING; tail -3 /tmp/apt-1.log; }
RUN set -eu; cd /tmp/dl; gh=https://github.com; \
    curl -fsSL -o upx.txz $gh/upx/upx/releases/download/v5.2.1/upx-5.2.1-arm64_linux.tar.xz; mkdir -p x-upx && tar xJf upx.txz -C x-upx; install -m 755 "$(find x-upx -type f -name upx | head -1)" /opt/bin/upx; \
    curl -fsSL -o argocd $gh/argoproj/argo-cd/releases/download/v3.5.3/argocd-linux-arm64; install -m 755 argocd /opt/bin/argocd; \
    curl -fsSL -o prefsCleaner.sh https://raw.githubusercontent.com/arkenfox/user.js/bb45863be796d331717e2b5d6e490f0d3e3cf93f/prefsCleaner.sh; \
    curl -fsSL -o user.js https://raw.githubusercontent.com/arkenfox/user.js/bb45863be796d331717e2b5d6e490f0d3e3cf93f/user.js; \
    mkdir -p /opt/arkenfox && install -m 755 prefsCleaner.sh /opt/arkenfox/prefsCleaner.sh && install -m 644 user.js /opt/arkenfox/user.js
RUN { for c in "upx --version" "argocd version --client --short" "lz4 --version"; do printf '%s: ' "$c"; sh -c "$c" < /dev/null 2>&1 | head -1; done; echo "prefsCleaner $(grep -m1 -i version /opt/arkenfox/prefsCleaner.sh)"; } | tee /versions.txt
