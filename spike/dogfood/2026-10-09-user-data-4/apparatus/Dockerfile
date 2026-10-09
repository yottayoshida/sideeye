# The box for the 2026-10-09 user-data-4 rounds: Sideeye v1.10.0 installed the way
# docs/ci-quickstart.md tells a project to install it, and the candidates beside it.
# Shape copied from 2026-10-07 user-data-3's Dockerfile; its tool layers are not carried over —
# this run's candidates are added below the base as they clear the screen.
#
# What the candidates share with 2026-10-07: state that git does not hold, and not formatters.
# A FAIL measured on a packaged build is void if upstream has moved
# (spike/upstream-report-template.md), so a tool is taken from its own latest release where one
# exists for linux/arm64, and from Debian only where Debian ships the upstream release or the tool
# has none; each Debian one says so in SELECTION.md.
#
# Built by build.sh. Network at build only; every gate, explore and replay runs `--network none`.
# linux/arm64 (this machine's Docker).
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 python3-venv python3-dev ca-certificates procps bash git curl unzip xz-utils bzip2 \
      build-essential pkg-config

COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

# Runtimes, one line per package, OK or MISSING. libfaketime pins a clock when a define's gate asks.
RUN for p in nodejs npm ruby ruby-dev php-cli php-xml php-mbstring golang-go libfaketime faketime; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt

ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    PATH=/opt/bin:/opt/py/bin:/usr/local/bin:/root/go/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
RUN mkdir -p /opt/bin /tmp/dl && python3 -m venv /opt/py

COPY install-sideeye.sh /opt/install-sideeye.sh
RUN sh /opt/install-sideeye.sh v1.10.0 /opt/se > /install.path 2>/install.log; \
    echo "installer exit: $?"; \
    echo "stdout: [$(cat /install.path)]"; \
    grep -E 'digest|sideeye ' /install.log || true
RUN "$(cat /install.path)" version


# ---- candidate layers, added as the screen clears them ----

# First layer, after the run's own screen and scout 1 (transcripts/fresh-screen-1.txt,
# word-recheck-{1,2}.txt, stars-0.txt, scout-1.txt, receipts/rule11-bug-reports-1.txt). Each from
# its own latest release for linux/arm64 as GitHub and PyPI answered on 2026-10-09: scw 2.65.1,
# f2 2.2.2, SeConv (Subtitle Edit) 5.2.0 — the stable tag; the betas above it are one a day —
# and opentimelineio 0.18.1 (PyPI's latest; GitHub marks the tag a pre-release). OpenImageIO is
# Debian trixie's openimageio-tools 2.5.18: upstream's 3.2.1.1 ships no binary and no iconvert in
# its wheel, and a source build needs the whole dependency tree, so a FAIL on it is read against
# upstream main's iconvert.cpp before anything is said (spike/upstream-report-template.md).
RUN apt-get install -y --no-install-recommends openimageio-tools libicu76 > /tmp/apt-oiio.log 2>&1 && echo "OK openimageio-tools" || { echo "MISSING openimageio-tools"; tail -3 /tmp/apt-oiio.log; }
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/scaleway/scaleway-cli/releases/download/v2.65.1/scaleway-cli_2.65.1_linux_arm64 scw; \
    get $gh/ayoisaiah/f2/releases/download/v2.2.2/f2_2.2.2_linux_arm64.tar.gz f2.tgz; \
    get $gh/SubtitleEdit/subtitleedit/releases/download/v5.2.0/SeConv-Linux-ARM64.tar.gz seconv.tgz; \
    install -m 755 scw /opt/bin/scw; \
    mkdir -p x-f2 && tar xzf f2.tgz -C x-f2 && install -m 755 "$(find x-f2 -type f -name f2 | head -1)" /opt/bin/f2; \
    mkdir -p /opt/seconv && tar xzf seconv.tgz -C /opt/seconv && f=$(find /opt/seconv -type f \( -name SeConv -o -name seconv \) | head -1) && chmod 755 "$f" && ln -sf "$f" /opt/bin/seconv && echo "seconv <- $f"; \
    ls -l /opt/bin
RUN /opt/py/bin/pip install --no-cache-dir opentimelineio==0.18.1 > /tmp/pip-otio.log 2>&1 && echo "OK opentimelineio" || { echo "FAILED opentimelineio"; tail -3 /tmp/pip-otio.log; }
RUN { echo "scw $(scw version 2>&1 | head -1)"; echo "f2 $(f2 --version 2>&1 | head -1)"; echo "seconv $(seconv 2>&1 | head -1)"; echo "iconvert $(iconvert --help 2>&1 | head -1)"; echo "otiotool $(otiotool --version 2>&1 | head -1)"; } | tee /versions.txt

# Second layer, after scout 3 (transcripts/scout-3.txt, word-recheck-3.txt, receipts/rule11-bug-reports-2.txt):
# cookcli 0.38.0 (its aarch64 musl tarball), MCA Selector 2.9 (its aarch64 .deb, a jlink runtime
# inside), and arkenfox's prefsCleaner.sh at tag 144.0 (commit bb45863be796d331717e2b5d6e490f0d3e3cf93f;
# the repository is the user.js file and three scripts, with no release asset). zim is out
# (SELECTION.md). sheets and organize failed rule 11.
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/cooklang/cookcli/releases/download/v0.38.0/cook-aarch64-unknown-linux-musl.tar.gz cook.tgz; \
    get $gh/Querz/mcaselector/releases/download/2.9/mcaselector-2.9-aarch64.deb mcaselector.deb; \
    get https://raw.githubusercontent.com/arkenfox/user.js/bb45863be796d331717e2b5d6e490f0d3e3cf93f/prefsCleaner.sh prefsCleaner.sh; \
    get https://raw.githubusercontent.com/arkenfox/user.js/bb45863be796d331717e2b5d6e490f0d3e3cf93f/user.js user.js; \
    mkdir -p x-cook && tar xzf cook.tgz -C x-cook && install -m 755 "$(find x-cook -type f -name cook | head -1)" /opt/bin/cook; \
    mkdir -p /opt/arkenfox && install -m 755 prefsCleaner.sh /opt/arkenfox/prefsCleaner.sh && install -m 644 user.js /opt/arkenfox/user.js; \
    apt-get install -y --no-install-recommends xdg-utils > /tmp/apt-xdg.log 2>&1; \
    (dpkg -i mcaselector.deb > /tmp/dpkg-mca.log 2>&1 || apt-get install -y -f > /tmp/apt-mca.log 2>&1) && echo "OK mcaselector" || { echo "FAILED mcaselector"; tail -3 /tmp/dpkg-mca.log; }; \
    ls -l /opt/bin; dpkg -L mcaselector 2>/dev/null | grep -E 'bin/|\.jar$' | head -5
RUN { echo "cook $(cook --version 2>&1 | head -1)"; echo "prefsCleaner $(sha256sum /opt/arkenfox/prefsCleaner.sh | cut -c1-16) $(grep -m1 -i 'version' /opt/arkenfox/prefsCleaner.sh)"; echo "mcaselector $(ls /opt/mcaselector/bin 2>/dev/null | head -3 | tr '\n' ' ')"; } | tee -a /versions.txt

# Third layer, after scouts 2 and 4 (transcripts/scout-2.txt, scout-4.txt, fresh-screen-2.txt,
# word-recheck-4.txt, receipts/rule11-bug-reports-3.txt, rule11-relabel-3.txt): nmctl 1.7.0
# (netmaker's linux-arm64 asset), yarn 4.18.1 (@yarnpkg/cli-dist from npm), sindresorhus's
# trash-cli from npm (its latest as the registry answered), and Debian's softhsm2 2.6.1 (upstream's
# tag is 2.7.0; SELECTION.md says what that means for a FAIL).
RUN apt-get install -y --no-install-recommends softhsm2 opensc > /tmp/apt-softhsm.log 2>&1 && echo "OK softhsm2" || { echo "MISSING softhsm2"; tail -3 /tmp/apt-softhsm.log; }
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/gravitl/netmaker/releases/download/v1.7.0/nmctl-linux-arm64 nmctl; install -m 755 nmctl /opt/bin/nmctl
RUN npm install -g --no-fund --no-audit @yarnpkg/cli-dist@4.18.1 trash-cli > /tmp/npm-third.log 2>&1 && echo "OK yarn trash-cli" || { echo "FAILED yarn/trash-cli"; tail -3 /tmp/npm-third.log; }
RUN { echo "nmctl $(nmctl version 2>&1 | head -1)"; echo "yarn $(yarn --version 2>&1 | head -1)"; echo "trash $(npm ls -g trash-cli 2>/dev/null | grep trash-cli)"; echo "softhsm2 $(softhsm2-util --version 2>&1 | head -1)"; } | tee -a /versions.txt

# Fourth layer, after scout 4's second half (transcripts/scout-4.txt, receipts/rule11-bug-reports-4.txt):
# libdeflate 1.26 built from its release tarball with cmake (no binary asset); its gzip
# replaces the input with the .gz unless -k is given (programs/gzip.c).
RUN apt-get install -y --no-install-recommends cmake > /tmp/apt-cmake.log 2>&1 && echo "OK cmake" || echo "MISSING cmake"
RUN set -u; cd /tmp/dl; curl -fsSL -o libdeflate.tgz https://github.com/ebiggers/libdeflate/archive/refs/tags/v1.26.tar.gz && mkdir -p x-libdeflate && tar xzf libdeflate.tgz -C x-libdeflate --strip-components=1 && \
    cmake -S x-libdeflate -B x-libdeflate/build -DCMAKE_BUILD_TYPE=Release -DLIBDEFLATE_BUILD_STATIC_LIB=OFF > /tmp/libdeflate-cmake.log 2>&1 && cmake --build x-libdeflate/build -j"$(nproc)" > /tmp/libdeflate-make.log 2>&1 && \
    install -m 755 x-libdeflate/build/programs/libdeflate-gzip /opt/bin/libdeflate-gzip && install -m 755 x-libdeflate/build/libdeflate.so* /usr/local/lib/ 2>/dev/null; ldconfig; \
    echo "libdeflate-gzip $(libdeflate-gzip --version 2>&1 | head -1)" | tee -a /versions.txt || { echo "FAILED libdeflate"; tail -3 /tmp/libdeflate-make.log; }

# Fifth layer, after scout 5 and the run's own screens (transcripts/scout-5.txt, fresh-screen-3..6.txt,
# receipts/rule11-bug-reports-5.txt, -6.txt): stack 3.11.1, carapace-bin 1.8.0 and cabal-install
# 3.18.2.0 from their linux-aarch64 release assets; hunspell 1.7.5 built from its release tarball
# (trixie ships 1.7.2) with trixie's en_US dictionary; chdman (mame-tools 0.276) and Kvantum
# (qt6-style-kvantum 1.1.4) from Debian — upstream is 0.289 and 1.1.8, and a source build of
# either is MAME's or a Qt6 tree, so a FAIL on them is read against upstream's source before
# anything is said, as OpenImageIO's.
RUN apt-get install -y --no-install-recommends mame-tools qt6-style-kvantum hunspell-en-us libgmp10 > /tmp/apt-l5.log 2>&1 && echo "OK mame-tools kvantum hunspell-en-us" || { echo "MISSING layer-5 apt"; tail -3 /tmp/apt-l5.log; }
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/commercialhaskell/stack/releases/download/v3.11.1/stack-3.11.1-linux-aarch64.tar.gz stack.tgz; \
    get $gh/carapace-sh/carapace-bin/releases/download/v1.8.0/carapace-bin_1.8.0_linux_arm64.tar.gz carapace.tgz; \
    get $gh/haskell/cabal/releases/download/cabal-install-v3.18.2.0/cabal-install-3.18.2.0-aarch64-linux-unknown.tar.xz cabal.txz; \
    get $gh/hunspell/hunspell/releases/download/v1.7.5/hunspell-1.7.5.tar.gz hunspell.tgz; \
    mkdir -p x-stack x-carapace x-cabal x-hunspell; \
    tar xzf stack.tgz -C x-stack && install -m 755 "$(find x-stack -type f -name stack | head -1)" /opt/bin/stack; \
    tar xzf carapace.tgz -C x-carapace && install -m 755 "$(find x-carapace -type f -name carapace | head -1)" /opt/bin/carapace; \
    tar xJf cabal.txz -C x-cabal && install -m 755 "$(find x-cabal -type f -name cabal | head -1)" /opt/bin/cabal; \
    tar xzf hunspell.tgz -C x-hunspell --strip-components=1 && cd x-hunspell && ./configure --prefix=/opt/hunspell > /tmp/hunspell-configure.log 2>&1 && make -j"$(nproc)" > /tmp/hunspell-make.log 2>&1 && make install > /tmp/hunspell-install.log 2>&1 && ln -sf /opt/hunspell/bin/hunspell /opt/bin/hunspell && echo "hunspell built" || { echo "FAILED hunspell"; tail -5 /tmp/hunspell-make.log /tmp/hunspell-configure.log; }
RUN { echo "stack $(stack --version 2>&1 | head -1)"; echo "carapace $(carapace --version 2>&1 | head -1)"; echo "cabal $(cabal --version 2>&1 | head -1)"; echo "hunspell $(hunspell -v 2>&1 | head -1)"; echo "chdman $(chdman 2>&1 | head -1)"; echo "kvantummanager $(ls /usr/bin/kvantummanager 2>&1)"; } | tee -a /versions.txt

# Sixth layer, from the run's own screen (fresh-screen-8.txt, stars-4.txt, receipts/rule11-bug-reports-7.txt):
# buildx 0.38.0 and zvm 0.9.1 from their linux-arm64 release assets.
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/docker/buildx/releases/download/v0.38.0/buildx-v0.38.0.linux-arm64 buildx; install -m 755 buildx /opt/bin/buildx; \
    get $gh/tristanisham/zvm/releases/download/v0.9.1/zvm-linux-arm64.tar zvm.tar; mkdir -p x-zvm && tar xf zvm.tar -C x-zvm && install -m 755 "$(find x-zvm -type f -name zvm | head -1)" /opt/bin/zvm; \
    { echo "buildx $(buildx version 2>&1 | head -1)"; echo "zvm $(zvm version 2>&1 | head -1)"; } | tee -a /versions.txt

# Seventh layer, after scout 7 (transcripts/scout-7.txt, fresh-screen-12.txt): ifcpatch 0.9.0 and
# ifcopenshell 0.9.0 from PyPI (its cp313 aarch64 wheel); CKAN 1.36.4 from its release .deb on
# trixie's Mono 6.12; Hydrogen's h2cli from trixie (1.2.2; upstream is 1.2.7, a Qt and audio source
# build — a FAIL on it is read against upstream's source first); ROOT 6.40.04 from conda-forge through
# micromamba 2.9.0 (ROOT publishes no linux-aarch64 binary of its own), in its own prefix.
RUN /opt/py/bin/pip install --no-cache-dir ifcopenshell==0.9.0 ifcpatch==0.9.0 > /tmp/pip-ifc.log 2>&1 && echo "OK ifcpatch" || { echo "FAILED ifcpatch"; tail -3 /tmp/pip-ifc.log; }
RUN apt-get install -y --no-install-recommends hydrogen mono-runtime libmono-system-core4.0-cil libmono-system-componentmodel-composition4.0-cil > /tmp/apt-l7.log 2>&1 && echo "OK hydrogen mono" || { echo "MISSING hydrogen/mono"; tail -3 /tmp/apt-l7.log; }
RUN set -u; cd /tmp/dl; curl -fsSL -o ckan.deb https://github.com/KSP-CKAN/CKAN/releases/download/v1.36.4/ckan_1.36.4.26132_all.deb && \
    (dpkg -i ckan.deb > /tmp/dpkg-ckan.log 2>&1 || apt-get install -y -f --no-install-recommends > /tmp/apt-ckan.log 2>&1) && echo "OK ckan" || { echo "FAILED ckan"; tail -3 /tmp/dpkg-ckan.log; }
RUN set -u; cd /tmp/dl; curl -fsSL -o micromamba https://github.com/mamba-org/micromamba-releases/releases/download/2.9.0-0/micromamba-linux-aarch64 && install -m 755 micromamba /opt/bin/micromamba && \
    MAMBA_ROOT_PREFIX=/opt/mamba micromamba create -y -p /opt/root -c conda-forge root=6.40.04 > /tmp/mamba-root.log 2>&1 && echo "OK root" || { echo "FAILED root"; tail -5 /tmp/mamba-root.log; }
# Eighth layer, after scout 6 (transcripts/scout-6.txt, fresh-screen-13.txt, receipts/rule11-bug-reports-9.txt):
# fly 8.3.1 (Concourse), kafkactl 5.20.0, rpk 26.2.2 (Redpanda) and atac 0.23.1 (its musl build), each
# from its linux-arm64 release asset.
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/concourse/concourse/releases/download/v8.3.1/fly-8.3.1-linux-arm64.tgz fly.tgz; \
    get $gh/deviceinsight/kafkactl/releases/download/v5.20.0/kafkactl_5.20.0_linux_arm64.tar.gz kafkactl.tgz; \
    get $gh/redpanda-data/redpanda/releases/download/v26.2.2/rpk-linux-arm64.zip rpk.zip; \
    get $gh/Julien-cpsn/ATAC/releases/download/v0.23.1/atac-v0.23.1-aarch64-unknown-linux-musl.tar.gz atac.tgz; \
    for t in fly kafkactl atac; do mkdir -p x-$t && tar xzf $t.tgz -C x-$t && install -m 755 "$(find x-$t -type f -name $t | head -1)" /opt/bin/$t && echo "bin $t"; done; \
    mkdir -p x-rpk && unzip -q rpk.zip -d x-rpk && install -m 755 "$(find x-rpk -type f -name rpk | head -1)" /opt/bin/rpk && echo "bin rpk"; \
    { echo "fly $(fly --version 2>&1 | head -1)"; echo "kafkactl $(kafkactl version 2>&1 | head -1)"; echo "rpk $(rpk version 2>&1 | head -1)"; echo "atac $(atac --version 2>&1 | head -1)"; } | tee -a /versions.txt
RUN { echo "ifcpatch $(/opt/py/bin/pip show ifcpatch 2>/dev/null | grep ^Version)"; echo "h2cli $(h2cli --version 2>&1 | head -1)"; echo "ckan $(ckan version 2>&1 | head -1)"; echo "root $(/opt/root/bin/root-config --version 2>&1)"; ls /opt/root/bin | grep -E '^root(rm|ls|mkdir|cp|mv)$' | tr '\n' ' '; echo; } | tee -a /versions.txt

