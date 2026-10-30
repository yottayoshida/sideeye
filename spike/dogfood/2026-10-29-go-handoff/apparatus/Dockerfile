# The box for #987's measurement: the eight static Go tools the 2026-10-25 shipped-v1160 run met the
# threads wall with under --observe supervised, at the versions and from the assets that run used
# (its sets 1, 1b, 2, 2b, 3 and 4, layer for layer), and strace. No Sideeye: every run here is the
# operation under strace, without the engine. The defines are 2026-10-25's own, mounted at /ap.
#
# Built by build.sh. Network at build only; every run is `--network none`. linux/arm64.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps bash git curl xz-utils build-essential \
      sqlite3 libsqlite3-0 libtag2 libfontconfig1

COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    PATH=/opt/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
RUN mkdir -p /opt/bin /tmp/dl

# Set 1: etcd 3.7.3, Dolt 2.6.0, Grafana 13.2.4.
RUN set -eu; cd /tmp/dl; gh=https://github.com; \
    curl -fsSL -o etcd.tgz $gh/etcd-io/etcd/releases/download/v3.7.3/etcd-v3.7.3-linux-arm64.tar.gz; \
    curl -fsSL -o dolt.tgz $gh/dolthub/dolt/releases/download/v2.6.0/dolt-linux-arm64.tar.gz; \
    curl -fsSL -o grafana.deb $gh/grafana/grafana/releases/download/v13.2.4/grafana_13.2.4_38252365904_linux_arm64.deb; \
    mkdir -p x-etcd && tar xzf etcd.tgz -C x-etcd && for b in etcd etcdutl etcdctl; do install -m 755 "$(find x-etcd -type f -name $b | head -1)" /opt/bin/$b; done; \
    mkdir -p x-dolt && tar xzf dolt.tgz -C x-dolt && install -m 755 "$(find x-dolt -type f -name dolt | head -1)" /opt/bin/dolt
RUN apt-get install -y --no-install-recommends /tmp/dl/grafana.deb > /tmp/apt-grafana.log 2>&1 || { tail -5 /tmp/apt-grafana.log; exit 1; }

# Set 1b: vmrestore, vmbackup and the server, 1.154.1.
RUN set -eu; cd /tmp/dl; gh=https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v1.154.1; \
    curl -fsSL -o vmutils.tgz $gh/vmutils-linux-arm64-v1.154.1.tar.gz; curl -fsSL -o vm.tgz $gh/victoria-metrics-linux-arm64-v1.154.1.tar.gz; \
    mkdir -p x-vm && tar xzf vmutils.tgz -C x-vm && tar xzf vm.tgz -C x-vm && \
    for b in vmbackup-prod vmrestore-prod victoria-metrics-prod; do install -m 755 "x-vm/$b" "/opt/bin/${b%-prod}"; done

# Set 2: Gogs 0.14.3 and the instance its define restores over (set 2's layer, unchanged).
RUN cd /tmp/dl && curl -fsSL -o gogs.tgz https://github.com/gogs/gogs/releases/download/v0.14.3/gogs_v0.14.3_linux_arm64.tar.gz && \
    tar xzf gogs.tgz -C /opt && ln -sf /opt/gogs/gogs /opt/bin/gogs
COPY gogs-app.ini /opt/gogs-proto/custom/conf/app.ini
RUN set -eu; P=/opt/gogs-proto; mkdir -p $P/data/avatars $P/repositories /s/gogsaux/log; cd $P; \
    export GOGS_WORK_DIR=$P GOGS_CUSTOM=$P/custom; \
    (gogs web --config $P/custom/conf/app.ini > /tmp/gogs-web.log 2>&1 & echo $! > /tmp/gogs.pid; sleep 8; kill $(cat /tmp/gogs.pid)); sleep 1; \
    gogs admin create-user --config $P/custom/conf/app.ini --name alice --password 'correct-horse-9' --email alice@example.com --admin; \
    mkdir -p $P/repositories/alice/notes.git && git init -q --bare $P/repositories/alice/notes.git; \
    printf 'avatar-of-alice-v1' > $P/data/avatars/1; \
    mkdir -p /opt/gogs-backup && gogs backup --config $P/custom/conf/app.ini --target /opt/gogs-backup --archive-name gogs-backup.zip; \
    gogs admin create-user --config $P/custom/conf/app.ini --name bob --password 'battery-staple-7' --email bob@example.com; \
    printf 'avatar-of-alice-v2' > $P/data/avatars/1; printf 'avatar-of-bob' > $P/data/avatars/2

# Set 2b: Go 1.27.3, gqlgen 0.17.98 and the project `gqlgen init` made.
RUN cd /tmp/dl && curl -fsSL -o go.tgz https://go.dev/dl/go1.27.3.linux-arm64.tar.gz && tar xzf go.tgz -C /opt
ENV GOMODCACHE=/opt/gomod GOCACHE=/opt/gocache GOTOOLCHAIN=local PATH=/opt/go/bin:/opt/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
RUN set -eu; cd /tmp/dl && curl -fsSL -o gqlgen.tgz https://github.com/99designs/gqlgen/releases/download/v0.17.98/gqlgen_Linux_arm64.tar.gz && \
    mkdir -p x-gqlgen && tar xzf gqlgen.tgz -C x-gqlgen && install -m 755 "$(find x-gqlgen -type f -name gqlgen | head -1)" /opt/bin/gqlgen; \
    mkdir -p /opt/gql-proto && cd /opt/gql-proto && go mod init example.com/notes > /dev/null 2>&1 && \
    go get github.com/99designs/gqlgen@v0.17.98 > /tmp/gql-get.log 2>&1 && gqlgen init > /tmp/gql-init.log 2>&1 && go mod tidy > /tmp/gql-tidy.log 2>&1 && go build ./... && \
    chmod -R a+rwX /opt/gomod /opt/gocache

# Set 3: JuiceFS 1.4.2.
RUN set -eu; cd /tmp/dl; curl -fsSL -o jfs.tgz https://github.com/juicedata/juicefs/releases/download/v1.4.2/juicefs-1.4.2-linux-arm64.tar.gz && \
    mkdir -p x-jfs && tar xzf jfs.tgz -C x-jfs && install -m 755 "$(find x-jfs -type f -name juicefs | head -1)" /opt/bin/juicefs

# Set 4: Navidrome 0.64.2.
RUN set -eu; cd /tmp/dl; curl -fsSL -o nd.tgz https://github.com/navidrome/navidrome/releases/download/v0.64.2/navidrome_0.64.2_linux_arm64.tar.gz && \
    mkdir -p x-nd && tar xzf nd.tgz -C x-nd && install -m 755 x-nd/navidrome /opt/bin/navidrome

# The two controls: the race this measurement must see, and #687's turn-taking pair.
COPY controls/ /opt/controls/
RUN set -eu; cd /opt/controls; for c in race condvar; do gcc -O2 -pthread -o /opt/bin/ctl-$c $c.c; done

RUN { echo "strace $(strace -V | head -1)"; echo "etcdutl $(etcdutl version 2>&1 | head -1)"; echo "dolt $(dolt version 2>&1 | head -1)"; \
      echo "grafana $(/usr/share/grafana/bin/grafana --version 2>&1 | head -1)"; echo "vmrestore $(vmrestore -version 2>&1 | head -1)"; \
      echo "gogs $(gogs --version 2>&1 | head -1)"; echo "gqlgen $(gqlgen version 2>&1 | head -1)"; echo "go $(go version)"; \
      echo "juicefs $(juicefs --version 2>&1 | head -1)"; echo "navidrome $(navidrome --version 2>&1 | tail -1)"; \
      for b in /opt/bin/etcdutl /opt/bin/dolt /usr/share/grafana/bin/grafana /opt/bin/vmrestore /opt/gogs/gogs /opt/bin/gqlgen /opt/bin/juicefs /opt/bin/navidrome; do \
        echo "link $b: $(file -bL $b | cut -c1-90)"; done; } | tee /versions.txt
