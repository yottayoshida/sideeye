# The box for #947's measurement: vim and logrotate as the walls recorded them (vim 2:9.1.1230-2 in
# 2026-10-06-read-only-684, logrotate 3.22.0 in 2026-10-14-mechanisms), from the same pinned snapshot
# as the second, so a rebuild installs the same versions. The engine is mounted, not installed.
# Network at build only; every run is `--network none`. linux/arm64.
FROM debian:trixie-slim

COPY proxy-ca.pem /tmp/proxy-ca.pem
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
      strace python3 ca-certificates procps vim logrotate libfaketime faketime acl attr > /tmp/apt.log 2>&1 \
      && echo "OK packages" || { tail -5 /tmp/apt.log; exit 1; }
RUN dpkg-query -W -f '${Package} ${Version}\n' vim logrotate libfaketime strace acl > /versions.txt && cat /versions.txt
