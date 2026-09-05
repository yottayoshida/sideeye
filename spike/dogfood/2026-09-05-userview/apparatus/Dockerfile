# ユーザ目線テスト用の箱。sideeye 本体は入れない（ホストからクロスビルドしてマウントする）。
# cohort 1-3 と同じ作法: apt は plain HTTP なので通る。pip/npm は TLS 傍受プロキシに
# 当たる実測があるので trusted-host を付ける。
# apt lists の掃除はしない（omamori がホスト側で文字列を止めるため。image サイズだけの話）。
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace python3 python3-pip ca-certificates gcc libc6-dev \
      gnupg git ffmpeg file

# beets 2.13.1 — 対象4のうち唯一 Python。音楽ファイル移動 + タグ書き込み + library.db 更新
RUN pip3 install --break-system-packages \
      --trusted-host pypi.org --trusted-host files.pythonhosted.org \
      beets==2.13.1 \
 && beet --version

# 静的リンクの実測用。ユーザーが入れる公式配布物そのまま
COPY artifacts/x-chezmoi/chezmoi /usr/local/bin/chezmoi
COPY artifacts/x-gopass/gopass /usr/local/bin/gopass
RUN chezmoi --version && gopass --version

WORKDIR /work
