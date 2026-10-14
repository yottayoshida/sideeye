# The box for the 2026-10-14 mechanisms run (#861): Sideeye v1.12.0 installed the way
# docs/ci-quickstart.md tells a project to install it, and the candidates of CANDIDATES.md beside it.
# Base copied from 2026-10-12 shipped-v1120's Dockerfile; its tool layers are not carried over.
#
# Every candidate is Debian trixie's package as `apt install` gave it on 2026-10-14: the sources are
# snapshot.debian.org at that instant, so a rebuild installs the same versions, and /versions.txt
# keeps `dpkg-query -W` for the transcript.
#
# Built by build.sh. Network at build only; every gate, explore and replay runs `--network none`.
# linux/arm64 (this machine's Docker).
FROM debian:trixie-slim

COPY proxy-ca.pem /tmp/proxy-ca.pem
# deb822 stanzas are separated by a blank line; without it the second stanza replaces the first
# and only the security archive is seen (transcripts/build-1.txt).
RUN printf '%s\n' \
      'Types: deb' \
      'URIs: http://snapshot.debian.org/archive/debian/20261014T000000Z' \
      'Suites: trixie trixie-updates' \
      'Components: main' \
      'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg' \
      '' \
      'Types: deb' \
      'URIs: http://snapshot.debian.org/archive/debian-security/20261014T000000Z' \
      'Suites: trixie-security' \
      'Components: main' \
      'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg' \
      > /etc/apt/sources.list.d/debian.sources && \
    printf '%s\n' 'Acquire::Check-Valid-Until "false";' 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/99snapshot

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps bash curl gcc libc6-dev
RUN cp /tmp/proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt && update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

COPY install-sideeye.sh /opt/install-sideeye.sh
RUN sh /opt/install-sideeye.sh v1.12.0 /opt/se > /install.path 2>/install.log; \
    echo "installer exit: $?"; \
    echo "stdout: [$(cat /install.path)]"; \
    grep -E 'digest|sideeye ' /install.log || true
RUN "$(cat /install.path)" version

# ---- the candidates (CANDIDATES.md), every one from the pinned snapshot ----
# passwd (shadow-utils) and dpkg (update-alternatives, dpkg-divert, dpkg -i) are in the base image.
RUN apt-get install -y --no-install-recommends \
      fossil notmuch darcs isync vdirsyncer sqlite3 vim logrotate \
      python3-alembic python3-sqlalchemy python3-django sqlite-utils \
      libfaketime faketime > /tmp/apt-candidates.log 2>&1 && echo "OK candidates" || { echo "FAILED candidates"; tail -5 /tmp/apt-candidates.log; exit 1; }

COPY pin-random.c /opt/pin/pin-random.c
RUN gcc -shared -fPIC -O2 -o /opt/pin/pin-random.so /opt/pin/pin-random.c -ldl && \
    python3 -c "import sys; sys.stdout.buffer.write(bytes((i * 131 + 7) % 256 for i in range(1 << 20)))" > /opt/pin/urandom.bin && echo "OK pin-random.so"

RUN dpkg-query -W -f '${Package} ${Version}\n' passwd dpkg fossil notmuch darcs isync vdirsyncer sqlite3 vim logrotate \
      python3-alembic python3-sqlalchemy python3-django sqlite-utils libfaketime strace > /versions.txt && cat /versions.txt
