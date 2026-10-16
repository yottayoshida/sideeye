FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f
COPY proxy-ca.pem /tmp/proxy-ca.pem
RUN printf '%s\n' \
      'Types: deb' \
      'URIs: http://snapshot.debian.org/archive/debian/20261015T000000Z' \
      'Suites: trixie trixie-updates' \
      'Components: main' \
      'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg' \
      '' \
      'Types: deb' \
      'URIs: http://snapshot.debian.org/archive/debian-security/20261015T000000Z' \
      'Suites: trixie-security' \
      'Components: main' \
      'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg' \
      > /etc/apt/sources.list.d/debian.sources && \
    printf '%s\n' 'Acquire::Check-Valid-Until "false";' 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/99snapshot
RUN rm -f /etc/dpkg/dpkg.cfg.d/docker /etc/dpkg/dpkg.cfg.d/excludes \
 && apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl strace coreutils python3 man-db less procps
RUN cp /tmp/proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt && update-ca-certificates > /dev/null 2>&1
RUN useradd -m user
WORKDIR /home/user/authoring
RUN curl -fsSL -o sideeye-v1.13.0-aarch64-linux.tar.gz \
      https://github.com/yottayoshida/sideeye/releases/download/v1.13.0/sideeye-v1.13.0-aarch64-linux.tar.gz \
 && echo "93046775f9f5e28f6f6716730aaa3cbab8fa1916c1f41ff0afc73b7cc1ed2e06  sideeye-v1.13.0-aarch64-linux.tar.gz" | sha256sum -c -
COPY v1.13.0/ /home/user/authoring/
COPY watch-defines.py /usr/local/bin/watch-defines.py
RUN mkdir -p /home/user/revisions /home/user/authoring/define \
 && chmod 0755 /usr/local/bin/watch-defines.py \
 && chown -R user:user /home/user
ARG TARGET_PKG
RUN apt-get install -y --no-install-recommends "$TARGET_PKG" \
 && dpkg-query -W -f '${Package}=${Version}\n' "${TARGET_PKG%%=*}" > /target-version.txt \
 && rm -rf /var/lib/apt/lists/* /tmp/proxy-ca.pem
USER user
ENV USER=user HOME=/home/user
CMD ["python3", "/usr/local/bin/watch-defines.py", "/home/user", "/home/user/revisions"]
