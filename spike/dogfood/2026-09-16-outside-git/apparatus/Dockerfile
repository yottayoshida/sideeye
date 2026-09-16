# 2026-09-16 outside-git: tools whose state is data a user keeps outside version control — a
# credentials file, editor history, a vault cache, user configuration. Sideeye is not in the image:
# the released v1.4.0 tarball and a cross-build of main 047592d are mounted at /se140 and /semain.
# apt lists are not cleaned (omamori blocks the rm -rf string on the host side).
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 python3-venv ca-certificates unzip procps bash
# Each candidate alone, so a missing package prints MISSING rather than failing the build.
RUN for p in awscli neovim openjdk-21-jdk-headless nodejs npm python3-pip; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt
# hatch is not packaged in Debian trixie; from PyPI, through the same proxy (--trusted-host).
RUN pip3 install --break-system-packages --trusted-host pypi.org --trusted-host files.pythonhosted.org hatch \
      > /tmp/pip-hatch.log 2>&1; tail -1 /tmp/pip-hatch.log
# jbang wants a JDK, not a JRE: with only a JRE on PATH it tries to download JDK 17 and fails.
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-arm64
# Node CLIs from npm. The container's TLS goes through an intercepting proxy, so strict-ssl is
# off for the install (the 2026-09-11 joplin recipe).
RUN npm config set registry https://registry.npmjs.org/ \
 && npm config set strict-ssl false \
 && npm install -g @bitwarden/cli @angular/cli > /tmp/npm-install.log 2>&1; tail -3 /tmp/npm-install.log
# jbang's platform-independent release zip and pyenv's v2.8.5 source archive, downloaded on the
# host; the jbang zip's digest matched the one its release publishes.
COPY jbang-0.141.0.zip pyenv-2.8.5.tar.gz /tmp/
RUN unzip -q /tmp/jbang-0.141.0.zip -d /opt && ln -s /opt/jbang-0.141.0/bin/jbang /usr/local/bin/jbang \
 && mkdir -p /opt/pyenv && tar -xzf /tmp/pyenv-2.8.5.tar.gz -C /opt/pyenv --strip-components=1 \
 && ln -s /opt/pyenv/bin/pyenv /usr/local/bin/pyenv
RUN { aws --version; hatch --version; nvim --version | head -1; java -version 2>&1 | head -1; \
      jbang version; node --version; bw --version; ng version 2>/dev/null | grep -i 'angular cli'; pyenv --version; } 2>&1
WORKDIR /w
