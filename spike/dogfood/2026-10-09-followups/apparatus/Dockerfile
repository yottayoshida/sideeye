# The box for the 2026-10-09 follow-ups: the released Sideeye v1.10.0 installed the way
# docs/ci-quickstart.md tells a project to install it, beside two kinds of target —
#   - four walls of the 2026-10-09 user-data-4 run, to be asked under `--observe supervised` by name
#     (Kvantum and Hydrogen ended unresolvable_path, yarn and trash-cli multiple_threads_detected);
#   - three upstream fixes this project has not measured: neovim#41940 (commit 1dc9728dbd, in the
#     nightly), pymol-open-source#520 (PR #521, master edcda80f3a) and dwarfs#388 (commits on the
#     mhx/work branch), each beside the build the report was measured on.
# The base is 2026-10-09 user-data-4's, copied. Network at build only; every run is `--network none`.
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
RUN mkdir -p /opt/bin /tmp/dl && python3 -m venv /opt/py

COPY install-sideeye.sh /opt/install-sideeye.sh
RUN sh /opt/install-sideeye.sh v1.10.0 /opt/se > /install.path 2>/install.log; \
    echo "installer exit: $?"; \
    echo "stdout: [$(cat /install.path)]"; \
    grep -E 'digest|sideeye ' /install.log || true
RUN "$(cat /install.path)" version

# ---- the four walls, as 2026-10-09 user-data-4 installed them ----
RUN apt-get install -y --no-install-recommends qt6-style-kvantum hydrogen > /tmp/apt-walls.log 2>&1 && echo "OK kvantum hydrogen" || { echo "MISSING"; tail -3 /tmp/apt-walls.log; }
RUN npm install -g --no-fund --no-audit @yarnpkg/cli-dist@4.18.1 trash-cli@7.2.0 > /tmp/npm-walls.log 2>&1 && echo "OK yarn trash-cli" || { echo "FAILED"; tail -3 /tmp/npm-walls.log; }

# ---- neovim: the nightly (NVIM v0.13.0-dev-1824+g27ee55c09d, 48 commits past the fix 1dc9728dbd)
# and v0.12.5, the release neovim#41940 was measured on; each tarball's digest checked against the
# one the release publishes ----
RUN set -eu; cd /tmp/dl; gh=https://github.com/neovim/neovim/releases/download; \
    curl -fsSL -o nvim-nightly.tgz $gh/nightly/nvim-linux-arm64.tar.gz; \
    echo "ee0ad0d35d453a6e56ebb2e622419ee28003ea3ab2fe28c6175e97a022664f93  nvim-nightly.tgz" | sha256sum -c; \
    curl -fsSL -o nvim-0125.tgz $gh/v0.12.5/nvim-linux-arm64.tar.gz; \
    echo "1aa5ca085249580ae0f91eb14f27ec0919773ff2d99a163d03f3d6c21ac29725  nvim-0125.tgz" | sha256sum -c; \
    mkdir -p /opt/nvim-nightly /opt/nvim-0125; \
    tar xzf nvim-nightly.tgz -C /opt/nvim-nightly --strip-components=1; tar xzf nvim-0125.tgz -C /opt/nvim-0125 --strip-components=1; \
    ln -s /opt/nvim-nightly/bin/nvim /opt/bin/nvim-nightly; ln -s /opt/nvim-0125/bin/nvim /opt/bin/nvim-0125; \
    nvim-nightly --version | head -1; nvim-0125 --version | head -1

# ---- PyMOL: trixie's 3.1.0 (what pymol-open-source#520 was measured on) and master at edcda80f3a,
# the merge of PR #521, built with pip into a venv of its own ----
RUN apt-get install -y --no-install-recommends pymol libglew-dev libpng-dev libfreetype-dev libxml2-dev libglm-dev libnetcdf-dev cmake > /tmp/apt-pymol.log 2>&1 && echo "OK pymol and build deps" || { echo "MISSING"; tail -3 /tmp/apt-pymol.log; }
RUN set -u; cd /tmp/dl; curl -fsSL -o pymol.tgz https://github.com/schrodinger/pymol-open-source/archive/edcda80f3a.tar.gz && \
    mkdir -p x-pymol && tar xzf pymol.tgz -C x-pymol --strip-components=1 && \
    python3 -m venv /opt/pymol-main && /opt/pymol-main/bin/pip install --no-cache-dir ./x-pymol > /tmp/pip-pymol.log 2>&1 && \
    echo "pymol master: $(/opt/pymol-main/bin/python -c 'import pymol, pymol.cmd as c; print(c.get_version()[0])')" || { echo "FAILED pymol master"; tail -8 /tmp/pip-pymol.log; }

# ---- DwarFS: the 0.15.8 release (what dwarfs#388 was measured on) and the mhx/work CI build at
# f7689c9a20, 10 commits past the fix fe09fbbc05 (stage/, its digest matched the artifact's) ----
COPY stage/dwarfs-work.tar.zst /tmp/dl/
RUN set -eu; cd /tmp/dl; \
    curl -fsSL -o dwarfs-0158.txz https://github.com/mhx/dwarfs/releases/download/v0.15.8/dwarfs-0.15.8-Linux-aarch64.tar.xz; \
    echo "ee100574a1340ad054bdf7543bedde3bd040639114ede65f1c20e08567eff2b1  dwarfs-0158.txz" | sha256sum -c; \
    echo "9838d66086bf5c72f47931ca87854001552b1d2c1a75c40770515e01c48eaa2e  dwarfs-work.tar.zst" | sha256sum -c; \
    mkdir -p /opt/dwarfs-0158 /opt/dwarfs-work; \
    tar xJf dwarfs-0158.txz -C /opt/dwarfs-0158 --strip-components=1; \
    tar --zstd -xf dwarfs-work.tar.zst -C /opt/dwarfs-work --strip-components=1; \
    ln -s /opt/dwarfs-0158/bin/mkdwarfs /opt/bin/mkdwarfs-0158; \
    ln -s /opt/dwarfs-work/bin/mkdwarfs /opt/bin/mkdwarfs-work; \
    ln -s /opt/dwarfs-0158/bin/dwarfsck /opt/bin/dwarfsck-0158; \
    mkdwarfs-0158 --help 2>&1 | head -1; mkdwarfs-work --help 2>&1 | head -1
RUN { echo "nvim-nightly $(nvim-nightly --version | head -1)"; echo "nvim-0125 $(nvim-0125 --version | head -1)"; \
      echo "pymol-debian $(/usr/bin/python3 -c 'import pymol.cmd as c; print(c.get_version()[0])' 2>&1)"; \
      echo "pymol-main $(/opt/pymol-main/bin/python -c 'import pymol.cmd as c; print(c.get_version()[0])' 2>&1)"; \
      echo "mkdwarfs-0158 $(mkdwarfs-0158 --help 2>&1 | head -1)"; echo "mkdwarfs-work $(mkdwarfs-work --help 2>&1 | head -1)"; \
      echo "yarn $(yarn --version)"; echo "trash $(npm ls -g trash-cli 2>/dev/null | grep trash-cli)"; } | tee /versions.txt

# ---- added after the recount (PREDICTIONS.md, second table): Home Assistant 2026.10.0 in a venv of its
# own on a standalone Python 3.14 fetched by uv (it requires >= 3.14.2, trixie has 3.13), as
# 2026-10-05 user-data-2 installed 2026.9.4; dotter v0.13.5, the build 2026-10-03 measured ----
RUN /opt/py/bin/pip install --no-cache-dir uv > /tmp/pip-uv.log 2>&1 && UV_PYTHON_INSTALL_DIR=/opt/uvpy /opt/py/bin/uv venv -q -p 3.14 /opt/ha > /tmp/uv-venv.log 2>&1 \
      && VIRTUAL_ENV=/opt/ha /opt/py/bin/uv pip install -q homeassistant==2026.10.0 > /tmp/uv-ha.log 2>&1; echo "homeassistant exit: $?"; tail -3 /tmp/uv-ha.log; ln -s /opt/ha/bin/hass /opt/bin/hass; /opt/ha/bin/python --version
RUN set -eu; cd /tmp/dl; curl -fsSL -o dotter https://github.com/SuperCuber/dotter/releases/download/v0.13.5/dotter-linux-arm64-musl; install -m 755 dotter /opt/bin/dotter; dotter --version
RUN { echo "hass $(/opt/ha/bin/python -c 'import homeassistant.const as c; print(c.__version__)' 2>&1)"; echo "dotter $(dotter --version 2>&1)"; } | tee -a /versions.txt
