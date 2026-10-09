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

# ---- round 2: the awaiting reports' projects at their latest releases (2026-10-09) ----
RUN apt-get install -y --no-install-recommends stow nodejs npm tesseract-ocr tesseract-ocr-eng ghostscript \
      autoconf automake libtool autopoint gettext libncurses-dev libssl-dev libsqlite3-dev openssl unzip \
      > /tmp/apt-r2.log 2>&1 && echo "OK apt round 2" || { echo MISSING; tail -3 /tmp/apt-r2.log; }
RUN for p in trash-cli==0.26.9.29 topydo==0.16 beancount==3.2.3 ocrmypdf==17.13.0 Pillow; do \
      /opt/py/bin/pip install --no-cache-dir "$p" > /tmp/pip-$p.log 2>&1 && echo "OK $p" || { echo "FAILED $p"; tail -3 /tmp/pip-$p.log; }; \
    done
RUN npm install -g --no-fund --no-audit @dotenvx/dotenvx@2.34.1 > /tmp/npm-dotenvx.log 2>&1 && echo "OK dotenvx" || tail -3 /tmp/npm-dotenvx.log
RUN set -u; cd /tmp/dl; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get https://github.com/Exiv2/exiv2/releases/download/v0.28.9/exiv2-0.28.9-Linux-aarch64.tar.gz exiv2.tgz; \
    get https://releases.hashicorp.com/terraform/1.16.5/terraform_1.16.5_linux_arm64.zip terraform.zip; \
    get https://awscli.amazonaws.com/awscli-exe-linux-aarch64-2.37.11.zip awscli.zip; \
    get https://calcurse.org/files/calcurse-4.8.2.tar.gz calcurse.tgz; \
    get https://github.com/softhsm/SoftHSMv2/archive/refs/tags/2.7.0.tar.gz softhsm.tgz; \
    mkdir -p /opt/exiv2 && tar xzf exiv2.tgz -C /opt/exiv2 --strip-components=1; \
    unzip -q -o terraform.zip -d /opt/bin; \
    unzip -q -o awscli.zip -d /tmp/dl/aws && /tmp/dl/aws/aws/install -i /opt/aws-cli -b /opt/bin > /tmp/aws-install.log 2>&1; echo "aws install exit $?"
RUN set -u; cd /tmp/dl && tar xzf calcurse.tgz && cd calcurse-4.8.2 && ./configure --prefix=/opt/calcurse --disable-docs > /tmp/calcurse.log 2>&1 \
    && make -j4 >> /tmp/calcurse.log 2>&1 && make install >> /tmp/calcurse.log 2>&1; echo "calcurse build exit $?"; tail -2 /tmp/calcurse.log
RUN set -u; cd /tmp/dl && tar xzf softhsm.tgz && cd SoftHSMv2-2.7.0 && sh autogen.sh > /tmp/softhsm.log 2>&1 && ./configure --prefix=/opt/softhsm --disable-gost >> /tmp/softhsm.log 2>&1 \
    && make -j4 >> /tmp/softhsm.log 2>&1 && make install >> /tmp/softhsm.log 2>&1; echo "softhsm build exit $?"; tail -2 /tmp/softhsm.log || true
RUN { for c in "/opt/exiv2/bin/exiv2 --version" "/opt/py/bin/trash-put --version" "stow --version" "/opt/bin/aws --version" \
        "/opt/py/bin/bean-format --version" "dotenvx --version" "/opt/bin/terraform version" "/opt/calcurse/bin/calcurse --version" \
        "/opt/py/bin/ocrmypdf --version" "/opt/softhsm/bin/softhsm2-util --version" "/opt/py/bin/topydo version"; do \
        printf '%s: ' "$c"; sh -c "$c" < /dev/null 2>&1 | head -1; done; } | tee -a /versions.txt
# trash-cli 0.24.5.26, the release andreafrancia/trash-cli#414 measured, in a venv of its own beside the latest
RUN python3 -m venv /opt/tc0245 && /opt/tc0245/bin/pip install --no-cache-dir trash-cli==0.24.5.26 > /tmp/pip-tc0245.log 2>&1; \
    echo "trash-cli 0.24.5.26: $(/opt/tc0245/bin/trash-put --version 2>&1)" | tee -a /versions.txt
