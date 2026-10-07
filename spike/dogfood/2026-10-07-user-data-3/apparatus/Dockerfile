# The box for the 2026-10-07 user-data-3 rounds: Sideeye v1.9.0 installed the way
# docs/ci-quickstart.md tells a project to install it, and the candidates beside it.
# Shape copied from 2026-10-05 user-data-2's Dockerfile; its tool layers are not carried over —
# this run's candidates are added below the base as they clear the screen.
#
# What the candidates share with 2026-10-05: state that git does not hold, and not formatters.
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
RUN sh /opt/install-sideeye.sh v1.9.0 /opt/se > /install.path 2>/install.log; \
    echo "installer exit: $?"; \
    echo "stdout: [$(cat /install.path)]"; \
    grep -E 'digest|sideeye ' /install.log || true
RUN "$(cat /install.path)" version

WORKDIR /w

# ---- candidate layers, added as the screen clears them ----

# First layer, after the first screen (transcripts/fresh-screen-1.txt, word-recheck-1.txt,
# stars-1.txt). Each from its own latest release for linux/arm64; versions as GitHub and the
# registries answered on 2026-10-07. openssl 4.0.3 has no binary asset and Debian trixie ships
# 3.5, so it is built from the release tarball; minisign and zsh are Debian's, each checked against
# upstream's latest in SELECTION.md.
RUN for p in minisign zsh; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/openssl/openssl/releases/download/openssl-4.0.3/openssl-4.0.3.tar.gz openssl.tgz; \
    get $gh/smallstep/cli/releases/download/v0.31.0/step_linux_0.31.0_arm64.tar.gz step.tgz; \
    get $gh/lxc/incus/releases/download/v7.5.1/bin.linux.incus.aarch64 incus; \
    get $gh/canonical/lxd/releases/download/lxd-6.9/bin.linux.lxc.aarch64 lxc; \
    get $gh/git-lfs/git-lfs/releases/download/v3.8.0/git-lfs-linux-arm64-v3.8.0.tar.gz git-lfs.tgz; \
    get $gh/gilbertchen/duplicacy/releases/download/v3.2.5/duplicacy_linux_arm64_3.2.5 duplicacy; \
    get $gh/PlakarKorp/plakar/releases/download/v1.1.7/plakar_1.1.7_linux_arm64.tar.gz plakar.tgz; \
    get $gh/rustic-rs/rustic/releases/download/v0.11.4/rustic-v0.11.4-aarch64-unknown-linux-gnu.tar.gz rustic.tgz; \
    get $gh/gorilla-devs/ferium/releases/download/v4.7.1/ferium-linux-arm64-nogui.zip ferium.zip; \
    get $gh/OpenVPN/easy-rsa/releases/download/v3.2.7/EasyRSA-3.2.7.tgz easyrsa.tgz; \
    get $gh/acmesh-official/acme.sh/archive/refs/tags/3.1.6.tar.gz acme.tgz; \
    get $gh/agkozak/zsh-z/archive/refs/tags/v2.0.1.tar.gz zshz.tgz; \
    ls -l /tmp/dl
RUN set -u; cd /tmp/dl; mkdir -p x-openssl && tar xzf openssl.tgz -C x-openssl --strip-components=1 && cd x-openssl && \
    ./Configure --prefix=/opt/openssl --openssldir=/opt/openssl/ssl --libdir=lib '-Wl,-rpath,/opt/openssl/lib' > /tmp/openssl-configure.log 2>&1 && \
    make -j"$(nproc)" > /tmp/openssl-make.log 2>&1 && make install_sw install_ssldirs > /tmp/openssl-install.log 2>&1 && \
    ln -sf /opt/openssl/bin/openssl /opt/bin/openssl && echo "openssl: $(/opt/bin/openssl version)" || { echo "openssl: FAILED"; tail -5 /tmp/openssl-make.log; }
RUN set -u; cd /tmp/dl; \
    for t in step git-lfs plakar rustic easyrsa acme zshz; do mkdir -p x-$t && tar xzf $t.tgz -C x-$t && echo "untar $t: ok" || echo "untar $t: FAILED"; done; \
    mkdir -p x-ferium && unzip -q ferium.zip -d x-ferium && echo "unzip ferium: ok"; \
    install -m 755 incus /opt/bin/incus; install -m 755 lxc /opt/bin/lxc; install -m 755 duplicacy /opt/bin/duplicacy; \
    for n in step git-lfs plakar rustic ferium; do \
      f=$(find /tmp/dl/x-* -type f -name "$n" | head -1); \
      [ -n "$f" ] && install -m 755 "$f" /opt/bin/$n && echo "bin $n <- $f" || echo "bin $n: NOT FOUND"; \
    done; \
    d=$(dirname "$(find /tmp/dl/x-easyrsa -type f -name easyrsa | head -1)"); cp -a "$d" /opt/easyrsa && ln -sf /opt/easyrsa/easyrsa /opt/bin/easyrsa && echo "easyrsa <- $d"; \
    d=$(find /tmp/dl/x-acme -maxdepth 1 -mindepth 1 -type d | head -1); cp -a "$d" /opt/acme.sh-src && echo "acme.sh src <- $d"; \
    d=$(find /tmp/dl/x-zshz -maxdepth 1 -mindepth 1 -type d | head -1); cp -a "$d" /opt/zsh-z && echo "zsh-z <- $d"; \
    ls -l /opt/bin
RUN for p in certstrap@v1.3.0 sbctl@0.18; do \
      case "$p" in certstrap*) m=github.com/square/certstrap@v1.3.0 ;; sbctl*) m=github.com/foxboron/sbctl/cmd/sbctl@0.18 ;; esac; \
      GOFLAGS=-mod=mod go install "$m" > /tmp/go-$p.log 2>&1 && echo "OK go $p" || { echo "FAILED go $p"; tail -3 /tmp/go-$p.log; }; \
    done; ls -l /root/go/bin
RUN for p in afdko==5.0.1 legendary-gl==0.21.1 weewx==5.5.2 snakemake==9.27.0 esptool==5.4.0; do \
      /opt/py/bin/pip install --no-cache-dir "$p" > /tmp/pip-$p.log 2>&1 && echo "OK $p" || { echo "FAILED $p"; tail -3 /tmp/pip-$p.log; }; \
    done
RUN npm install -g --no-fund --no-audit netlify-cli@27.11.2 > /tmp/npm-netlify.log 2>&1 && echo "OK netlify-cli" || { echo "FAILED netlify-cli"; tail -3 /tmp/npm-netlify.log; }
RUN { for c in "openssl version" "minisign -v" "zsh --version" "step version" "incus version" "lxc version" "git-lfs version" \
        "duplicacy -h" "plakar version" "rustic --version" "ferium --version" "easyrsa --version" "certstrap --version" "sbctl --version" \
        "sfntedit -h" "legendary --version" "weectl --version" "snakemake --version" "esptool version" "netlify --version"; do \
        printf '%s: ' "$c"; sh -c "$c" 2>&1 | head -1; done; } > /versions.txt 2>&1; cat /versions.txt

# Second layer: keyring (jaraco) with keyrings.alt, so a define can name the plaintext file backend
# (its default store is the Secret Service over DBus, which the box has none of). PyPI's latest on
# 2026-10-07.
RUN for p in keyring==25.7.0 keyrings.alt==5.0.2; do \
      /opt/py/bin/pip install --no-cache-dir "$p" > /tmp/pip-$p.log 2>&1 && echo "OK $p" || { echo "FAILED $p"; tail -3 /tmp/pip-$p.log; }; \
    done; printf 'keyring --version: ' >> /versions.txt; /opt/py/bin/keyring --version >> /versions.txt 2>&1; tail -1 /versions.txt

# Third layer, after the second screen (transcripts/scout-2.txt, word-recheck-2.txt, stars-4.txt,
# rule11-bug-reports-3.txt): each from its own latest release for linux/arm64 where one exists, npm
# at the registry's latest on 2026-10-07; libzip (ziptool) built from its release tarball (no binary
# asset; trixie ships 1.11.3); oh-my-fish v8 installed offline from its tag, on fish 4.9.3's own
# arm64 build.
RUN apt-get install -y --no-install-recommends cmake zlib1g-dev libbz2-dev liblzma-dev libzstd-dev > /tmp/apt-cmake.log 2>&1 && echo "OK cmake and zlib" || echo "MISSING cmake"
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/Canop/broot/releases/download/v1.61.0/broot_1.61.0.zip broot.zip; \
    get $gh/j178/prek/releases/download/v0.5.5/prek-aarch64-unknown-linux-gnu.tar.gz prek.tgz; \
    get $gh/savedra1/clipse/releases/download/v1.2.1/clipse_v1.2.1_linux_x11_arm64.tar.gz clipse.tgz; \
    get $gh/tstack/lnav/releases/download/v0.14.1/lnav-0.14.1-linux-musl-arm64.zip lnav.zip; \
    get $gh/nih-at/libzip/releases/download/v1.11.4/libzip-1.11.4.tar.gz libzip.tgz; \
    get $gh/fish-shell/fish-shell/releases/download/4.9.3/fish-4.9.3-linux-aarch64.tar.xz fish.txz; \
    get $gh/oh-my-fish/oh-my-fish/archive/refs/tags/v8.tar.gz omf.tgz; \
    ls -l /tmp/dl | tail -n 8
RUN set -u; cd /tmp/dl; \
    mkdir -p x-broot && unzip -q broot.zip -d x-broot && f=$(find x-broot -path '*aarch64-unknown-linux-gnu*' -type f -name broot | head -1) && install -m 755 "$f" /opt/bin/broot && echo "bin broot <- $f"; \
    mkdir -p x-prek && tar xzf prek.tgz -C x-prek && install -m 755 "$(find x-prek -type f -name prek | head -1)" /opt/bin/prek && echo "bin prek"; \
    mkdir -p x-clipse && tar xzf clipse.tgz -C x-clipse && install -m 755 "$(find x-clipse -type f -name 'clipse*' ! -name '*.tar.gz' | head -1)" /opt/bin/clipse && echo "bin clipse"; \
    mkdir -p x-lnav && unzip -q lnav.zip -d x-lnav && install -m 755 "$(find x-lnav -type f -name lnav | head -1)" /opt/bin/lnav && echo "bin lnav"; \
    mkdir -p x-fish && tar xJf fish.txz -C x-fish && install -m 755 "$(find x-fish -type f -name fish | head -1)" /opt/bin/fish && echo "bin fish"; \
    mkdir -p x-omf && tar xzf omf.tgz -C x-omf && d=$(find x-omf -maxdepth 1 -mindepth 1 -type d | head -1) && cp -a "$d" /opt/omf-src && echo "omf src <- $d"
RUN set -u; cd /tmp/dl; mkdir -p x-libzip && tar xzf libzip.tgz -C x-libzip --strip-components=1 && cd x-libzip && mkdir build && cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/opt/libzip -DCMAKE_INSTALL_RPATH=/opt/libzip/lib -DENABLE_GNUTLS=OFF -DENABLE_OPENSSL=OFF -DENABLE_MBEDTLS=OFF -DBUILD_REGRESS=OFF -DBUILD_DOC=OFF > /tmp/libzip-cmake.log 2>&1 && \
    make -j"$(nproc)" > /tmp/libzip-make.log 2>&1 && make install > /tmp/libzip-install.log 2>&1 && \
    cp src/ziptool /opt/bin/ziptool 2>/dev/null || find . -type f -name ziptool -perm -u+x -exec cp {} /opt/bin/ziptool \; ; \
    ls -l /opt/bin/ziptool && echo "ziptool built" || { echo "ziptool: FAILED"; tail -5 /tmp/libzip-make.log; }
RUN npm install -g --no-fund --no-audit tiddlywiki@5.4.1 > /tmp/npm-tiddlywiki.log 2>&1 && echo "OK tiddlywiki" || { echo "FAILED tiddlywiki"; tail -3 /tmp/npm-tiddlywiki.log; }
RUN { for c in "broot --version" "prek --version" "clipse -v" "lnav -V" "ziptool -h" "fish --version" "tiddlywiki --version"; do \
        printf '%s: ' "$c"; sh -c "$c" 2>&1 | head -1; done; } >> /versions.txt 2>&1; tail -7 /versions.txt

# Fourth layer, after the third screen (transcripts/scout-3.txt, word-recheck-3.txt, stars-5.txt,
# rule11-bug-reports-4.txt, rule11-relabel-3.txt). Each from its own latest release: arm64 assets for
# TIC-80 and krew; source tarballs at the latest tag for minizip-ng, LAStools, extract-xiso, Limine's
# host utility, xbps and libqalculate (their Linux assets are x86_64 or absent); PyPI's latest for ezdxf
# and mcpm. From Debian, each said to equal upstream's latest in SELECTION.md: testdisk 7.2 and
# sndfile-programs 1.2.2.
RUN for p in testdisk sndfile-programs libarchive-dev libssl-dev libmpfr-dev libgmp-dev libxml2-dev libicu-dev libreadline-dev intltool autoconf automake libtool; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/nesbox/TIC-80/releases/download/v1.3.1/tic80-v1.3-linux-arm64.zip tic80.zip; \
    get $gh/kubernetes-sigs/krew/releases/download/v0.5.0/krew-linux_arm64.tar.gz krew.tgz; \
    get $gh/zlib-ng/minizip-ng/archive/refs/tags/4.2.2.tar.gz minizip.tgz; \
    get $gh/LAStools/LAStools/archive/refs/tags/v2.0.5.tar.gz lastools.tgz; \
    get $gh/XboxDev/extract-xiso/archive/refs/tags/build-202609111233.tar.gz xiso.tgz; \
    get $gh/Limine-Bootloader/Limine/releases/download/v12.9.3/limine-12.9.3.tar.gz limine.tgz; \
    get $gh/void-linux/xbps/archive/refs/tags/0.60.7.tar.gz xbps.tgz; \
    get $gh/Qalculate/libqalculate/releases/download/v5.13.1/libqalculate-5.13.1.tar.gz qalc.tgz; \
    ls -l /tmp/dl | tail -n 8
RUN set -u; cd /tmp/dl; \
    mkdir -p x-tic && unzip -q tic80.zip -d x-tic && f=$(find x-tic -type f -name 'tic80*' ! -name '*.zip' | head -1) && install -m 755 "$f" /opt/bin/tic80 && echo "bin tic80 <- $f"; \
    mkdir -p x-krew && tar xzf krew.tgz -C x-krew && install -m 755 "$(find x-krew -type f -name 'krew-linux_arm64' | head -1)" /opt/bin/kubectl-krew && echo "bin kubectl-krew"
RUN set -u; cd /tmp/dl; mkdir -p x-mz && tar xzf minizip.tgz -C x-mz --strip-components=1 && cd x-mz && \
    cmake -S . -B build -DMZ_BUILD_TESTS=ON -DMZ_FETCH_LIBS=OFF -DMZ_OPENSSL=OFF -DMZ_LIBBSD=OFF -DMZ_ZSTD=OFF -DMZ_LZMA=OFF -DMZ_BZIP2=OFF -DMZ_ICONV=OFF -DMZ_BUILD_UNIT_TESTS=OFF -DCMAKE_BUILD_TYPE=Release > /tmp/mz-cmake.log 2>&1 && \
    cmake --build build -j"$(nproc)" > /tmp/mz-make.log 2>&1 && f=$(find build -type f -name 'minizip' -perm -u+x | head -1) && install -m 755 "$f" /opt/bin/minizip && echo "minizip built <- $f" || { echo "minizip: FAILED"; tail -n 5 /tmp/mz-cmake.log /tmp/mz-make.log || true; }
RUN set -u; cd /tmp/dl; mkdir -p x-las && tar xzf lastools.tgz -C x-las --strip-components=1 && cd x-las && \
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release > /tmp/las-cmake.log 2>&1 && cmake --build build -j"$(nproc)" --target lasinfo > /tmp/las-make.log 2>&1 && \
    f=$(find . -type f -name lasinfo -perm -u+x | head -1) && install -m 755 "$f" /opt/bin/lasinfo && echo "lasinfo built <- $f" || { echo "lasinfo: FAILED"; tail -n 5 /tmp/las-cmake.log /tmp/las-make.log || true; }
RUN set -u; cd /tmp/dl; mkdir -p x-xiso && tar xzf xiso.tgz -C x-xiso --strip-components=1 && cd x-xiso && \
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release > /tmp/xiso-cmake.log 2>&1 && cmake --build build -j"$(nproc)" > /tmp/xiso-make.log 2>&1 && \
    f=$(find build -type f -name extract-xiso -perm -u+x | head -1) && install -m 755 "$f" /opt/bin/extract-xiso && echo "extract-xiso built <- $f" || { echo "extract-xiso: FAILED"; tail -n 5 /tmp/xiso-make.log || true; }
RUN set -u; cd /tmp/dl; mkdir -p x-lim && tar xzf limine.tgz -C x-lim --strip-components=1 && cd x-lim && \
    { ./configure --disable-all > /tmp/lim-conf.log 2>&1 || true; } && { make -j"$(nproc)" > /tmp/lim-make.log 2>&1 || true; } && \
    f=$(find . -maxdepth 3 -type f -name limine -perm -u+x | head -1); \
    if [ -z "$f" ] && [ -f limine.c ]; then cc -O2 -std=c99 -o limine-host limine.c > /tmp/lim-cc.log 2>&1 && f=./limine-host; fi; \
    [ -n "$f" ] && install -m 755 "$f" /opt/bin/limine && echo "limine built <- $f" || { echo "limine: FAILED"; tail -n 5 /tmp/lim-conf.log /tmp/lim-make.log || true; }
RUN set -u; cd /tmp/dl; mkdir -p x-xbps && tar xzf xbps.tgz -C x-xbps --strip-components=1 && cd x-xbps && \
    ./configure --prefix=/opt/xbps > /tmp/xbps-conf.log 2>&1 && make -j"$(nproc)" > /tmp/xbps-make.log 2>&1 && make install > /tmp/xbps-install.log 2>&1 && \
    ln -sf /opt/xbps/bin/xbps-pkgdb /opt/bin/xbps-pkgdb && ln -sf /opt/xbps/bin/xbps-install /opt/bin/xbps-install && ln -sf /opt/xbps/bin/xbps-query /opt/bin/xbps-query && echo "xbps built" || { echo "xbps: FAILED"; tail -n 5 /tmp/xbps-conf.log /tmp/xbps-make.log || true; }
RUN set -u; cd /tmp/dl; mkdir -p x-qalc && tar xzf qalc.tgz -C x-qalc --strip-components=1 && cd x-qalc && \
    ./configure --prefix=/opt/qalc --without-libcurl --disable-nls > /tmp/qalc-conf.log 2>&1 && make -j"$(nproc)" > /tmp/qalc-make.log 2>&1 && make install > /tmp/qalc-install.log 2>&1 && \
    ln -sf /opt/qalc/bin/qalc /opt/bin/qalc && echo "qalc built" || { echo "qalc: FAILED"; tail -n 5 /tmp/qalc-conf.log /tmp/qalc-make.log || true; }
RUN for p in ezdxf==1.4.4 mcpm==2.15.0; do \
      /opt/py/bin/pip install --no-cache-dir "$p" > /tmp/pip-$p.log 2>&1 && echo "OK $p" || { echo "FAILED $p"; tail -3 /tmp/pip-$p.log; }; \
    done
RUN { for c in "testdisk /version" "sndfile-metadata-set --version" "tic80 --version" "kubectl-krew version" "minizip -h" "lasinfo -version" "extract-xiso -h" "limine --version" "xbps-pkgdb -V" "qalc --version" "ezdxf --version" "mcpm --version"; do \
        printf '%s: ' "$c"; sh -c "$c" < /dev/null 2>&1 | head -1; done; } >> /versions.txt 2>&1; tail -12 /versions.txt

# Fifth layer: three fixes to the fourth. LAStools builds lasinfo as bin64/lasinfo64; xbps's tools did not
# find libxbps.so.6 under /opt/xbps/lib; TIC-80's arm64 build wants libGL. Limine is out: the stage-1 code
# `bios-install` writes is built for the target with clang and nasm and embedded in the host utility.
RUN install -m 755 /tmp/dl/x-las/bin64/lasinfo64 /opt/bin/lasinfo && echo "bin lasinfo <- bin64/lasinfo64"; \
    echo /opt/xbps/lib > /etc/ld.so.conf.d/xbps.conf && ldconfig && echo "xbps libs registered"; \
    apt-get install -y --no-install-recommends libgl1 libegl1 > /tmp/apt-libgl.log 2>&1 && echo "OK libgl1" || echo "MISSING libgl1"
RUN { for c in "lasinfo -version" "xbps-pkgdb -V" "tic80 --version"; do printf '%s: ' "$c"; sh -c "$c" < /dev/null 2>&1 | head -1; done; } >> /versions.txt 2>&1; tail -3 /versions.txt

# Sixth layer, after the fourth screen (transcripts/scout-4.txt, word-recheck-4.txt, stars-6.txt,
# rule11-bug-reports-5.txt): pi, cspell and ruler from npm and doit from PyPI at the registries' latest on
# 2026-10-07; toolhive's thv and kitty's kitten from their arm64 release assets. And three earlier
# candidates given what they lacked: fdisk and e2fsprogs so testdisk has a partition to find, kitty's theme
# archive fetched here at build (`kitten themes` then runs offline on --cache-age=-1), and LAStools'
# txt2las so lasinfo is tried on a file LAStools itself wrote (lab 5's hand-built LAS 1.2 file was suspect).
RUN for p in fdisk e2fsprogs; do apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; done
RUN for p in @earendil-works/pi-coding-agent@1.0.4 cspell@10.3.6 @intellectronica/ruler@0.3.44; do \
      npm install -g --no-fund --no-audit "$p" > /tmp/npm-$(echo $p | tr /@ __).log 2>&1 && echo "OK $p" || { echo "FAILED $p"; tail -3 /tmp/npm-$(echo $p | tr /@ __).log; }; \
    done
RUN /opt/py/bin/pip install --no-cache-dir doit==0.37.0 > /tmp/pip-doit.log 2>&1 && echo "OK doit" || { echo "FAILED doit"; tail -3 /tmp/pip-doit.log; }
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/stacklok/toolhive/releases/download/v0.51.4/toolhive_0.51.4_linux_arm64.tar.gz thv.tgz; \
    get $gh/kovidgoyal/kitty/releases/download/v0.49.2/kitten-linux-arm64 kitten; \
    get https://codeload.github.com/kovidgoyal/kitty-themes/zip/refs/heads/master kitty-themes.zip; \
    mkdir -p x-thv && tar xzf thv.tgz -C x-thv && install -m 755 "$(find x-thv -type f -name thv | head -1)" /opt/bin/thv && echo "bin thv"; \
    install -m 755 kitten /opt/bin/kitten && echo "bin kitten"; \
    mkdir -p /opt/kitty-themes && cp kitty-themes.zip /opt/kitty-themes/kitty-themes.zip && ls -l /opt/kitty-themes
RUN set -u; cd /tmp/dl/x-las && cmake --build build -j"$(nproc)" --target txt2las > /tmp/las-txt2las.log 2>&1; \
    f=$(find . -type f -name 'txt2las*' -perm -u+x | head -1); [ -n "$f" ] && install -m 755 "$f" /opt/bin/txt2las && echo "bin txt2las <- $f" || { echo "txt2las: FAILED"; tail -n 5 /tmp/las-txt2las.log || true; }
RUN { for c in "pi --version" "cspell --version" "ruler --version" "doit --version" "thv version" "kitten --version" "txt2las -version" "sfdisk --version" "mkfs.ext2 -V"; do \
        printf '%s: ' "$c"; sh -c "$c" < /dev/null 2>&1 | head -1; done; } >> /versions.txt 2>&1; tail -9 /versions.txt

# Seventh layer: Node 22 from nodejs.org (digest checked against its SHASUMS256.txt), because pi and cspell
# refuse trixie's Node 20 (cspell: ">=22.18.0 is required"). Kept under /opt/node22 so the Node targets
# already explored keep the Node they ran on; pi's and cspell's defines put it first on PATH.
RUN set -u; cd /tmp/dl; curl -fsSL -o node22.txz https://nodejs.org/dist/v22.23.3/node-v22.23.3-linux-arm64.tar.xz && \
    echo "a44aeb94849a299b22df10b9e622ec2f605c2183501bc40590705131de7c740f  node22.txz" | sha256sum -c && \
    mkdir -p /opt/node22 && tar xJf node22.txz -C /opt/node22 --strip-components=1 && /opt/node22/bin/node --version
RUN for p in @earendil-works/pi-coding-agent@1.0.4 cspell@10.3.6; do \
      PATH=/opt/node22/bin:$PATH /opt/node22/bin/npm install -g --no-fund --no-audit "$p" > /tmp/npm22-$(echo $p | tr /@ __).log 2>&1 && echo "OK node22 $p" || { echo "FAILED $p"; tail -3 /tmp/npm22-$(echo $p | tr /@ __).log; }; \
    done
RUN { for c in "pi --version" "cspell --version"; do printf '%s (node22): ' "$c"; PATH=/opt/node22/bin:$PATH sh -c "$c" < /dev/null 2>&1 | head -1; done; } >> /versions.txt 2>&1; tail -2 /versions.txt

# Eighth layer, the last candidates (rule 11 in rule11-bug-reports-3.txt for alacritty and ostree, -6.txt for
# goaccess and gitmoji): alacritty built at its tag with trixie's Rust 1.85.1 (its rust-version is 1.85.0) and
# its own Cargo.lock; goaccess and libostree from their latest release sources (trixie ships goaccess 1.9.3
# against upstream 1.12, and ostree 2025.2 against 2026.4); gitmoji-cli from npm at the registry's latest.
RUN for p in cargo rustc libfreetype-dev libfontconfig-dev libxcb-xfixes0-dev libxkbcommon-dev libncurses-dev gettext autopoint \
             libglib2.0-dev libgpgme-dev libmount-dev libfuse3-dev e2fslibs-dev libcurl4-openssl-dev bison; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/alacritty/alacritty/archive/refs/tags/v0.17.0.tar.gz alacritty.tgz; \
    get $gh/allinurl/goaccess/archive/refs/tags/v1.12.tar.gz goaccess.tgz; \
    get $gh/ostreedev/ostree/releases/download/v2026.4/libostree-2026.4.tar.xz ostree.txz
RUN set -u; cd /tmp/dl; mkdir -p x-alac && tar xzf alacritty.tgz -C x-alac --strip-components=1 && cd x-alac && \
    CARGO_HTTP_CAINFO=/etc/ssl/certs/ca-certificates.crt cargo build --release --locked -p alacritty > /tmp/alac-build.log 2>&1 && \
    install -m 755 target/release/alacritty /opt/bin/alacritty && echo "alacritty built" || { echo "alacritty: FAILED"; tail -n 8 /tmp/alac-build.log || true; }
RUN set -u; cd /tmp/dl; mkdir -p x-goa && tar xzf goaccess.tgz -C x-goa --strip-components=1 && cd x-goa && \
    { autoreconf -fiv > /tmp/goa-autoreconf.log 2>&1; ./configure --prefix=/opt/goaccess > /tmp/goa-conf.log 2>&1; } && make -j"$(nproc)" > /tmp/goa-make.log 2>&1 && make install > /tmp/goa-install.log 2>&1 && \
    ln -sf /opt/goaccess/bin/goaccess /opt/bin/goaccess && echo "goaccess built" || { echo "goaccess: FAILED"; tail -n 8 /tmp/goa-conf.log /tmp/goa-make.log || true; }
RUN set -u; cd /tmp/dl; mkdir -p x-ost && tar xJf ostree.txz -C x-ost --strip-components=1 && cd x-ost && \
    ./configure --prefix=/opt/ostree --without-soup --without-libarchive --without-selinux --without-libsystemd --without-avahi --disable-man --disable-gtk-doc --without-composefs > /tmp/ost-conf.log 2>&1 && \
    make -j"$(nproc)" > /tmp/ost-make.log 2>&1 && make install > /tmp/ost-install.log 2>&1 && \
    echo /opt/ostree/lib > /etc/ld.so.conf.d/ostree.conf && ldconfig && ln -sf /opt/ostree/bin/ostree /opt/bin/ostree && echo "ostree built" || { echo "ostree: FAILED"; tail -n 8 /tmp/ost-conf.log /tmp/ost-make.log || true; }
RUN npm install -g --no-fund --no-audit gitmoji-cli@9.7.0 > /tmp/npm-gitmoji.log 2>&1 && echo "OK gitmoji-cli" || { echo "FAILED gitmoji-cli"; tail -3 /tmp/npm-gitmoji.log; }
RUN { for c in "alacritty --version" "goaccess --version" "ostree --version" "gitmoji --version"; do printf '%s: ' "$c"; sh -c "$c" < /dev/null 2>&1 | head -1; done; } >> /versions.txt 2>&1; tail -4 /versions.txt

# Ninth layer: capacitor's and astro's CLIs from npm at the registry's latest on 2026-10-07 (rule 11 in
# rule11-bug-reports-7.txt). Their settings files are read as rule-5 state the way 2026-10-05 read turbo's,
# wrangler's and vercel's telemetry settings.
RUN for p in @capacitor/cli@8.5.2 astro@7.3.6; do \
      npm install -g --no-fund --no-audit "$p" > /tmp/npm-$(echo $p | tr /@ __).log 2>&1 && echo "OK $p" || { echo "FAILED $p"; tail -3 /tmp/npm-$(echo $p | tr /@ __).log; }; \
    done
RUN { for c in "cap --version" "astro --version"; do printf '%s: ' "$c"; ASTRO_TELEMETRY_DISABLED=1 sh -c "$c" < /dev/null 2>&1 | head -1; done; } >> /versions.txt 2>&1; tail -2 /versions.txt

# Tenth layer: capacitor and astro refuse Node 20 too ("requires NodeJS >=22.0.0", "Node.js v20.19.2 is not
# supported"), so they go in under /opt/node22 like pi and cspell; their defines put it first on PATH.
RUN for p in @capacitor/cli@8.5.2 astro@7.3.6; do \
      PATH=/opt/node22/bin:$PATH /opt/node22/bin/npm install -g --no-fund --no-audit "$p" > /tmp/npm22-$(echo $p | tr /@ __).log 2>&1 && echo "OK node22 $p" || { echo "FAILED $p"; tail -3 /tmp/npm22-$(echo $p | tr /@ __).log; }; \
    done
RUN { for c in "cap --version" "astro --version"; do printf '%s (node22): ' "$c"; PATH=/opt/node22/bin:$PATH ASTRO_TELEMETRY_DISABLED=1 sh -c "$c" < /dev/null 2>&1 | head -1; done; } >> /versions.txt 2>&1; tail -2 /versions.txt

# Eleventh layer: roswell from its linux-arm64 release asset (the fifth screen's one clean candidate left;
# knife's `config use-profile` lives in chef/knife, 1 star — rule 1 on the code that writes).
RUN set -u; cd /tmp/dl; curl -fsSL -o ros.tbz https://github.com/roswell/roswell/releases/download/v26.02.116/roswell-26.02.116-linux-arm64.tar.bz2 && echo "OK ros.tbz" && \
    mkdir -p x-ros && tar xjf ros.tbz -C x-ros && f=$(find x-ros -type f -name ros -perm -u+x | head -1) && install -m 755 "$f" /opt/bin/ros && echo "bin ros <- $f"; \
    d=$(dirname "$(find x-ros -type f -name ros | head -1)"); ls "$d" | head; printf 'ros version: ' >> /versions.txt; /opt/bin/ros version >> /versions.txt 2>&1 || true; tail -3 /versions.txt

# Twelfth layer: roswell installed by its own Makefile (its lisp files go to /usr/local/etc/roswell) and set
# up at build, network on, so `ros config` finds an SBCL offline. ROSWELL_HOME is pinned under /opt so the
# define's HOME starts empty of everything but the config the seed writes.
RUN set -u; cd /tmp/dl/x-ros/roswell && make install > /tmp/ros-install.log 2>&1 && echo "ros installed" || { echo "ros install: FAILED"; tail -n 5 /tmp/ros-install.log || true; }
RUN ROSWELL_HOME=/opt/roswell-home ros setup > /tmp/ros-setup.log 2>&1 && echo "ros setup ok" || { echo "ros setup: FAILED"; tail -n 8 /tmp/ros-setup.log || true; }; \
    ls /opt/roswell-home 2>/dev/null | head
