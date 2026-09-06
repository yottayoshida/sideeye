# ImageMagick main (3501ef34) を最小構成でビルドし、Debian 版 7.1.1-43 と同じ箱に置く。
# 目的は issue #8939 の patch (link_utf8 の追加) が backup~ を巻き添えにするかの実測。
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential pkg-config libpng-dev strace file imagemagick ca-certificates

# tarball は repo に入れていない（14 MB）。ビルド前にホストで取る:
#   gh api repos/ImageMagick/ImageMagick/tarball/3501ef340e01e615fffe436b9528d30b716a71c6 > im.tar.gz
COPY im.tar.gz /tmp/im.tar.gz
RUN mkdir -p /src && tar xzf /tmp/im.tar.gz -C /src --strip-components=1

WORKDIR /src
RUN ./configure --prefix=/opt/im --without-magick-plus-plus --disable-openmp \
      --without-x --with-png=yes > /tmp/configure.log 2>&1 \
    || { tail -40 /tmp/configure.log; exit 1; }
RUN make -j"$(nproc)" > /tmp/make.log 2>&1 || { tail -40 /tmp/make.log; exit 1; }
RUN make install > /tmp/install.log 2>&1 || { tail -20 /tmp/install.log; exit 1; }

ENV LD_LIBRARY_PATH=/opt/im/lib
WORKDIR /work
