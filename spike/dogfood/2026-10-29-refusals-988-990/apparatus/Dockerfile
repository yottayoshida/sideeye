# The box for #988, #989 and #990: the four targets 2026-10-25's run met the three refusals on, at the
# versions it ran them at, and no Sideeye. The engine and shim are mounted per run, so one box runs main
# and each change side by side and a wall that moved did so between the two builds.
#
# Layers copied from spike/dogfood/2026-10-25-shipped-v1160/apparatus (Dockerfile, sets/1b, sets/1e,
# sets/3). linux/arm64 (this machine's Docker). Network at build only; every run is `--network none`.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps bash curl xz-utils sqlite3 \
      openjdk-21-jre-headless rocksdb-tools

COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    PATH=/opt/bin:/opt/node/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
RUN mkdir -p /opt/bin /tmp/dl

RUN cd /tmp/dl && curl -fsSL -o flyway.tgz https://github.com/flyway/flyway/releases/download/flyway-13.11.1/flyway-commandline-13.11.1.tar.gz && \
    mkdir -p /opt/flyway && tar xzf flyway.tgz -C /opt/flyway --strip-components=1 && ln -sf /opt/flyway/flyway /opt/bin/flyway

RUN cd /tmp/dl && curl -fsSL -o node.txz https://nodejs.org/dist/v24.22.1/node-v24.22.1-linux-arm64.tar.xz && \
    mkdir -p /opt/node && tar xJf node.txz -C /opt/node --strip-components=1 && /opt/node/bin/node --version
RUN set -e; P=/opt/prisma-proto; mkdir -p $P/prisma && cd $P && npm init -y > /dev/null && \
    npm install --no-audit --no-fund prisma@7.10.1 > /tmp/npm-prisma.log 2>&1 && npx prisma --version | head -3

RUN cd /tmp/dl && curl -fsSL -o salt.txz https://github.com/saltstack/salt/releases/download/v3008.4/salt-3008.4-onedir-linux-arm64.tar.xz && \
    mkdir -p /opt/salt && tar xJf salt.txz -C /opt/salt && \
    ln -sf "$(find /opt/salt -maxdepth 2 -name salt-call | head -1)" /opt/bin/salt-call

RUN { echo "flyway $(flyway -v 2>&1 | grep -i -m1 'flyway')"; echo "ldb $(dpkg-query -W rocksdb-tools)"; \
      echo "java $(java -version 2>&1 | head -1)"; echo "node $(node --version)"; \
      echo "prisma $(cd /opt/prisma-proto && npx prisma --version 2>&1 | head -1)"; \
      echo "salt-call $(salt-call --version 2>&1 | head -1)"; echo "strace $(strace -V | head -1)"; } | tee /versions.txt
