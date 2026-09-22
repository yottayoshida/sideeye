# The box for the 2026-09-22 shipped-v160 run: Sideeye v1.6.0 installed the way
# docs/ci-quickstart.md tells a project to install it, and the nine candidates beside it.
#
# Built by build.sh, which stages the proxy CA and the vendored installer. Two stages of
# network, and only these two: the image build (install, packages) — and nothing after it.
# Every gate, explore and replay runs with `docker run --network none`.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 python3-venv ca-certificates procps bash git curl unzip

# This machine's TLS-intercepting proxy (see build.sh). Empty when there is none.
COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

# One line per package, OK or MISSING, so a candidate that could not be installed shows up
# as a missing tool rather than as a target that refused.
RUN for p in nodejs npm openjdk-21-jre-headless ormolu; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt

# A statically linked binary to hold the static question's red against (busybox-static).
RUN apt-get install -y --no-install-recommends busybox-static > /tmp/apt-busybox.log 2>&1 && file -bL /bin/busybox

ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# Versions pinned, and each install's tail kept, so a failure names itself.
RUN python3 -m venv /opt/py \
    && /opt/py/bin/pip install --no-cache-dir commitizen==4.18.1 ast-grep-cli==0.45.3 git-cliff==2.14.2 > /tmp/pip.log 2>&1; \
    echo "pip exit: $?"; tail -2 /tmp/pip.log
RUN npm install -g --no-fund --no-audit eslint@10.11.0 stylelint@17.15.0 js-beautify@2.0.3 > /tmp/npm.log 2>&1; \
    echo "npm exit: $?"; tail -3 /tmp/npm.log
RUN curl -fsSL -o /tmp/todo.tgz https://github.com/todotxt/todo.txt-cli/releases/download/v2.14.0/todo.txt_cli-2.14.0.tar.gz \
    && mkdir -p /opt/todo && tar xzf /tmp/todo.tgz -C /opt/todo --strip-components=1 && ls /opt/todo
RUN curl -fsSL -o /opt/ktlint https://github.com/pinterest/ktlint/releases/download/1.8.0/ktlint && chmod 755 /opt/ktlint

ENV PATH=/opt/py/bin:$PATH

# The adoption step itself — the page's command, stdout and stderr kept apart so "stdout is
# the binary's absolute path and nothing else" can be checked (release-path's finding).
COPY install-sideeye.sh /opt/install-sideeye.sh
RUN sh /opt/install-sideeye.sh v1.6.0 /opt/se > /install.path 2>/install.log; \
    echo "installer exit: $?"; \
    echo "stdout: [$(cat /install.path)]"; \
    grep -E 'digest|sideeye ' /install.log || true
RUN "$(cat /install.path)" version

# What was installed, as the tools report themselves, for the SELECTION table.
RUN { echo "sideeye: $("$(cat /install.path)" version)"; \
      echo "eslint: $(eslint --version)"; echo "stylelint: $(stylelint --version)"; \
      echo "js-beautify: $(js-beautify --version)"; echo "ast-grep: $(ast-grep --version)"; \
      echo "git-cliff: $(git-cliff --version)"; echo "commitizen: $(cz version)"; \
      echo "todo.txt: $(bash /opt/todo/todo.sh -V | head -1)"; \
      echo "ktlint: $(java -jar /opt/ktlint --version 2>/dev/null | tail -1)"; \
      echo "ormolu: $(ormolu --version | head -1)"; \
      echo "node: $(node --version)"; echo "java: $(java -version 2>&1 | head -1)"; } > /versions.txt 2>&1; cat /versions.txt

WORKDIR /w
