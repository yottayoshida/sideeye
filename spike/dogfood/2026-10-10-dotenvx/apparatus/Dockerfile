# The box for 2026-10-10: the released Sideeye v1.10.0 beside dotenvx 2.32.4 (the version
# dotenvx/dotenvx#1012 measured) and 2.34.2 (its fix, dotenvx/dotenvx#1014), each in a prefix of its own.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace python3 ca-certificates procps bash git curl nodejs npm util-linux

COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

COPY install-sideeye.sh /opt/install-sideeye.sh
RUN sh /opt/install-sideeye.sh v1.10.0 /opt/se > /install.path 2>/install.log; \
    echo "installer exit: $?"; grep -E 'digest|sideeye ' /install.log || true
RUN "$(cat /install.path)" version

RUN for v in 2.32.4 2.34.2; do \
      npm install -g --no-fund --no-audit --prefix /opt/dx-$v @dotenvx/dotenvx@$v > /tmp/npm-$v.log 2>&1 \
        && echo "OK dotenvx $v" || { echo "FAILED $v"; tail -3 /tmp/npm-$v.log; }; \
    done
RUN { echo "node $(node --version)"; echo "git $(git --version)"; echo "strace $(strace -V | head -1)"; \
      for v in 2.32.4 2.34.2; do echo "dotenvx $(/opt/dx-$v/bin/dotenvx --version)"; \
        echo "  write-file-atomic: $(cat /opt/dx-$v/lib/node_modules/@dotenvx/dotenvx/node_modules/write-file-atomic/package.json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])' 2>/dev/null || echo absent)"; done; } | tee /versions.txt
