# The box for #943's acceptance: Alembic and SQLAlchemy as the 2026-10-14 mechanisms run installed
# them, from the same pinned snapshot. The engine is mounted, not installed. Network at build only;
# every run is `--network none`. linux/arm64.
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
      strace python3 python3-alembic python3-sqlalchemy sqlite3 ca-certificates procps > /tmp/apt.log 2>&1 \
      && echo "OK packages" || { tail -5 /tmp/apt.log; exit 1; }
RUN dpkg-query -W -f '${Package} ${Version}\n' python3-alembic python3-sqlalchemy sqlite3 strace > /versions.txt && cat /versions.txt
