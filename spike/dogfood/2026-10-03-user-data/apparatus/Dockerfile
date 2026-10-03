# The box for the 2026-10-03 user-data rounds: Sideeye v1.7.0 installed the way
# docs/ci-quickstart.md tells a project to install it, and the candidates beside it.
# Shape copied from 2026-09-28 shipped-v170's Dockerfile.
#
# What differs from that box: the candidates are tools whose state is user data that git does
# not hold (a wallet, a spreadsheet, photos, a mail folder, a sequencing file, a shell history),
# and a C/C++ candidate is BUILT FROM ITS LATEST UPSTREAM RELEASE rather than taken from Debian,
# because trixie lags most of them (rdfind 1.6.0 vs 1.8.0, samtools 1.21 vs 1.24, kakoune
# 2024.05 vs 2026.05) and a FAIL measured on a packaged build is void if upstream has moved
# (spike/upstream-report-template.md). Two are Debian's for now and say so: mu (maildir-utils)
# and util-linux's hardlink.
#
# Built by build.sh. Network at build only; every gate, explore and replay runs `--network none`.
# linux/arm64 (this machine's Docker).
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 python3-venv python3-dev ca-certificates procps bash git curl unzip xz-utils bzip2 \
      build-essential pkg-config autoconf automake cmake bison

COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

# Runtime and build dependencies, one line per package, OK or MISSING.
RUN for p in nodejs npm ruby ruby-dev lua5.4 nettle-dev libncurses-dev libreadline-dev zlib1g-dev libbz2-dev \
             liblzma-dev libsecp256k1-dev libjpeg-dev libxml2-dev libzip-dev jpegoptim optipng \
             maildir-utils util-linux busybox-static; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt

ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Release binaries, each version pinned in its URL. One line per tool, OK or MISSING.
RUN set -u; mkdir -p /opt/bin /tmp/dl; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/Yakitrak/notesmd-cli/releases/download/v0.3.7/notesmd-cli_0.3.7_linux_arm64.tar.gz notesmd.tgz; \
    get $gh/qarmin/czkawka/releases/download/12.0.2/linux_czkawka_cli_arm64 czkawka_cli; \
    get $gh/upx/upx/releases/download/v5.2.1/upx-5.2.1-arm64_linux.tar.xz upx.txz; \
    get $gh/NixOS/patchelf/releases/download/0.19.2/patchelf-0.19.2-aarch64.tar.gz patchelf.tgz; \
    get $gh/SuperCuber/dotter/releases/download/v0.13.5/dotter-linux-arm64-musl dotter; \
    get $gh/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.8.2/kustomize_v5.8.2_linux_arm64.tar.gz kustomize.tgz; \
    get $gh/thomasschafer/scooter/releases/download/v0.9.1/scooter-v0.9.1-aarch64-unknown-linux-musl.tar.gz scooter.tgz; \
    get https://raw.githubusercontent.com/skywind3000/z.lua/1.8.26/z.lua z.lua; \
    ls -l /tmp/dl
RUN set -u; cd /tmp/dl; \
    for t in notesmd patchelf kustomize scooter; do mkdir -p x-$t && tar xzf $t.tgz -C x-$t && echo "untar $t: ok" || echo "untar $t: FAILED"; done; \
    mkdir -p x-upx && tar xJf upx.txz -C x-upx && echo "untar upx: ok"; \
    for b in czkawka_cli dotter; do install -m 755 $b /opt/bin/$b; done; \
    install -m 644 z.lua /opt/bin/z.lua; \
    for n in notesmd-cli patchelf kustomize scooter upx; do \
      f=$(find /tmp/dl/x-* -type f -name "$n" | head -1); \
      [ -n "$f" ] && install -m 755 "$f" /opt/bin/$n && echo "bin $n <- $f" || echo "bin $n: NOT FOUND"; \
    done; ls -l /opt/bin

# C / C++ candidates from their latest upstream release. Each build's tail is kept.
RUN set -u; mkdir -p /tmp/src; cd /tmp/src; gh=https://github.com; \
    b() { name=$1; shift; ( set -e; "$@" ) > /tmp/build-$name.log 2>&1 && echo "BUILT $name" || { echo "FAILED $name"; tail -5 /tmp/build-$name.log; }; }; \
    b rdfind sh -c "curl -fsSL $gh/pauldreik/rdfind/releases/download/releases%2F1.8.0/rdfind-1.8.0.tar.gz | tar xz && cd rdfind-1.8.0 && ./configure --prefix=/usr/local && make -j4 && make install"; \
    b hstr sh -c "curl -fsSL $gh/dvorka/hstr/releases/download/v3.2/hstr-3.2.0-tarball.tgz | tar xz && cd \$(ls -d hstr*/ | head -1) && ./configure --prefix=/usr/local && make -j4 && make install"; \
    b samtools sh -c "curl -fsSL $gh/samtools/samtools/releases/download/1.24/samtools-1.24.tar.bz2 | tar xj && cd samtools-1.24 && ./configure --prefix=/usr/local --without-curses --disable-libcurl && make -j4 && make install"; \
    b bzip3 sh -c "curl -fsSL $gh/iczelia/bzip3/releases/download/1.5.4/bzip3-1.5.4.tar.gz | tar xz && cd bzip3-1.5.4 && ./configure --prefix=/usr/local && make -j4 && make install && ldconfig"; \
    b sc-im sh -c "curl -fsSL $gh/andmarti1424/sc-im/archive/refs/tags/v0.8.5.tar.gz | tar xz && cd sc-im-0.8.5/src && make -j4 prefix=/usr/local && make install prefix=/usr/local"; \
    b brotli sh -c "curl -fsSL $gh/google/brotli/archive/refs/tags/v1.2.0.tar.gz | tar xz && cd brotli-1.2.0 && cmake -S . -B out -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local && cmake --build out -j4 && cmake --install out && ldconfig"; \
    b kakoune sh -c "curl -fsSL $gh/mawww/kakoune/releases/download/v2026.05.21/kakoune-2026.05.21.tar.bz2 | tar xj && cd kakoune-2026.05.21 && make -j4 && make install PREFIX=/usr/local"; \
    true

ENV PATH=/opt/bin:/opt/py/bin:/usr/local/bin:$PATH

# Python candidates, versions pinned. The first build also installed Electrum, organize and imgp;
# Electrum's electrum_ecc wheel failed to build and took the whole install down with it, and all
# three had already left at rule 11, so they are not installed (transcripts/build-first.txt).
RUN python3 -m venv /opt/py \
    && /opt/py/bin/pip install --no-cache-dir \
         visidata==3.4 dotdrop==1.17.0 > /tmp/pip.log 2>&1; \
    echo "pip exit: $?"; tail -2 /tmp/pip.log
RUN gem install --no-document doing -v 2.1.124 > /tmp/gem-doing.log 2>&1; echo "gem doing exit: $?"; tail -2 /tmp/gem-doing.log
RUN gem install --no-document hexapdf -v 1.11.0 > /tmp/gem-hexapdf.log 2>&1; echo "gem hexapdf exit: $?"; tail -2 /tmp/gem-hexapdf.log
RUN npm install -g --no-fund --no-audit @dotenvx/dotenvx@2.32.4 mapshaper@0.7.72 > /tmp/npm.log 2>&1; echo "npm exit: $?"; tail -2 /tmp/npm.log
# The fourth name screen's two more: snapraid from its release, nushell's aarch64 gnu build.
RUN set -u; cd /tmp/src; \
    ( curl -fsSL https://github.com/amadvance/snapraid/releases/download/v14.10/snapraid-14.10.tar.gz | tar xz && cd snapraid-14.10 && ./configure --prefix=/usr/local && make -j4 && make install ) > /tmp/build-snapraid.log 2>&1 && echo "BUILT snapraid" || { echo "FAILED snapraid"; tail -5 /tmp/build-snapraid.log; }; \
    curl -fsSL -o /tmp/dl/nu.tgz https://github.com/nushell/nushell/releases/download/0.116.0/nu-0.116.0-aarch64-unknown-linux-gnu.tar.gz \
      && mkdir -p /tmp/dl/x-nu && tar xzf /tmp/dl/nu.tgz -C /tmp/dl/x-nu \
      && install -m 755 "$(find /tmp/dl/x-nu -type f -name nu | head -1)" /opt/bin/nu && echo "OK nu" || echo "MISSING nu"

COPY install-sideeye.sh /opt/install-sideeye.sh
RUN sh /opt/install-sideeye.sh v1.7.0 /opt/se > /install.path 2>/install.log; \
    echo "installer exit: $?"; \
    echo "stdout: [$(cat /install.path)]"; \
    grep -E 'digest|sideeye ' /install.log || true
RUN "$(cat /install.path)" version

# What was installed, as the tools report themselves. Each probe gets 10 s and no stdin: the first
# build hung here on one of them for over an hour, and the second (each under `timeout`, piped to
# `head`) hung again: a probe's grandchild kept the pipe open. Output goes to a file now.
RUN v() { n=$1; shift; timeout -k 2 10 "$@" </dev/null >/tmp/v.out 2>&1; echo "$n: $(head -1 /tmp/v.out) (rc $?)"; }; { \
      v sideeye "$(cat /install.path)" version; v visidata vd --version; v dotdrop dotdrop --version; \
      v doing doing --version; v notesmd-cli notesmd-cli --version; v upx upx --version; \
      v dotter dotter --version; v kustomize kustomize version; v scooter scooter --version; \
      v z.lua lua5.4 /opt/bin/z.lua --version; v rdfind rdfind -v; v samtools samtools --version; \
      v bzip3 bzip3 --version; v sc-im sc-im --version; v kakoune kak -version; v mu mu --version; \
      v snapraid snapraid --version; v nu nu --version; v dotenvx dotenvx --version; \
      v mapshaper mapshaper --version; v hexapdf hexapdf version; v perl perl -e 'print $^V'; \
      } > /versions.txt; cat /versions.txt

# Added after the fifth name screen: gocryptfs, its static arm64 release.
RUN curl -fsSL -o /tmp/gcf.tgz https://github.com/rfjakob/gocryptfs/releases/download/v2.6.1/gocryptfs_v2.6.1_linux-static_arm64.tar.gz \
      && mkdir -p /tmp/x-gcf && tar xzf /tmp/gcf.tgz -C /tmp/x-gcf && install -m 755 /tmp/x-gcf/gocryptfs /opt/bin/gocryptfs \
      && echo "gocryptfs: $(gocryptfs -version | head -1)" >> /versions.txt && tail -1 /versions.txt

# Added after the sixth name screen. kubectx, OpenTofu and DwarFS from their arm64 releases;
# flatpak and podman from Debian for the gate only (trixie 1.16.6 / 5.4.2 against upstream
# 1.18.4 / 6.1.3 — a report would be measured on upstream first); libfaketime for the clock pin
# docs/apparatus.md describes (through /etc/ld.so.preload, written per run, never LD_PRELOAD).
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/ahmetb/kubectx/releases/download/v0.11.0/kubectx_v0.11.0_linux_arm64.tar.gz kubectx.tgz; \
    get $gh/opentofu/opentofu/releases/download/v1.13.1/tofu_1.13.1_linux_arm64.tar.gz tofu.tgz; \
    get $gh/mhx/dwarfs/releases/download/v0.15.8/dwarfs-0.15.8-Linux-aarch64.tar.xz dwarfs.txz; \
    for t in kubectx tofu; do mkdir -p x-$t && tar xzf $t.tgz -C x-$t; done; mkdir -p x-dwarfs && tar xJf dwarfs.txz -C x-dwarfs; \
    for n in kubectx tofu mkdwarfs dwarfsck dwarfsextract; do f=$(find /tmp/dl/x-kubectx /tmp/dl/x-tofu /tmp/dl/x-dwarfs/*/bin -type f -name "$n" | head -1); \
      [ -n "$f" ] && install -m 755 "$f" /opt/bin/$n && echo "bin $n <- $f" || echo "bin $n: NOT FOUND"; done
RUN for p in flatpak podman libfaketime faketime; do apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; done
RUN v() { n=$1; shift; timeout -k 2 10 "$@" </dev/null >/tmp/v.out 2>&1; echo "$n: $(head -1 /tmp/v.out) (rc $?)"; }; { \
      v kubectx kubectx --version; v tofu tofu version; v mkdwarfs mkdwarfs -h; \
      v flatpak flatpak --version; v podman podman --version; v faketime faketime --version; } >> /versions.txt; tail -6 /versions.txt

# Added when rule 11 was re-read at 2026-09-28's bar (SELECTION.md, "Rule 11"): Electrum in a
# venv of its own, told to use Debian's libsecp256k1 rather than build one (the first box's
# failure); hcloud, doctl, argocd, kubecm and minikube from their arm64 releases; Babel from PyPI;
# transmission-edit from Debian (4.1.0~beta2 against upstream 4.1.3 — rebuilt before any report).
RUN python3 -m venv /opt/el && ELECTRUM_ECC_DONT_COMPILE=1 /opt/el/bin/pip install --no-cache-dir \
      "https://download.electrum.org/4.8.2/Electrum-4.8.2.tar.gz" cryptography > /tmp/pip-el.log 2>&1; \
    echo "pip electrum exit: $?"; ln -s /opt/el/bin/electrum /opt/bin/electrum; \
    /opt/py/bin/pip install --no-cache-dir babel==2.18.0 > /tmp/pip-babel.log 2>&1; echo "pip babel exit: $?"
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/hetznercloud/cli/releases/download/v1.69.0/hcloud-linux-arm64.tar.gz hcloud.tgz; \
    get $gh/digitalocean/doctl/releases/download/v1.177.0/doctl-1.177.0-linux-arm64.tar.gz doctl.tgz; \
    get $gh/sunny0826/kubecm/releases/download/v0.35.1/kubecm_v0.35.1_Linux_arm64.tar.gz kubecm.tgz; \
    get $gh/argoproj/argo-cd/releases/download/v3.5.3/argocd-linux-arm64 argocd; \
    get $gh/kubernetes/minikube/releases/download/v1.39.0/minikube-linux-arm64 minikube; \
    for t in hcloud doctl kubecm; do mkdir -p y-$t && tar xzf $t.tgz -C y-$t; f=$(find y-$t -type f -name $t | head -1); \
      [ -n "$f" ] && install -m 755 "$f" /opt/bin/$t && echo "bin $t" || echo "bin $t: NOT FOUND"; done; \
    install -m 755 argocd /opt/bin/argocd; install -m 755 minikube /opt/bin/minikube
RUN apt-get install -y --no-install-recommends transmission-cli > /tmp/apt-tr.log 2>&1 && echo "OK transmission-cli" || echo "MISSING transmission-cli"
RUN v() { n=$1; shift; timeout -k 2 10 "$@" </dev/null >/tmp/v.out 2>&1; echo "$n: $(head -1 /tmp/v.out) (rc $?)"; }; { \
      v electrum electrum version --offline; v pybabel pybabel --version; v hcloud hcloud version; v doctl doctl version; \
      v kubecm kubecm version; v argocd argocd version --client --short; v minikube minikube version --short; \
      v transmission-edit transmission-edit --version; } >> /versions.txt; tail -8 /versions.txt

# The last two, both back at 2026-09-28's rule-11 bar: luarocks from its v3.13.0 source against
# Debian's Lua 5.4, and bibtex-tidy from npm.
RUN apt-get install -y --no-install-recommends liblua5.4-dev > /tmp/apt-lua.log 2>&1; \
    ( cd /tmp/src && curl -fsSL https://github.com/luarocks/luarocks/archive/refs/tags/v3.13.0.tar.gz | tar xz \
      && cd luarocks-3.13.0 && ./configure --prefix=/usr/local --lua-version=5.4 && make && make install ) > /tmp/build-luarocks.log 2>&1 \
      && echo "BUILT luarocks" || { echo "FAILED luarocks"; tail -5 /tmp/build-luarocks.log; }
RUN npm install -g --no-fund --no-audit bibtex-tidy@1.15.1 > /tmp/npm3.log 2>&1; echo "npm bibtex-tidy exit: $?"
RUN v() { n=$1; shift; timeout -k 2 10 "$@" </dev/null >/tmp/v.out 2>&1; echo "$n: $(head -1 /tmp/v.out) (rc $?)"; }; { \
      v luarocks luarocks --version; v bibtex-tidy bibtex-tidy --version; } >> /versions.txt; tail -2 /versions.txt

# The twentieth: talosctl from its arm64 release.
RUN curl -fsSL -o /opt/bin/talosctl https://github.com/siderolabs/talos/releases/download/v1.14.2/talosctl-linux-arm64 \
      && chmod 755 /opt/bin/talosctl && echo "talosctl: $(talosctl version --client --short 2>&1 | head -2 | tr '\n' ' ')" >> /versions.txt && tail -1 /versions.txt

WORKDIR /w
