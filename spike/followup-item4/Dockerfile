# 2026-09-07 reach 計測用の箱。sideeye 本体は入れない（ホストからクロスビルドしてマウント）。
# apt lists の掃除はしない（omamori がホスト側で rm -rf の文字列を止めるため）。
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates bash gnupg pass rsync lame
# item 4 の対象。無いものは MISSING と印字して先へ進む（黙って飛ばさない）。
RUN for p in sqlfluff libvips-tools zstd ansible-core bundler git-annex git miller oxipng newsboat beets; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt
WORKDIR /w
