# The box for the second round of 2026-10-09 follow-ups: the released Sideeye v1.10.0 installed the
# way docs/ci-quickstart.md tells a project to install it, beside six upstream fix PRs this project
# had not measured, each next to the build its report was measured on:
#   SubtitleEdit/subtitleedit#15829  PR #15833  99f440ebf8  (control: SeConv 5.2.0, 2026-10-09)
#   aws/aws-cli#10648                PR #10649  c7999845b3  (control: Debian's awscli, 2026-09-16)
#   Exiv2/exiv2#9482                 PR #9504   8e2fc85ae2  (control: Debian's exiv2, 2026-09-05)
#   beancount/beancount#1051         PR #1054   cc591f7fcf  (control: Debian's beancount, 2026-09-06)
#   helm/helm#32709                  PR #32716  09cda512f9  (control: helm v4.3.0, 2026-10-02)
#   solvespace/solvespace#1783       PR #1784   a3b470a591  (control: v3.2 built, 2026-10-05)
# The base is 2026-10-09 follow-ups', copied. Network at build only; every run is `--network none`.
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

# ---- the controls: the builds the reports were measured on ----
RUN apt-get install -y --no-install-recommends libicu76 awscli exiv2 beancount ffmpeg imagemagick cmake ninja-build \
      bison flex meson libexpat1-dev zlib1g-dev libinih-dev libbrotli-dev libpng-dev libfreetype-dev libcairo2-dev \
      libjson-c-dev libfontconfig-dev > /tmp/apt-controls.log 2>&1 && echo "OK controls and build deps" || { echo "MISSING"; tail -3 /tmp/apt-controls.log; }
RUN set -eu; cd /tmp/dl; gh=https://github.com; \
    curl -fsSL -o seconv.tgz $gh/SubtitleEdit/subtitleedit/releases/download/v5.2.0/SeConv-Linux-ARM64.tar.gz; \
    mkdir -p /opt/seconv && tar xzf seconv.tgz -C /opt/seconv && f=$(find /opt/seconv -type f \( -name SeConv -o -name seconv \) | head -1) && chmod 755 "$f" && ln -sf "$f" /opt/bin/seconv; \
    curl -fsSL -o helm.tgz https://get.helm.sh/helm-v4.3.0-linux-arm64.tar.gz; mkdir -p x-helm && tar xzf helm.tgz -C x-helm && install -m 755 x-helm/linux-arm64/helm /opt/bin/helm; \
    cd /tmp/src && git clone -q --depth 1 -b v3.2 --recurse-submodules --shallow-submodules $gh/solvespace/solvespace \
      && cd solvespace && cmake -S . -B out -DCMAKE_BUILD_TYPE=Release -DENABLE_GUI=OFF -DENABLE_TESTS=OFF -DENABLE_OPENMP=OFF > /tmp/ss.log 2>&1 \
      && cmake --build out -j4 --target solvespace-cli >> /tmp/ss.log 2>&1 && install -m 755 out/bin/solvespace-cli /opt/bin/solvespace-cli; \
    echo "controls installed"

# ---- the fixes: each PR's head ----
# A commit fetched by its id from the repository that holds it (the PR's own branch where it is a fork).
RUN printf '#!/bin/sh\nset -eu\n# fetchsha <repo url> <commit> <dir>\nmkdir -p "$3" && cd "$3" && git init -q && git fetch -q --depth 1 "$1" "$2" && git checkout -q FETCH_HEAD\n' > /usr/local/bin/fetchsha && chmod 755 /usr/local/bin/fetchsha
RUN b() { name=$1; shift; ( set -e; "$@" ) > /tmp/build-$name.log 2>&1 && echo "BUILT $name" || { echo "FAILED $name"; tail -12 /tmp/build-$name.log; }; }; \
    gh=https://github.com; \
    b go sh -c "cd /tmp/dl && curl -fsSL -o go.tgz https://go.dev/dl/go1.26.9.linux-arm64.tar.gz && echo '4a97373d49fcacdcf3694fea368a500b00ee3e963974f3e7514132717632f052  go.tgz' | sha256sum -c && tar xzf go.tgz -C /opt"; \
    b helm-pr sh -c "fetchsha $gh/jdymitarai/helm 09cda512f9beddf39e6ca964c5bef93459e018b3 /tmp/src/helm && cd /tmp/src/helm && /opt/go/bin/go build -o /opt/bin/helm-pr ./cmd/helm"; \
    b aws-pr sh -c "python3 -m venv /opt/aws-pr && /opt/aws-pr/bin/pip install -q https://codeload.github.com/lazerg/aws-cli/tar.gz/c7999845b39cf3838928711916c3bb9e91e46111 && ln -s /opt/aws-pr/bin/aws /opt/bin/aws-pr"; \
    b beancount-pr sh -c "python3 -m venv /opt/bc-pr && /opt/bc-pr/bin/pip install -q https://codeload.github.com/ryanduguid/beancount/tar.gz/cc591f7fcf61977e8527e0caa477db355378b920 && ln -s /opt/bc-pr/bin/bean-format /opt/bin/bean-format-pr"; \
    b exiv2-pr sh -c "fetchsha $gh/jadhavgaurav/exiv2 8e2fc85ae210926a057cbffcaa1c451d01f6b706 /tmp/src/exiv2 && cd /tmp/src/exiv2 && cmake -S . -B out -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DEXIV2_BUILD_SAMPLES=OFF -DEXIV2_BUILD_UNIT_TESTS=OFF -DEXIV2_ENABLE_NLS=OFF -DEXIV2_ENABLE_INIH=OFF && cmake --build out --target exiv2 && install -m 755 out/bin/exiv2 /opt/bin/exiv2-pr"; \
    b solvespace-pr sh -c "fetchsha $gh/solvespace/solvespace a3b470a591a0f30bd7829fc753fff56c06c40e37 /tmp/src/ss-pr && cd /tmp/src/ss-pr && git submodule update -q --init --depth 1 --recursive && cmake -S . -B out -DCMAKE_BUILD_TYPE=Release -DENABLE_GUI=OFF -DENABLE_TESTS=OFF -DENABLE_OPENMP=OFF && cmake --build out -j4 --target solvespace-cli && install -m 755 out/bin/solvespace-cli /opt/bin/solvespace-cli-pr"; \
    b dotnet sh -c "cd /tmp/dl && curl -fsSL -o dotnet-install.sh https://dot.net/v1/dotnet-install.sh && bash dotnet-install.sh --channel 10.0 --install-dir /opt/dotnet"; \
    b seconv-pr sh -c "fetchsha $gh/SubtitleEdit/subtitleedit 99f440ebf85aa909dbd9e7d77b0c22a171cba4ee /tmp/src/se && cd /tmp/src/se && DOTNET_CLI_TELEMETRY_OPTOUT=1 /opt/dotnet/dotnet publish src/seconv/SeConv.csproj -c Release -r linux-arm64 --self-contained true -o /opt/seconv-pr && ln -s /opt/seconv-pr/seconv /opt/bin/seconv-pr"; \
    true
RUN { echo "seconv $(seconv 2>&1 | head -1)"; echo "seconv-pr $(seconv-pr 2>&1 | head -1)"; \
      echo "aws $(aws --version 2>&1)"; echo "aws-pr $(aws-pr --version 2>&1)"; \
      echo "exiv2 $(exiv2 --version 2>&1 | head -1)"; echo "exiv2-pr $(exiv2-pr --version 2>&1 | head -1)"; \
      echo "bean-format $(dpkg-query -W beancount 2>&1)"; echo "bean-format-pr $(/opt/bc-pr/bin/python -c 'import beancount; print(beancount.__version__)' 2>&1)"; \
      echo "helm $(helm version --short 2>&1)"; echo "helm-pr $(helm-pr version --short 2>&1)"; \
      echo "solvespace-cli $(ls -l /opt/bin/solvespace-cli 2>&1 | cut -c1-60)"; echo "solvespace-cli-pr $(ls -l /opt/bin/solvespace-cli-pr 2>&1 | cut -c1-60)"; } | tee /versions.txt
