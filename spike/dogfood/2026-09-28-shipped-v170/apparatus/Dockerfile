# The box for the 2026-09-28 shipped-v170 run: Sideeye v1.7.0 installed the way
# docs/ci-quickstart.md tells a project to install it, and the nineteen candidates beside it.
#
# Built by build.sh, which stages the proxy CA and the vendored installer. Two stages of
# network, and only these two: the image build (install, packages) — and nothing after it.
# Every gate, explore and replay runs with `docker run --network none`.
#
# linux/arm64 (this machine's Docker). Every release binary below is the aarch64-linux asset
# its project publishes; a candidate with no such asset was dropped at selection (dstask).
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 python3-venv ca-certificates procps bash git curl unzip xz-utils

# This machine's TLS-intercepting proxy (see build.sh). Empty when there is none.
COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

# One line per package, OK or MISSING, so a candidate that could not be installed shows up
# as a missing tool rather than as a target that refused.
RUN for p in nodejs npm openjdk-21-jre-headless php-cli php-xml php-mbstring ruby pgformatter; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt

# A statically linked binary to hold the static question's red against (busybox-static).
RUN apt-get install -y --no-install-recommends busybox-static > /tmp/apt-busybox.log 2>&1 && file -bL /bin/busybox

ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Release binaries, each version pinned in its URL. One line per tool, OK or MISSING.
RUN set -u; mkdir -p /opt/bin /tmp/dl; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/mvdan/gofumpt/releases/download/v0.12.0/gofumpt_v0.12.0_linux_arm64 gofumpt; \
    get $gh/google/yamlfmt/releases/download/v0.21.0/yamlfmt_0.21.0_Linux_arm64.tar.gz yamlfmt.tgz; \
    get https://get.helm.sh/helm-v4.3.0-linux-arm64.tar.gz helm.tgz; \
    get $gh/google/go-jsonnet/releases/download/v0.22.0/go-jsonnet_0.22.0_linux_arm64.tar.gz jsonnet.tgz; \
    get https://releases.hashicorp.com/terraform/1.16.4/terraform_1.16.4_linux_arm64.zip terraform.zip; \
    get https://dl.k8s.io/release/v1.37.1/bin/linux/arm64/kubectl kubectl; \
    get "$gh/biomejs/biome/releases/download/%40biomejs%2Fbiome%402.5.14/biome-linux-arm64" biome; \
    get $gh/rvben/rumdl/releases/download/v0.2.77/rumdl-v0.2.77-aarch64-unknown-linux-gnu.tar.gz rumdl.tgz; \
    get $gh/quarylabs/sqruff/releases/download/v0.40.0/sqruff-linux-aarch64-musl.tar.gz sqruff.tgz; \
    get $gh/tombi-toml/tombi/releases/download/v1.5.6/tombi-cli-1.5.6-aarch64-unknown-linux-musl.tar.gz tombi.tgz; \
    get $gh/kamadorueda/alejandra/releases/download/4.0.0/alejandra-aarch64-unknown-linux-musl alejandra; \
    get $gh/PHPCSStandards/PHP_CodeSniffer/releases/download/4.0.4/phpcbf.phar phpcbf.phar; \
    get $gh/laravel/pint/releases/download/v1.32.1/pint.phar pint.phar; \
    get $gh/Kotlin/ktfmt/releases/download/v0.64/ktfmt-0.64-with-dependencies.jar ktfmt.jar; \
    get $gh/scalameta/scalafmt/releases/download/v3.11.5/scalafmt-aarch64-pc-linux.zip scalafmt.zip; \
    ls -l /tmp/dl
RUN set -u; cd /tmp/dl; \
    for t in yamlfmt helm jsonnet rumdl sqruff tombi; do mkdir -p x-$t && tar xzf $t.tgz -C x-$t && echo "untar $t: ok" || echo "untar $t: FAILED"; done; \
    unzip -q -o terraform.zip -d x-terraform; unzip -q -o scalafmt.zip -d x-scalafmt; \
    for b in gofumpt kubectl biome alejandra; do install -m 755 $b /opt/bin/$b; done; \
    for n in yamlfmt helm jsonnetfmt rumdl sqruff tombi terraform scalafmt; do \
      f=$(find /tmp/dl/x-* -type f -name "$n" | head -1); \
      [ -n "$f" ] && install -m 755 "$f" /opt/bin/$n && echo "bin $n <- $f" || echo "bin $n: NOT FOUND"; \
    done; \
    install -m 644 phpcbf.phar pint.phar ktfmt.jar /opt/bin/; ls -l /opt/bin

ENV PATH=/opt/bin:/opt/py/bin:$PATH

# Versions pinned, and each install's tail kept, so a failure names itself.
RUN python3 -m venv /opt/py \
    && /opt/py/bin/pip install --no-cache-dir nbqa==1.9.1 black==26.5.1 > /tmp/pip.log 2>&1; \
    echo "pip exit: $?"; tail -2 /tmp/pip.log
RUN npm install -g --no-fund --no-audit oxfmt@0.70.0 > /tmp/npm.log 2>&1; \
    echo "npm exit: $?"; tail -3 /tmp/npm.log
# standard's dependency prism builds a C extension: the first build of this box failed there
# ("can't find header files for ruby"), which is what these two packages answer.
RUN apt-get install -y --no-install-recommends ruby-dev build-essential > /tmp/apt-rubydev.log 2>&1; echo "apt ruby-dev exit: $?"
RUN gem install --no-document standard -v 1.56.0 > /tmp/gem.log 2>&1; \
    echo "gem exit: $?"; tail -3 /tmp/gem.log

# The adoption step itself — the page's command, stdout and stderr kept apart so "stdout is
# the binary's absolute path and nothing else" can be checked (release-path's finding).
COPY install-sideeye.sh /opt/install-sideeye.sh
RUN sh /opt/install-sideeye.sh v1.7.0 /opt/se > /install.path 2>/install.log; \
    echo "installer exit: $?"; \
    echo "stdout: [$(cat /install.path)]"; \
    grep -E 'digest|sideeye ' /install.log || true
RUN "$(cat /install.path)" version

# What was installed, as the tools report themselves, for the SELECTION table.
RUN { echo "sideeye: $("$(cat /install.path)" version)"; \
      echo "gofumpt: $(gofumpt --version)"; echo "yamlfmt: $(yamlfmt -version)"; \
      echo "helm: $(helm version --short)"; echo "jsonnetfmt: $(jsonnetfmt --version)"; \
      echo "terraform: $(terraform version | head -1)"; echo "kubectl: $(kubectl version --client | head -1)"; \
      echo "biome: $(biome --version)"; echo "rumdl: $(rumdl --version)"; echo "sqruff: $(sqruff --version)"; \
      echo "tombi: $(tombi --version)"; echo "alejandra: $(alejandra --version)"; \
      echo "phpcbf: $(php /opt/bin/phpcbf.phar --version | head -1)"; echo "pint: $(php /opt/bin/pint.phar --version | head -1)"; \
      echo "ktfmt: $(java -jar /opt/bin/ktfmt.jar --version 2>&1 | tail -1)"; echo "scalafmt: $(scalafmt --version)"; \
      echo "oxfmt: $(oxfmt --version)"; echo "nbqa: $(nbqa --version)"; echo "black: $(black --version | head -1)"; \
      echo "standardrb: $(standardrb --version)"; echo "pg_format: $(pg_format --version)"; \
      echo "node: $(node --version)"; echo "java: $(java -version 2>&1 | head -1)"; \
      echo "php: $(php --version | head -1)"; echo "ruby: $(ruby --version)"; } > /versions.txt 2>&1; cat /versions.txt

WORKDIR /w
