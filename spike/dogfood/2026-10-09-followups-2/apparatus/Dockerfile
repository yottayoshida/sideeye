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

# ---- the second group: fifteen targets no campaign carried to a verdict, at the versions their
# last campaigns measured, each to be taken one next step further on v1.10.0 ----
RUN apt-get install -y --no-install-recommends ruby ruby-dev maildir-utils softhsm2 opensc bat ocrmypdf tesseract-ocr-eng ghostscript ccache \
      > /tmp/apt-group2.log 2>&1 && echo "OK group-2 apt" || { echo "MISSING"; tail -3 /tmp/apt-group2.log; }
RUN gem install --no-document hexapdf -v 1.11.0 > /tmp/gem-hexapdf.log 2>&1; echo "gem hexapdf exit: $?"; \
    /opt/py/bin/pip install --no-cache-dir esptool==5.4.0 > /tmp/pip-esptool.log 2>&1; echo "pip esptool exit: $?"; \
    npm install -g --no-fund --no-audit firebase-tools@15.32.1 > /tmp/npm-firebase.log 2>&1; echo "npm firebase-tools exit: $?"
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get https://downloads.getmonero.org/cli/monero-linux-armv8-v0.18.5.1.tar.bz2 monero.tbz; \
    get $gh/infracost/infracost/releases/download/v0.10.46/infracost-linux-arm64.tar.gz infracost.tgz; \
    get $gh/PlakarKorp/plakar/releases/download/v1.1.7/plakar_1.1.7_linux_arm64.tar.gz plakar.tgz; \
    get $gh/rfjakob/gocryptfs/releases/download/v2.6.1/gocryptfs_v2.6.1_linux-static_arm64.tar.gz gcf.tgz; \
    mkdir -p x-monero x-infracost x-plakar x-gcf; tar xjf monero.tbz -C x-monero; tar xzf infracost.tgz -C x-infracost; tar xzf plakar.tgz -C x-plakar; tar xzf gcf.tgz -C x-gcf; \
    install -m 755 "$(find x-monero -type f -name monero-wallet-cli | head -1)" /opt/bin/monero-wallet-cli; \
    install -m 755 "$(find x-infracost -type f -name 'infracost*' | head -1)" /opt/bin/infracost; \
    install -m 755 "$(find x-plakar -type f -name plakar | head -1)" /opt/bin/plakar; \
    install -m 755 x-gcf/gocryptfs /opt/bin/gocryptfs; ls -l /opt/bin | wc -l
RUN cd /tmp/src && curl -fsSL https://github.com/xmake-io/xmake/releases/download/v3.1.1/xmake-v3.1.1.tar.gz | tar xz \
    && cd xmake-3.1.1 && ./configure > /tmp/build-xmake.log 2>&1 && make -j4 >> /tmp/build-xmake.log 2>&1 && make install PREFIX=/usr/local >> /tmp/build-xmake.log 2>&1; \
    echo "xmake build exit: $?"; tail -2 /tmp/build-xmake.log
RUN { echo "hexapdf $(hexapdf version 2>&1 | head -1)"; echo "mu $(mu --version 2>&1 | head -1)"; echo "monero $(monero-wallet-cli --version 2>&1 | head -1)"; \
      echo "infracost $(infracost --version 2>&1 | head -1)"; echo "xmake $(XMAKE_ROOT=y xmake --version 2>&1 | head -1)"; echo "esptool $(esptool version 2>&1 | tail -1)"; \
      echo "plakar $(plakar version 2>&1 | head -1)"; echo "softhsm2 $(softhsm2-util --version 2>&1)"; echo "bat $(batcat --version 2>&1)"; echo "meson $(meson --version 2>&1)"; \
      echo "ocrmypdf $(ocrmypdf --version 2>&1)"; echo "ccache $(ccache --version 2>&1 | head -1)"; echo "git $(git --version)"; echo "firebase $(firebase --version 2>&1 | tail -1)"; \
      echo "gocryptfs $(gocryptfs -version 2>&1 | head -1)"; } | tee -a /versions.txt

RUN install -m 755 /tmp/dl/x-gcf/gocryptfs-xray /opt/bin/gocryptfs-xray && echo "gocryptfs-xray installed"
