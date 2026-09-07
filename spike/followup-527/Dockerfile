# 2026-09-07: --observe wrappers と --observe syscalls を同じ対象で並べて測る箱。
# 2026-09-05 と 09-06 の dogfood run が測った 14 対象を1つの image にまとめる
# （どの対象がどの run 由来かは RESULTS.md の表が持つ）。
# sideeye 本体は入れない（ホストからクロスビルドしてマウント）。
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates \
      flac python3-mutagen fontforge fonts-dejavu-core lame mupdf-tools \
      fonttools python3-fonttools libarchive-tools beancount \
      isort pyupgrade libjpeg-turbo-progs \
      imagemagick qpdf exiv2 rdiff-backup ffmpeg

WORKDIR /work
