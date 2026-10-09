# The box for the third round of 2026-10-09 follow-ups: the released Sideeye v1.10.0 beside the targets
# the second recount left measurable (SELECTION.md). The base is 2026-10-09 follow-ups 2's, copied.
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

# ---- Node targets, for UV_THREADPOOL_SIZE=1 (the threads wall) ----
RUN npm install -g --no-fund --no-audit @yarnpkg/cli-dist@4.18.1 trash-cli@7.2.0 > /tmp/npm-1.log 2>&1 && echo "OK yarn trash-cli" || { echo FAILED; tail -3 /tmp/npm-1.log; }
RUN { echo "node $(node --version)"; echo "yarn $(yarn --version)"; echo "trash $(npm ls -g trash-cli 2>/dev/null | grep trash-cli)"; } | tee /versions.txt

# ---- the rest of the threads wall's Node targets, at the versions their campaigns measured ----
RUN apt-get install -y --no-install-recommends php-cli php-xml php-mbstring golang-go > /tmp/apt-2.log 2>&1 && echo "OK php golang" || { echo MISSING; tail -3 /tmp/apt-2.log; }
RUN for p in bibtex-tidy@1.15.1 @dotenvx/dotenvx@2.32.4 @google/gemini-cli@0.62.0 @gltf-transform/cli@4.5.1 vercel@62.2.0 \
      eslint@10.11.0 prettier@3.9.7 stylelint@17.15.0 svgo@4.1.0 joplin@3.7.1 @bitwarden/cli@2026.8.0; do \
      npm install -g --no-fund --no-audit "$p" > /tmp/npm-$(echo $p | tr /@ __).log 2>&1 && echo "OK $p" || { echo "FAILED $p"; tail -2 /tmp/npm-$(echo $p | tr /@ __).log; }; \
    done
RUN mkdir -p /opt/lingui-proj && cd /opt/lingui-proj && printf '{"name":"seed","private":true,"type":"module"}\n' > package.json \
    && npm install --no-fund --no-audit @lingui/cli@6.9.0 @lingui/core@6.9.0 @lingui/babel-plugin-lingui-macro@6.9.0 > /tmp/npm-lingui.log 2>&1; echo "npm lingui exit: $?"
RUN set -u; cd /tmp/dl; curl -fsSL -o node22.txz https://nodejs.org/dist/v22.23.3/node-v22.23.3-linux-arm64.tar.xz && \
    echo "a44aeb94849a299b22df10b9e622ec2f605c2183501bc40590705131de7c740f  node22.txz" | sha256sum -c && \
    mkdir -p /opt/node22 && tar xJf node22.txz -C /opt/node22 --strip-components=1 && /opt/node22/bin/node --version
RUN for p in cspell@10.3.6 @capacitor/cli@8.5.2; do \
      PATH=/opt/node22/bin:$PATH /opt/node22/bin/npm install -g --no-fund --no-audit "$p" > /tmp/npm22-$(echo $p | tr /@ __).log 2>&1 && echo "OK node22 $p" || { echo "FAILED $p"; tail -3 /tmp/npm22-$(echo $p | tr /@ __).log; }; \
    done
# ---- Go targets for GOMAXPROCS=1, and the five that cleared a gate and were never explored ----
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/opentofu/opentofu/releases/download/v1.13.1/tofu_1.13.1_linux_arm64.tar.gz tofu.tgz; \
    get $gh/digitalocean/doctl/releases/download/v1.177.0/doctl-1.177.0-linux-arm64.tar.gz doctl.tgz; \
    get $gh/infracost/infracost/releases/download/v0.10.46/infracost-linux-arm64.tar.gz infracost.tgz; \
    get $gh/PlakarKorp/plakar/releases/download/v1.1.7/plakar_1.1.7_linux_arm64.tar.gz plakar.tgz; \
    get $gh/sigp/lighthouse/releases/download/v8.2.3/lighthouse-v8.2.3-aarch64-unknown-linux-gnu.tar.gz lighthouse.tgz; \
    get $gh/git-lfs/git-lfs/releases/download/v3.8.0/git-lfs-linux-arm64-v3.8.0.tar.gz git-lfs.tgz; \
    get $gh/dokuwiki/dokuwiki/archive/refs/tags/release-2026-07-14c.tar.gz dokuwiki.tgz; \
    for t in tofu doctl infracost plakar lighthouse git-lfs; do mkdir -p x-$t && tar xzf $t.tgz -C x-$t; done; \
    for n in tofu doctl infracost plakar lighthouse git-lfs; do f=$(find x-$n -type f -name "$n" | head -1); [ -n "$f" ] && install -m 755 "$f" /opt/bin/$n && echo "bin $n" || echo "NO BINARY $n"; done; \
    mkdir -p /opt/dokuwiki && tar xzf dokuwiki.tgz -C /opt/dokuwiki --strip-components=1 && echo "dokuwiki: ok"
RUN GOFLAGS=-mod=mod go install github.com/gsamokovarov/jump@v0.69.0 > /tmp/go-jump.log 2>&1; echo "go jump exit: $?"; install -m 755 /root/go/bin/jump /opt/bin/jump
RUN for p in keyring==25.7.0 keyrings.alt==5.0.2; do /opt/py/bin/pip install --no-cache-dir "$p" > /tmp/pip-k.log 2>&1 && echo "OK $p" || echo "FAILED $p"; done
RUN { for c in "bibtex-tidy --version" "dotenvx --version" "gemini --version" "gltf-transform --version" "vercel --version" "eslint --version" "prettier --version" "stylelint --version" "svgo --version" "joplin version" "bw --version" "npm --version" "tofu version" "doctl version" "infracost --version" "plakar version" "lighthouse --version" "git-lfs version" "jump --version" "/opt/py/bin/keyring --version"; do printf '%s: ' "$c"; sh -c "$c" < /dev/null 2>&1 | head -1; done; for c in "cspell --version" "cap --version"; do printf '%s (node22): ' "$c"; PATH=/opt/node22/bin:$PATH sh -c "$c" < /dev/null 2>&1 | head -1; done; } | tee -a /versions.txt

RUN install -m 755 "$(find /tmp/dl/x-infracost -type f -name 'infracost*' | head -1)" /opt/bin/infracost && infracost --version | tee -a /versions.txt

# ---- the threads wall's last tools, each with its own switch for one thread ----
RUN apt-get install -y --no-install-recommends zstd lz4 beets lame > /tmp/apt-3.log 2>&1 && echo "OK zstd lz4 beets lame" || { echo MISSING; tail -3 /tmp/apt-3.log; }
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/rustic-rs/rustic/releases/download/v0.11.4/rustic-v0.11.4-aarch64-unknown-linux-gnu.tar.gz rustic.tgz; \
    get $gh/j178/prek/releases/download/v0.5.5/prek-aarch64-unknown-linux-gnu.tar.gz prek.tgz; \
    get $gh/openai/codex/releases/download/rust-v0.160.0/codex-aarch64-unknown-linux-musl.tar.gz codex.tgz; \
    get $gh/dyc3/steamguard-cli/releases/download/v0.18.4/steamguard-linux-aarch64 steamguard; \
    for t in rustic prek codex; do mkdir -p y-$t && tar xzf $t.tgz -C y-$t; done; \
    install -m 755 "$(find y-rustic -type f -name rustic | head -1)" /opt/bin/rustic; \
    install -m 755 "$(find y-prek -type f -name prek | head -1)" /opt/bin/prek; \
    install -m 755 "$(find y-codex -type f -name 'codex*' | head -1)" /opt/bin/codex; \
    install -m 755 steamguard /opt/bin/steamguard; \
    { for c in "zstd --version" "lz4 --version" "beet version" "rustic --version" "prek --version" "codex --version" "steamguard --version"; do printf '%s: ' "$c"; sh -c "$c" < /dev/null 2>&1 | head -1; done; } | tee -a /versions.txt

# ---- the last walls' switches: ccache's stats off, astropy's memmap off, and a FAT filesystem (no
# O_TMPFILE, no ACL) for vim, Kvantum, Hydrogen, flatpak and ostree ----
RUN apt-get install -y --no-install-recommends ccache gcc libc6-dev vim-nox qt6-style-kvantum hydrogen flatpak ostree dosfstools \
      > /tmp/apt-4.log 2>&1 && echo "OK ccache vim kvantum hydrogen flatpak ostree dosfstools" || { echo MISSING; tail -3 /tmp/apt-4.log; }
RUN /opt/py/bin/pip install --no-cache-dir astropy==8.0.1 > /tmp/pip-astropy.log 2>&1; echo "pip astropy exit: $?"; ln -sf /opt/py/bin/fitscheck /opt/bin/fitscheck
RUN { for c in "ccache --version" "vim --version" "fitscheck --version" "flatpak --version" "ostree --version" "mkfs.vfat --help"; do printf '%s: ' "$c"; sh -c "$c" < /dev/null 2>&1 | head -1; done; } | tee -a /versions.txt

# ---- ROOT 6.40.04 from conda-forge through micromamba 2.9.0, as 2026-10-09 user-data-4 installed it ----
RUN set -u; cd /tmp/dl; curl -fsSL -o micromamba https://github.com/mamba-org/micromamba-releases/releases/download/2.9.0-0/micromamba-linux-aarch64 && install -m 755 micromamba /opt/bin/micromamba && \
    MAMBA_ROOT_PREFIX=/opt/mamba micromamba create -y -p /opt/root -c conda-forge root=6.40.04 > /tmp/mamba-root.log 2>&1 && echo "OK root" || { echo "FAILED root"; tail -5 /tmp/mamba-root.log; }
RUN echo "root $(/opt/root/bin/root-config --version 2>&1)" | tee -a /versions.txt
