# The box for 2026-10-09 follow-ups 5: the released Sideeye v1.10.0 beside tombi v1.7.0, the release
# tombi-toml/tombi#2265 was measured on (2026-10-02), and v1.7.3, which carries its fix (PR #2266, merged
# as 55b8549e53, the whole of v1.7.1's difference from v1.7.0). The base is 2026-10-09 follow-ups 4's, cut
# to what this round needs.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 python3-venv python3-dev ca-certificates procps bash git curl unzip xz-utils bzip2 \
      build-essential pkg-config zstd

COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

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
RUN set -eu; cd /tmp/dl; gh=https://github.com/tombi-toml/tombi/releases/download; \
    for v in 1.7.0 1.7.3; do \
      curl -fsSL -o tombi-$v.tgz $gh/v$v/tombi-cli-$v-aarch64-unknown-linux-musl.tar.gz; \
      mkdir -p x-$v /opt/tombi-$v && tar xzf tombi-$v.tgz -C x-$v && install -m 755 "$(find x-$v -type f -name tombi | head -1)" /opt/tombi-$v/tombi; \
      echo "tombi $v: $(/opt/tombi-$v/tombi --version) $(sha256sum tombi-$v.tgz | cut -c1-16)"; \
    done | tee /versions.txt
