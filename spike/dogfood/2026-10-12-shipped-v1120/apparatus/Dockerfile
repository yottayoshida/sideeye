# The box for the 2026-10-12 shipped-v1120 run: Sideeye v1.12.0 installed the way
# docs/ci-quickstart.md tells a project to install it, and the ten candidates beside it.
# Base copied from 2026-10-09 user-data-4's Dockerfile; its tool layers are not carried over.
#
# A FAIL measured on a packaged build is void if upstream has moved
# (spike/upstream-report-template.md), so each tool is taken from its own latest release for
# linux/arm64 as GitHub and PyPI answered on 2026-10-12. KeePassXC is the exception: its
# releases carry no Linux arm64 binary (an x86_64 AppImage, a macOS dmg), so it is Debian
# trixie's keepassxc-minimal 2.7.10 against upstream's 2.7.12, and a FAIL on it is read against
# upstream's source before anything is said (SELECTION.md).
#
# Built by build.sh. Network at build only; every gate, explore and replay runs `--network none`.
# linux/arm64 (this machine's Docker).
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 python3-venv python3-dev ca-certificates procps bash git curl unzip xz-utils bzip2 \
      build-essential pkg-config

COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    PATH=/opt/bin:/opt/py/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
RUN mkdir -p /opt/bin /tmp/dl && python3 -m venv /opt/py

COPY install-sideeye.sh /opt/install-sideeye.sh
RUN sh /opt/install-sideeye.sh v1.12.0 /opt/se > /install.path 2>/install.log; \
    echo "installer exit: $?"; \
    echo "stdout: [$(cat /install.path)]"; \
    grep -E 'digest|sideeye ' /install.log || true
RUN "$(cat /install.path)" version

# ---- the ten candidates ----

# Debian: KeePassXC (see the header) and age, the key sops encrypts to without a cloud KMS.
RUN apt-get install -y --no-install-recommends keepassxc-minimal age > /tmp/apt-kp.log 2>&1 && echo "OK keepassxc-minimal age" || { echo "MISSING keepassxc-minimal/age"; tail -3 /tmp/apt-kp.log; }

# Release assets for linux/arm64: sops 3.13.3, rclone 1.75.2, DuckDB 1.5.6 (the glibc CLI),
# yq 4.54.1, Crystal 1.21.1 (its bundled tarball: the compiler with the libraries it links),
# FreeCAD 1.1.4 (its aarch64 AppImage, extracted: a container has no FUSE), Bun 1.4.3 and
# SwiftLint 0.65.1.
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.arm64 sops; \
    get $gh/rclone/rclone/releases/download/v1.75.2/rclone-v1.75.2-linux-arm64.zip rclone.zip; \
    get $gh/duckdb/duckdb/releases/download/v1.5.6/duckdb_cli-linux-arm64.zip duckdb.zip; \
    get $gh/mikefarah/yq/releases/download/v4.54.1/yq_linux_arm64 yq; \
    get $gh/crystal-lang/crystal/releases/download/1.21.1/crystal-1.21.1-1-linux-aarch64-bundled.tar.gz crystal.tgz; \
    get $gh/FreeCAD/FreeCAD/releases/download/1.1.4/FreeCAD_1.1.4-Linux-aarch64-py311.AppImage freecad.AppImage; \
    get $gh/oven-sh/bun/releases/download/bun-v1.4.3/bun-linux-aarch64.zip bun.zip; \
    get $gh/realm/SwiftLint/releases/download/0.65.1/swiftlint_linux_arm64.zip swiftlint.zip; \
    install -m 755 sops /opt/bin/sops; install -m 755 yq /opt/bin/yq; \
    mkdir -p x-rclone && unzip -q rclone.zip -d x-rclone && install -m 755 "$(find x-rclone -type f -name rclone | head -1)" /opt/bin/rclone; \
    mkdir -p x-duckdb && unzip -q duckdb.zip -d x-duckdb && install -m 755 "$(find x-duckdb -type f -name duckdb | head -1)" /opt/bin/duckdb; \
    mkdir -p /opt/crystal && tar xzf crystal.tgz -C /opt/crystal && ln -sf "$(find /opt/crystal -maxdepth 3 -type f -path '*/bin/crystal' | head -1)" /opt/bin/crystal; \
    chmod 755 freecad.AppImage && (cd /opt && /tmp/dl/freecad.AppImage --appimage-extract > /tmp/freecad-extract.log 2>&1) && mv /opt/squashfs-root /opt/freecad && echo "OK freecad extracted" || { echo "FAILED freecad extract"; tail -3 /tmp/freecad-extract.log; }; \
    mkdir -p x-bun && unzip -q bun.zip -d x-bun && install -m 755 "$(find x-bun -type f -name bun | head -1)" /opt/bin/bun; \
    mkdir -p x-swiftlint && unzip -q swiftlint.zip -d x-swiftlint && install -m 755 "$(find x-swiftlint -type f -name swiftlint | head -1)" /opt/bin/swiftlint; \
    ls -l /opt/bin

# The devices the defines declare in `apparatus` (docs/apparatus.md): libfaketime for the time
# stamps KeePassXC and FreeCAD write into a save, pin-random.so for KeePassXC's salts and IVs, and
# one age key made here, once, so sops encrypts to the same recipient in every run and no key
# lives in the repository.
RUN apt-get install -y --no-install-recommends libfaketime faketime > /tmp/apt-faketime.log 2>&1 && echo "OK libfaketime" || { echo "MISSING libfaketime"; tail -3 /tmp/apt-faketime.log; }
COPY pin-random.c /opt/pin/pin-random.c
RUN gcc -shared -fPIC -O2 -o /opt/pin/pin-random.so /opt/pin/pin-random.c -ldl && \
    python3 -c "import sys; sys.stdout.buffer.write(bytes((i * 131 + 7) % 256 for i in range(1 << 20)))" > /opt/pin/urandom.bin && echo "OK pin-random.so"
RUN age-keygen -o /opt/sops-age-key.txt 2> /opt/sops-age-recipient.txt && chmod 600 /opt/sops-age-key.txt && echo "OK age key ($(sed -n 's/^Public key: //p' /opt/sops-age-recipient.txt))"

# dosfstools: KeePassXC's second define puts its state on FAT, where Qt's O_TMPFILE save falls back
# to a named temporary (fat.sh, copied from 2026-10-09 follow-ups 3; docs/target-classes.md's Qt row).
RUN apt-get install -y --no-install-recommends dosfstools > /tmp/apt-fat.log 2>&1 && echo "OK dosfstools" || echo "MISSING dosfstools"

# PyPI: ansible-core 2.21.5, for ansible-vault.
RUN /opt/py/bin/pip install --no-cache-dir ansible-core==2.21.5 > /tmp/pip-ansible.log 2>&1 && echo "OK ansible-core" || { echo "FAILED ansible-core"; tail -3 /tmp/pip-ansible.log; }

# SwiftLint's linux zip carries no SourceKit, and `--fix` dies loading libsourcekitdInProc.so
# (transcripts/lab-1.txt). It comes from Swift 6.4.0's debian12 aarch64 toolchain — trixie has
# no Swift package — of which only usr/lib is kept; SwiftLint finds it by LINUX_SOURCEKIT_LIB_PATH.
RUN apt-get install -y --no-install-recommends libncurses6 libxml2 libcurl4 libedit2 libsqlite3-0 libstdc++-14-dev > /tmp/apt-swift.log 2>&1 && echo "OK swift runtime deps" || { echo "MISSING swift deps"; tail -3 /tmp/apt-swift.log; }
RUN set -u; cd /tmp/dl; v=6.4.0; \
    curl -fsSL -o swift.tgz https://download.swift.org/swift-$v-release/debian12-aarch64/swift-$v-RELEASE/swift-$v-RELEASE-debian12-aarch64.tar.gz && \
    mkdir -p /opt/swift && tar xzf swift.tgz -C /opt/swift --strip-components=1 --wildcards '*/usr/lib/*' && rm -f swift.tgz && \
    ls /opt/swift/usr/lib/libsourcekitdInProc.so && echo "OK swift $v usr/lib" || echo "FAILED swift toolchain"
ENV LINUX_SOURCEKIT_LIB_PATH=/opt/swift/usr/lib

RUN { echo "keepassxc-cli $(keepassxc-cli --version 2>&1 | head -1)"; echo "age $(age --version 2>&1 | head -1)"; \
      echo "sops $(sops --version 2>&1 | head -1)"; echo "rclone $(rclone version 2>&1 | head -1)"; \
      echo "duckdb $(duckdb --version 2>&1 | head -1)"; echo "yq $(yq --version 2>&1 | head -1)"; \
      echo "crystal $(crystal --version 2>&1 | head -1)"; \
      echo "freecadcmd $(ls /opt/freecad/usr/bin 2>/dev/null | grep -i -m1 cmd) $(/opt/freecad/usr/bin/freecadcmd --version 2>&1 | head -1)"; \
      echo "bun $(bun --version 2>&1 | head -1)"; echo "swiftlint $(swiftlint version 2>&1 | head -1)"; \
      echo "ansible-vault $(ansible-vault --version 2>&1 | head -1)"; } | tee /versions.txt
