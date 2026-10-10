# The box for 2026-10-10 thread-order (#687): the released Sideeye v1.10.0 beside the five static
# targets #687 names as stopping at --observe supervised's threads wall, each pinned by the digest
# GitHub publishes for its release asset, and the two C controls the reader is checked against.
# The base is follow-ups 6's, with gcc for the controls.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps bash git curl xz-utils gcc libc6-dev

COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    PATH=/opt/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
RUN mkdir -p /opt/bin /tmp/dl

COPY install-sideeye.sh /opt/install-sideeye.sh
RUN sh /opt/install-sideeye.sh v1.10.0 /opt/se > /install.path 2>/install.log; \
    echo "installer exit: $?"; \
    echo "stdout: [$(cat /install.path)]"; \
    grep -E 'digest|sideeye ' /install.log || true
RUN "$(cat /install.path)" version

# name|url|sha256 — the digests are the ones GitHub lists for each asset (gh api .../releases/tags/<tag>).
RUN set -eu; cd /tmp/dl; gh=https://github.com; \
    for row in \
      "jj|$gh/jj-vcs/jj/releases/download/v0.46.0/jj-v0.46.0-aarch64-unknown-linux-musl.tar.gz|80e28f7501c11e50e0ca06cd6a1fa1d982cff9cc59bfe4411a9d36aa501d867e" \
      "tofu|$gh/opentofu/opentofu/releases/download/v1.13.1/tofu_1.13.1_linux_arm64.tar.gz|9c1ef375aa1852db0b2888aa921b640c71f8140d4682aa4fec99378a64fa7dc3" \
      "doctl|$gh/digitalocean/doctl/releases/download/v1.177.0/doctl-1.177.0-linux-arm64.tar.gz|3adfe5bb667c2cdee15eb3501d53b57d8f04dfa945ddd4584f6f760834506992" \
      "codex|$gh/openai/codex/releases/download/rust-v0.160.0/codex-aarch64-unknown-linux-musl.tar.gz|883620139925f677e5a12c95ba87a1d7f421388ebb797b1c10aba42a04ede9d7" \
      "notesmd-cli|$gh/Yakitrak/notesmd-cli/releases/download/v0.3.7/notesmd-cli_0.3.7_linux_arm64.tar.gz|3867ab60156ffd9fd938981e55f8fcbccdf5837ed518b640059a42c0e2f39ab4"; do \
      n=${row%%|*}; rest=${row#*|}; url=${rest%|*}; d=${rest##*|}; \
      curl -fsSL -o "$n.tgz" "$url"; \
      echo "$d  $n.tgz" | sha256sum -c; \
      mkdir -p "x-$n" && tar xzf "$n.tgz" -C "x-$n"; \
      install -m 755 "$(find "x-$n" -type f -name "$n*" -perm -u+x | head -1)" "/opt/bin/$n"; \
    done; \
    { echo "jj: $(jj --version)"; echo "tofu: $(tofu version | head -1)"; echo "doctl: $(doctl version | head -1)"; \
      echo "codex: $(codex --version)"; echo "notesmd-cli: $(notesmd-cli --version 2>&1 | head -1)"; \
      for b in jj tofu doctl codex notesmd-cli; do file -b "/opt/bin/$b" | sed "s|^|$b: |"; done; } | tee /versions.txt

COPY controls /opt/controls
RUN gcc -O2 -Wall -pthread -o /opt/bin/ctl-ordered /opt/controls/ordered.c && \
    gcc -O2 -Wall -pthread -o /opt/bin/ctl-condvar /opt/controls/condvar.c && \
    echo "controls: $(ls /opt/bin/ctl-*)" | tee -a /versions.txt
