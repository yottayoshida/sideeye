# The box for 2026-10-10 follow-ups 6: the released Sideeye v1.10.0 beside Jujutsu 0.44.0, the release
# #687 names (measured 2026-09-27), and 0.46.0, the latest — to find which threads write jj's state and
# whether a setting stops one. The base is follow-ups 5's.
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
RUN apt-get install -y --no-install-recommends git > /tmp/apt-git.log 2>&1 && echo "OK git" || { echo MISSING; tail -3 /tmp/apt-git.log; }
RUN set -eu; cd /tmp/dl; gh=https://github.com/jj-vcs/jj/releases/download; \
    for pair in 0.44.0:60d42fa2a9abaa445eff10cd2087458562aaad5a54b90309e5a3787ecc985ff2 0.46.0:80e28f7501c11e50e0ca06cd6a1fa1d982cff9cc59bfe4411a9d36aa501d867e; do \
      v=${pair%%:*}; d=${pair#*:}; \
      curl -fsSL -o jj-$v.tgz $gh/v$v/jj-v$v-aarch64-unknown-linux-musl.tar.gz; \
      echo "$d  jj-$v.tgz" | sha256sum -c; \
      mkdir -p x-$v /opt/jj-$v && tar xzf jj-$v.tgz -C x-$v && install -m 755 "$(find x-$v -type f -name jj | head -1)" /opt/jj-$v/jj; \
      echo "jj $v: $(/opt/jj-$v/jj --version)"; \
    done | tee /versions.txt
