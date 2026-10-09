# The box for the third round of 2026-10-09 follow-ups: the released Sideeye v1.10.0 beside the targets
# the second recount left measurable (SELECTION.md). The base is 2026-10-09 follow-ups 2's, copied.
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

# ---- Node targets, for UV_THREADPOOL_SIZE=1 (the threads wall) ----
RUN npm install -g --no-fund --no-audit @yarnpkg/cli-dist@4.18.1 trash-cli@7.2.0 > /tmp/npm-1.log 2>&1 && echo "OK yarn trash-cli" || { echo FAILED; tail -3 /tmp/npm-1.log; }
RUN { echo "node $(node --version)"; echo "yarn $(yarn --version)"; echo "trash $(npm ls -g trash-cli 2>/dev/null | grep trash-cli)"; } | tee /versions.txt
