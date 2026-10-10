# The box for #678's re-measurement: the two tools the 2026-10-03 run found checking a mode under
# the state (upx 5.2.1, argocd 3.5.3), installed from the release assets that run used, and the
# run's mode-bit probe (defines/modebit, a 0755 script inside the state). No engine is installed:
# run.sh mounts the build under test at /se.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps curl xz-utils bash \
 && rm -rf /var/lib/apt/lists/*

COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

RUN set -eu; mkdir -p /tmp/dl && cd /tmp/dl; gh=https://github.com; \
    curl -fsSL -o upx.txz "$gh/upx/upx/releases/download/v5.2.1/upx-5.2.1-arm64_linux.tar.xz"; \
    curl -fsSL -o argocd "$gh/argoproj/argo-cd/releases/download/v3.5.3/argocd-linux-arm64"; \
    sha256sum upx.txz argocd | tee /downloads.sha256; \
    mkdir -p x-upx && tar xJf upx.txz -C x-upx && install -m 755 "$(find x-upx -type f -name upx | head -1)" /usr/local/bin/upx; \
    install -m 755 argocd /usr/local/bin/argocd

RUN { upx --version | head -1; argocd version --client --short; file -L /usr/local/bin/upx /usr/local/bin/argocd | cut -c1-140; } > /versions.txt 2>&1; cat /versions.txt
