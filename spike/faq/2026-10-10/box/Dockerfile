FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 python3-pytest ca-certificates curl gcc libc6-dev cargo golang-go
COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log
COPY install-sideeye.sh /tmp/install-sideeye.sh
RUN sh /tmp/install-sideeye.sh --selftest >/dev/null && sh /tmp/install-sideeye.sh v1.10.0 /opt/sideeye > /install.path && cat /install.path
RUN ln -s "$(cat /install.path)" /usr/local/bin/sideeye && sideeye version && \
    { echo "python: $(python3 --version)"; echo "pytest: $(pytest --version 2>&1)"; echo "cargo: $(cargo --version)"; \
      echo "go: $(go version)"; echo "strace: $(strace -V | head -1)"; } > /versions.txt && cat /versions.txt
WORKDIR /work
