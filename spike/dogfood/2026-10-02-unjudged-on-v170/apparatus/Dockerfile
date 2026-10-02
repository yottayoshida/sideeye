# The box for the 2026-10-02 unjudged-on-v170 run: the 2026-09-28 box, and the tools of the
# targets no campaign has carried to a verdict.
#
# `sideeye-sv170` is the image the 2026-09-28 shipped-v170 run built
# (`../../2026-09-28-shipped-v170/apparatus/build.sh` and `Dockerfile`): Debian trixie, the
# released v1.7.0 installed by the page's installer (`/install.path`, `/install.log`), this
# machine's proxy CA already trusted. Nothing here touches the engine.
#
# Network: this build, and nothing after it. Every run is `docker run --network none`.
# linux/arm64. One line per package or download, OK or MISSING, so a tool that could not be
# installed shows up as a missing tool and not as a target that refused.
FROM sideeye-sv170

RUN apt-get update > /tmp/apt-uj-update.log 2>&1; echo "apt update exit: $?"

# Debian's own packages, at trixie's versions — the way each earlier run installed them.
RUN for p in flac python3-mutagen lame fontforge fonts-dejavu-core mupdf-tools beets \
             zstd lz4 bat ccache meson ninja-build gcc libc6-dev \
             ocrmypdf tesseract-ocr-eng ghostscript fish vim rrdtool ormolu \
             faketime libfaketime python3-pip \
             make g++ python3-dev libsecret-1-dev pkg-config libnode-dev; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-uj-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-uj-summary.txt

# joplin, as 2026-09-13-joplin-turns installed it (a native build).
ENV npm_config_nodedir=/usr
RUN pip3 install --break-system-packages setuptools > /tmp/pip-setuptools.log 2>&1; \
    npm config set registry https://registry.npmjs.org/ \
    && npm install -g --unsafe-perm joplin@3.7.1 > /tmp/npm-joplin.log 2>&1; \
    echo "npm joplin exit: $?"; tail -2 /tmp/npm-joplin.log; \
    joplin version > /dev/null 2>&1; echo "joplin version rc=$?"

# The three static release binaries of 2026-09-27-supervised-static, and ktlint and git-cliff
# as 2026-09-22-shipped-v160 installed them.
RUN set -u; mkdir -p /tmp/dl /opt/cz /opt/gp; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/twpayne/chezmoi/releases/download/v2.72.1/chezmoi_2.72.1_linux_arm64.tar.gz chezmoi.tgz; \
    get $gh/gopasspw/gopass/releases/download/v1.17.0/gopass-1.17.0-linux-arm64.tar.gz gopass.tgz; \
    get $gh/evilmartians/lefthook/releases/download/v1.13.6/lefthook_1.13.6_Linux_arm64 lefthook; \
    get $gh/pinterest/ktlint/releases/download/1.8.0/ktlint ktlint; \
    sha256sum chezmoi.tgz gopass.tgz lefthook ktlint | tee /tmp/dl-uj-sums.txt; \
    tar xzf chezmoi.tgz -C /opt/cz && install -m 755 /opt/cz/chezmoi /usr/local/bin/chezmoi; \
    tar xzf gopass.tgz -C /opt/gp && install -m 755 /opt/gp/gopass /usr/local/bin/gopass; \
    install -m 755 lefthook /usr/local/bin/lefthook; install -m 755 ktlint /opt/ktlint; \
    /opt/py/bin/pip install --no-cache-dir git-cliff==2.14.2 > /tmp/pip-git-cliff.log 2>&1; echo "pip git-cliff exit: $?"; \
    [ -x /opt/py/bin/git-cliff ] && ln -sf /opt/py/bin/git-cliff /usr/local/bin/git-cliff; ls -l /usr/local/bin | tail -5

# Newer releases of three tools the 2026-10-02 gate-cleared-twelve run measured at the box's
# versions and recorded as "not measured" at their latest: each beside the old one, not over it.
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    npm install --prefix /opt/oxfmt071 --no-fund --no-audit oxfmt@0.71.0 > /tmp/npm-oxfmt071.log 2>&1; echo "npm oxfmt@0.71.0 exit: $?"; \
    curl -fsSL -o pgf511.tgz $gh/darold/pgFormatter/archive/refs/tags/v5.11.tar.gz && mkdir -p /opt/pgf511 \
      && tar xzf pgf511.tgz -C /opt/pgf511 --strip-components=1 && echo "OK pgFormatter v5.11" || echo "MISSING pgFormatter v5.11"; \
    curl -fsSL -o /opt/bin/php-cs-fixer.phar $gh/PHP-CS-Fixer/PHP-CS-Fixer/releases/download/v3.95.27/php-cs-fixer.phar \
      && echo "OK php-cs-fixer v3.95.27" || echo "MISSING php-cs-fixer v3.95.27"; \
    sha256sum pgf511.tgz /opt/bin/php-cs-fixer.phar | tee -a /tmp/dl-uj-sums.txt

# The npm tools, at the versions the earlier runs recorded: eslint, stylelint and js-beautify
# as 2026-09-22-shipped-v160 pinned them; prettier and svgo as 2026-09-16-crossed-walls'
# transcripts report them (that run installed them unpinned).
RUN npm install -g --no-fund --no-audit eslint@10.11.0 stylelint@17.15.0 js-beautify@2.0.3 \
      prettier@3.9.7 svgo@4.1.0 > /tmp/npm-uj.log 2>&1; echo "npm exit: $?"; tail -2 /tmp/npm-uj.log

# Bitwarden CLI, at the version 2026-09-16-outside-git's transcripts report (that run installed
# it unpinned).
RUN npm install -g --no-fund --no-audit @bitwarden/cli@2026.8.0 > /tmp/npm-bw.log 2>&1; echo "npm bw exit: $?"; tail -2 /tmp/npm-bw.log; bw --version
