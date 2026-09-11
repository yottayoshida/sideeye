# 2026-09-11 dogfood: targets that earlier dogfood runs turned away for threads or
# children, re-met with the released v1.3.0 (contract v16). Sideeye itself is not in
# the image: the release tarball is mounted at /se.
# apt lists are not cleaned (omamori blocks the rm -rf string on the host side).
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates unzip procps
# Each target alone, so a missing package prints MISSING rather than failing the build.
RUN for p in newsboat oxipng rsync ocrmypdf tesseract-ocr-eng ghostscript ansible-core; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt
# Bun's release binary, downloaded on the host (the container's TLS goes through an
# intercepting proxy). Latest stable at the time of the run.
COPY bun /usr/local/bin/bun
# joplin CLI, with the four fixes the 2026-09-05 run needed on trixie
# (spike/dogfood/2026-09-05-userview/apparatus/Dockerfile.joplin).
RUN apt-get install -y --no-install-recommends \
      nodejs npm make g++ python3-dev python3-pip libsecret-1-dev pkg-config libnode-dev
RUN pip3 install --break-system-packages \
      --trusted-host pypi.org --trusted-host files.pythonhosted.org setuptools
ENV npm_config_nodedir=/usr
RUN npm config set registry https://registry.npmjs.org/ \
 && npm config set strict-ssl false \
 && npm install -g --unsafe-perm joplin
RUN joplin version > /dev/null 2>&1; echo "joplin version rc=$?"; bun --version
# oxipng is not packaged in Debian trixie; its release binary (gnu target, dynamic),
# downloaded on the host. Last so the joplin layer above stays cached.
COPY oxipng /usr/local/bin/oxipng
RUN oxipng --version
WORKDIR /w
