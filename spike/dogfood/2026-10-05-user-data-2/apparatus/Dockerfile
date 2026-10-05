# The box for the 2026-10-05 user-data-2 rounds: Sideeye v1.8.0 installed the way
# docs/ci-quickstart.md tells a project to install it, and the candidates beside it.
# Shape copied from 2026-10-03 user-data's Dockerfile.
#
# What the candidates share with 2026-10-03: state that git does not hold — a keystore, a wallet,
# a Steam Guard secret, wiki pages, notes, subtitles, a GeoTIFF, a validator list, a credentials
# file — and not formatters. A FAIL measured on a packaged build is void if upstream has moved
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

# Runtimes and Debian-packaged candidates, one line per package, OK or MISSING.
RUN for p in nodejs npm ruby ruby-dev php-cli php-xml php-mbstring golang-go libfaketime faketime \
             firewalld skopeo ntfs-3g; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt

ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Release binaries, each version pinned in its URL. One line per tool, OK or MISSING.
RUN set -u; mkdir -p /opt/bin /tmp/dl; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get https://gethstore.blob.core.windows.net/builds/geth-linux-arm64-1.17.7-3d858f85.tar.gz geth.tgz; \
    get https://downloads.getmonero.org/cli/monero-linux-armv8-v0.18.5.1.tar.bz2 monero.tbz; \
    get $gh/dyc3/steamguard-cli/releases/download/v0.18.4/steamguard-linux-aarch64 steamguard; \
    get $gh/sigp/lighthouse/releases/download/v8.2.3/lighthouse-v8.2.3-aarch64-unknown-linux-gnu.tar.gz lighthouse.tgz; \
    get $gh/git-ecosystem/git-credential-manager/releases/download/v2.9.1/gcm-linux-arm64-2.9.1.tar.gz gcm.tgz; \
    get $gh/oras-project/oras/releases/download/v1.3.4/oras_1.3.4_linux_arm64.tar.gz oras.tgz; \
    get $gh/regclient/regclient/releases/download/v0.11.6/regctl-linux-arm64 regctl; \
    get $gh/containerd/nerdctl/releases/download/v2.4.1/nerdctl-2.4.1-linux-arm64.tar.gz nerdctl.tgz; \
    get $gh/velero-io/velero/releases/download/v1.18.4/velero-v1.18.4-linux-arm64.tar.gz velero.tgz; \
    get $gh/openai/codex/releases/download/rust-v0.160.0/codex-aarch64-unknown-linux-musl.tar.gz codex.tgz; \
    get $gh/rossmacarthur/sheldon/releases/download/0.8.5/sheldon-0.8.5-aarch64-unknown-linux-musl.tar.gz sheldon.tgz; \
    get $gh/micro-editor/micro/releases/download/v2.0.15/micro-2.0.15-linux-arm64.tar.gz micro.tgz; \
    get $gh/dokuwiki/dokuwiki/archive/refs/tags/release-2026-07-14c.tar.gz dokuwiki.tgz; \
    ls -l /tmp/dl
RUN set -u; cd /tmp/dl; \
    for t in geth lighthouse gcm oras nerdctl velero codex sheldon micro; do mkdir -p x-$t && tar xzf $t.tgz -C x-$t && echo "untar $t: ok" || echo "untar $t: FAILED"; done; \
    mkdir -p x-monero && tar xjf monero.tbz -C x-monero && echo "untar monero: ok"; \
    install -m 755 steamguard /opt/bin/steamguard; install -m 755 regctl /opt/bin/regctl; \
    for n in geth lighthouse git-credential-manager oras nerdctl velero sheldon micro monero-wallet-cli; do \
      f=$(find /tmp/dl/x-* -type f -name "$n" | head -1); \
      [ -n "$f" ] && install -m 755 "$f" /opt/bin/$n && echo "bin $n <- $f" || echo "bin $n: NOT FOUND"; \
    done; \
    f=$(find /tmp/dl/x-codex -type f -name 'codex*' | head -1); install -m 755 "$f" /opt/bin/codex && echo "bin codex <- $f"; \
    d=$(dirname "$(find /tmp/dl/x-gcm -type f -name git-credential-manager | head -1)"); cp -a "$d" /opt/gcm && ln -sf /opt/gcm/git-credential-manager /opt/bin/git-credential-manager; \
    mkdir -p /opt/dokuwiki && tar xzf dokuwiki.tgz -C /opt/dokuwiki --strip-components=1 && echo "dokuwiki: ok"; \
    ls -l /opt/bin

ENV PATH=/opt/bin:/opt/py/bin:/usr/local/bin:/root/go/bin:$PATH

# Python candidates, versions pinned (PyPI's latest on 2026-10-05), one venv. Each its own pip call so one failure is one line.
RUN python3 -m venv /opt/py; for p in basic-memory==0.23.2 ffsubsync==0.5.1 rasterio==1.5.2 kaggle==2.2.4 \
      huggingface_hub==2.1.1 yt-dlp==2026.8.19; do \
      /opt/py/bin/pip install --no-cache-dir "$p" > /tmp/pip-$p.log 2>&1 && echo "OK $p" || { echo "FAILED $p"; tail -3 /tmp/pip-$p.log; }; \
    done
RUN for p in vercel@62.2.0 wrangler@4.147.0 @google/gemini-cli@0.62.0 serverless@4.43.0; do \
      npm install -g --no-fund --no-audit "$p" > /tmp/npm-$p.log 2>&1 && echo "OK $p" || { echo "FAILED $p"; tail -3 /tmp/npm-$p.log; }; \
    done
RUN gem install --no-document i18n-tasks -v 1.1.2 > /tmp/gem-i18n.log 2>&1; echo "gem i18n-tasks exit: $?"; tail -1 /tmp/gem-i18n.log
RUN GOFLAGS=-mod=mod go install github.com/gsamokovarov/jump@v0.69.0 > /tmp/go-jump.log 2>&1; echo "go jump exit: $?"; tail -2 /tmp/go-jump.log; ls -l /root/go/bin

COPY install-sideeye.sh /opt/install-sideeye.sh
RUN sh /opt/install-sideeye.sh v1.8.0 /opt/se > /install.path 2>/install.log; \
    echo "installer exit: $?"; \
    echo "stdout: [$(cat /install.path)]"; \
    grep -E 'digest|sideeye ' /install.log || true
RUN "$(cat /install.path)" version

WORKDIR /w

# Added after the sixth name screen, whose rule-11 receipts are transcripts/receipts/rule11-bug-reports-2.txt:
# oh-my-posh, opam, stack and juliaup from their arm64 releases; goi18n by `go install` at its tag (its
# release has no arm64 asset); toybox, gltfpack and solvespace built from their latest tags (toybox has
# no release assets, meshoptimizer none for gltfpack on arm64, solvespace none for Linux; Debian trixie's
# solvespace is 3.1 against upstream 3.2); glTF-Transform from npm and wandb from PyPI, pinned.
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/JanDeDobbeleer/oh-my-posh/releases/download/v31.4.1/posh-linux-arm64 posh; \
    get $gh/ocaml/opam/releases/download/2.6.0/opam-2.6.0-arm64-linux opam; \
    get $gh/commercialhaskell/stack/releases/download/v3.11.1/stack-3.11.1-linux-aarch64-bin stack; \
    get $gh/JuliaLang/juliaup/releases/download/v1.22.7/juliaup-1.22.7-aarch64-unknown-linux-musl-portable.tar.gz juliaup.tgz; \
    install -m 755 posh /opt/bin/oh-my-posh; install -m 755 opam /opt/bin/opam; install -m 755 stack /opt/bin/stack; \
    mkdir -p x-juliaup && tar xzf juliaup.tgz -C x-juliaup; \
    for n in juliaup julialauncher; do f=$(find x-juliaup -type f -name $n | head -1); [ -n "$f" ] && install -m 755 "$f" /opt/bin/$n && echo "bin $n" || echo "bin $n: NOT FOUND"; done
RUN GOFLAGS=-mod=mod go install github.com/nicksnyder/go-i18n/v2/goi18n@v2.6.1 > /tmp/go-goi18n.log 2>&1; echo "go goi18n exit: $?"; tail -2 /tmp/go-goi18n.log
RUN for p in cmake libpng-dev zlib1g-dev libfreetype-dev libcairo2-dev libjson-c-dev libfontconfig-dev; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; done
RUN set -u; mkdir -p /tmp/src; cd /tmp/src; gh=https://github.com; \
    b() { name=$1; shift; ( set -e; "$@" ) > /tmp/build-$name.log 2>&1 && echo "BUILT $name" || { echo "FAILED $name"; tail -8 /tmp/build-$name.log; }; }; \
    b toybox sh -c "curl -fsSL $gh/landley/toybox/archive/refs/tags/0.8.14.tar.gz | tar xz && cd toybox-0.8.14 && make defconfig && make -j4 toybox && install -m 755 toybox /opt/bin/toybox"; \
    b gltfpack sh -c "git clone -q --depth 1 -b v1.3 $gh/zeux/meshoptimizer && cd meshoptimizer && cmake -S . -B out -DCMAKE_BUILD_TYPE=Release -DMESHOPT_BUILD_GLTFPACK=ON && cmake --build out -j4 --target gltfpack && install -m 755 out/gltfpack /opt/bin/gltfpack"; \
    b solvespace sh -c "git clone -q --depth 1 -b v3.2 --recurse-submodules --shallow-submodules $gh/solvespace/solvespace && cd solvespace && cmake -S . -B out -DCMAKE_BUILD_TYPE=Release -DENABLE_GUI=OFF -DENABLE_TESTS=OFF -DENABLE_OPENMP=OFF && cmake --build out -j4 --target solvespace-cli && install -m 755 out/bin/solvespace-cli /opt/bin/solvespace-cli"; \
    true
RUN npm install -g --no-fund --no-audit @gltf-transform/cli@4.5.1 > /tmp/npm-gltf.log 2>&1; echo "npm gltf-transform exit: $?"; tail -2 /tmp/npm-gltf.log
RUN /opt/py/bin/pip install --no-cache-dir wandb==0.30.0 > /tmp/pip-wandb.log 2>&1; echo "pip wandb exit: $?"; tail -2 /tmp/pip-wandb.log
# Node 22: wrangler 4.147.0 refuses Debian trixie's Node 20.19.2 ("requires at least Node.js v22.0.0",
# transcripts/probe-help.txt). The official arm64 tarball goes first on PATH, so every npm tool runs on it.
RUN mkdir -p /opt/node22 && curl -fsSL https://nodejs.org/dist/v22.23.3/node-v22.23.3-linux-arm64.tar.xz | tar xJ -C /opt/node22 --strip-components=1 && /opt/node22/bin/node --version
ENV PATH=/opt/node22/bin:$PATH
# gemini-cli again: the first build's npm loop wrote each log to /tmp/npm-<package>.log, and the scoped
# name put a `/` into that path, so the redirect failed and npm never ran (transcripts/build-first.txt).
RUN npm install -g --no-fund --no-audit @google/gemini-cli@0.62.0 > /tmp/npm-gemini-cli.log 2>&1; echo "npm gemini-cli exit: $?"; tail -2 /tmp/npm-gemini-cli.log

# Added after the entry gate left 23 of 32 clear (transcripts/entry-candidates.txt) and a seventh name
# screen (transcripts/fresh-screen-7.txt, receipts/rule11-bug-reports-3.txt): stripe-cli and infracost
# from their arm64 releases; meltano, astropy and azure-cli from PyPI, pinned (azure-cli in a venv of its
# own, it is large); pymol from Debian, whose 3.1.0 is upstream's latest tag.
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/stripe/stripe-cli/releases/download/v1.53.0/stripe_1.53.0_linux_arm64.tar.gz stripe.tgz; \
    get $gh/infracost/infracost/releases/download/v0.10.46/infracost-linux-arm64.tar.gz infracost.tgz; \
    for t in stripe infracost; do mkdir -p y-$t && tar xzf $t.tgz -C y-$t; done; \
    f=$(find y-stripe -type f -name stripe | head -1); install -m 755 "$f" /opt/bin/stripe && echo "bin stripe"; \
    f=$(find y-infracost -type f -name 'infracost*' | head -1); install -m 755 "$f" /opt/bin/infracost && echo "bin infracost <- $f"
RUN for p in meltano==4.4.0 astropy==8.0.1; do /opt/py/bin/pip install --no-cache-dir "$p" > /tmp/pip-x.log 2>&1 && echo "OK $p" || { echo "FAILED $p"; tail -3 /tmp/pip-x.log; }; done
RUN python3 -m venv /opt/az && /opt/az/bin/pip install --no-cache-dir azure-cli==2.90.0 > /tmp/pip-az.log 2>&1; echo "pip azure-cli exit: $?"; ln -s /opt/az/bin/az /opt/bin/az
RUN apt-get install -y --no-install-recommends pymol > /tmp/apt-pymol.log 2>&1 && echo "OK pymol" || echo "MISSING pymol"

# Added after the eighth name screen (transcripts/fresh-screen-8.txt, receipts/rule11-bug-reports-4.txt):
# python-dotenv (with its CLI) and gita into the candidates' venv; homeassistant, which requires Python
# >= 3.14.2 where Debian trixie has 3.13, into a venv of its own on a standalone 3.14 fetched by uv.
RUN for p in "python-dotenv[cli]==1.2.4" gita==0.16.8.2; do /opt/py/bin/pip install --no-cache-dir "$p" > /tmp/pip-y.log 2>&1 && echo "OK $p" || { echo "FAILED $p"; tail -3 /tmp/pip-y.log; }; done
RUN /opt/py/bin/pip install --no-cache-dir uv > /tmp/pip-uv.log 2>&1 && UV_PYTHON_INSTALL_DIR=/opt/uvpy /opt/py/bin/uv venv -q -p 3.14 /opt/ha > /tmp/uv-venv.log 2>&1 \
      && VIRTUAL_ENV=/opt/ha /opt/py/bin/uv pip install -q homeassistant==2026.9.4 > /tmp/uv-ha.log 2>&1; echo "homeassistant exit: $?"; tail -3 /tmp/uv-ha.log; ln -s /opt/ha/bin/hass /opt/bin/hass; /opt/ha/bin/python --version

# Added after the ninth name screen (transcripts/fresh-screen-9.txt, receipts/rule11-bug-reports-5.txt):
# wp-cli from its release phar.
RUN curl -fsSL -o /opt/bin/wp https://github.com/wp-cli/wp-cli/releases/download/v2.12.0/wp-cli-2.12.0.phar && chmod 755 /opt/bin/wp && php /opt/bin/wp --info --allow-root | head -3

# Added after the rule-14 reading vetoed dokuwiki (SELECTION.md): dynaconf from PyPI (the eleventh name
# screen), and lingui's CLI, core and macro plugin from npm into a project directory of its own, pinned.
RUN /opt/py/bin/pip install --no-cache-dir dynaconf==3.3.5 > /tmp/pip-dyn.log 2>&1; echo "pip dynaconf exit: $?"
RUN mkdir -p /opt/lingui-proj && cd /opt/lingui-proj && printf '{"name":"seed","private":true,"type":"module"}\n' > package.json \
    && npm install --no-fund --no-audit @lingui/cli@6.9.0 @lingui/core@6.9.0 @lingui/babel-plugin-lingui-macro@6.9.0 > /tmp/npm-lingui.log 2>&1; \
    echo "npm lingui exit: $?"; tail -2 /tmp/npm-lingui.log; ls /opt/lingui-proj/node_modules/.bin | head

# Added after the rule-14 reading vetoed lighthouse (SELECTION.md): conan and platformio from PyPI, pinned
# (the twelfth name screen).
RUN for p in conan==2.33.0 platformio==6.2.0; do /opt/py/bin/pip install --no-cache-dir "$p" > /tmp/pip-z.log 2>&1 && echo "OK $p" || { echo "FAILED $p"; tail -3 /tmp/pip-z.log; }; done

# Added after the rule-14 reading vetoed jump (SELECTION.md): lima and tenv from their arm64 releases
# (the fourteenth name screen).
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/lima-vm/lima/releases/download/v2.2.1/lima-2.2.1-Linux-aarch64.tar.gz lima.tgz; \
    get $gh/tofuutils/tenv/releases/download/v4.15.1/tenv_v4.15.1_Linux_arm64.tar.gz tenv.tgz; \
    mkdir -p /opt/lima && tar xzf lima.tgz -C /opt/lima && ln -sf /opt/lima/bin/limactl /opt/bin/limactl && echo "bin limactl"; \
    mkdir -p y-tenv && tar xzf tenv.tgz -C y-tenv && f=$(find y-tenv -type f -name tenv | head -1) && install -m 755 "$f" /opt/bin/tenv && echo "bin tenv"

# A spare after the vetoes (the fifteenth name screen): xmake built from its v3.1.1 source tarball (its
# release has no linux/arm64 bundle).
RUN cd /tmp/src && curl -fsSL https://github.com/xmake-io/xmake/releases/download/v3.1.1/xmake-v3.1.1.tar.gz | tar xz \
    && cd xmake-3.1.1 && ./configure > /tmp/build-xmake.log 2>&1 && make -j4 >> /tmp/build-xmake.log 2>&1 && make install PREFIX=/usr/local >> /tmp/build-xmake.log 2>&1; \
    echo "xmake build exit: $?"; tail -2 /tmp/build-xmake.log; XMAKE_ROOT=y xmake --version 2>&1 | head -1

# Spares after the vetoes (the sixteenth name screen): crictl from its arm64 release, kubeadm from dl.k8s.io
# at the stable release.
RUN set -u; cd /tmp/dl; \
    curl -fsSL -o crictl.tgz https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.37.0/crictl-v1.37.0-linux-arm64.tar.gz && tar xzf crictl.tgz -C /opt/bin && echo "bin crictl"; \
    curl -fsSL -o /opt/bin/kubeadm https://dl.k8s.io/release/v1.37.1/bin/linux/arm64/kubeadm && chmod 755 /opt/bin/kubeadm && echo "bin kubeadm"

# Spares after more vetoes (the seventeenth name screen): k8sgpt from its arm64 release, ggshield from PyPI;
# uv is the one already in /opt/py (installed above for homeassistant's venv).
RUN set -u; cd /tmp/dl; curl -fsSL -o k8sgpt.tgz https://github.com/k8sgpt-ai/k8sgpt/releases/download/v0.4.39/k8sgpt_Linux_arm64.tar.gz \
    && mkdir -p y-k8sgpt && tar xzf k8sgpt.tgz -C y-k8sgpt && install -m 755 y-k8sgpt/k8sgpt /opt/bin/k8sgpt && echo "bin k8sgpt"; \
    /opt/py/bin/pip install --no-cache-dir ggshield==1.55.0 > /tmp/pip-gg.log 2>&1; echo "pip ggshield exit: $?"; /opt/py/bin/uv --version

# A spare after the opam and juliaup vetoes (the nineteenth name screen): juju's client from its arm64 release.
RUN set -u; cd /tmp/dl; curl -fsSL -o juju.txz https://github.com/juju/juju/releases/download/v3.6.29/juju-3.6.29-linux-arm64.tar.xz \
    && mkdir -p y-juju && tar xJf juju.txz -C y-juju && f=$(find y-juju -type f -name juju | head -1) && install -m 755 "$f" /opt/bin/juju && echo "bin juju <- $f"

# A spare after the stripe veto (the twentieth name screen): aliyun-cli from its arm64 release.
RUN set -u; cd /tmp/dl; curl -fsSL -o aliyun.tgz https://github.com/aliyun/aliyun-cli/releases/download/v3.5.1/aliyun-cli-linux-3.5.1-arm64.tgz \
    && mkdir -p y-aliyun && tar xzf aliyun.tgz -C y-aliyun && install -m 755 y-aliyun/aliyun /opt/bin/aliyun && echo "bin aliyun"

# A spare (its rule-11 receipt is in transcripts/receipts/rule11-bug-reports.txt): firebase-tools from npm, pinned.
RUN npm install -g --no-fund --no-audit firebase-tools@15.32.1 > /tmp/npm-firebase.log 2>&1; echo "npm firebase-tools exit: $?"; tail -1 /tmp/npm-firebase.log

# A spare (the twenty-first name screen): turbo from npm, pinned (its native binary comes as an optional dependency).
RUN npm install -g --no-fund --no-audit turbo@2.11.7 > /tmp/npm-turbo.log 2>&1; echo "npm turbo exit: $?"; turbo --version

# The spare after uv left the slate as seen (the twenty-third name screen): the go command itself at
# upstream's latest release, beside trixie's go 1.24.4 that built goi18n and jump. Digest from go.dev's
# own listing (?mode=json).
RUN set -u; cd /tmp/dl; curl -fsSL -o go.tgz https://go.dev/dl/go1.27.1.linux-arm64.tar.gz \
    && echo "3450b45a3f9ee8568792736a5c5e70a1f2e9b36c35a8f74958c03e51d7d92bec  go.tgz" | sha256sum -c - && mkdir -p /opt/go127 && tar xzf go.tgz -C /opt/go127 \
    && /opt/go127/go/bin/go version
