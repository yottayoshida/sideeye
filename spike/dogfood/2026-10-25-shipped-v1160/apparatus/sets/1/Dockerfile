# Set 1 of the 2026-10-25 shipped-v1160 run: databases and storage (transcripts/scout-1.txt).
# Each tool from its own latest release for linux/arm64 as GitHub answered on 2026-10-25.
FROM sideeye-sv1025
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/etcd-io/etcd/releases/download/v3.7.3/etcd-v3.7.3-linux-arm64.tar.gz etcd.tgz; \
    get $gh/dolthub/dolt/releases/download/v2.6.0/dolt-linux-arm64.tar.gz dolt.tgz; \
    get $gh/tursodatabase/turso/releases/download/v0.8.3/turso_cli-aarch64-unknown-linux-gnu.tar.xz turso.txz; \
    get $gh/diesel-rs/diesel/releases/download/v2.3.14/diesel_cli-aarch64-unknown-linux-gnu.tar.xz diesel.txz; \
    get $gh/grafana/grafana/releases/download/v13.2.4/grafana_13.2.4_38252365904_linux_arm64.deb grafana.deb; \
    mkdir -p x-etcd && tar xzf etcd.tgz -C x-etcd && for b in etcd etcdutl etcdctl; do install -m 755 "$(find x-etcd -type f -name $b | head -1)" /opt/bin/$b; done; \
    mkdir -p x-dolt && tar xzf dolt.tgz -C x-dolt && install -m 755 "$(find x-dolt -type f -name dolt | head -1)" /opt/bin/dolt; \
    mkdir -p x-turso && tar xJf turso.txz -C x-turso && install -m 755 "$(find x-turso -type f -name tursodb | head -1)" /opt/bin/tursodb; \
    mkdir -p x-diesel && tar xJf diesel.txz -C x-diesel && install -m 755 "$(find x-diesel -type f -name diesel | head -1)" /opt/bin/diesel; \
    ls -l /opt/bin
RUN apt-get install -y --no-install-recommends /tmp/dl/grafana.deb > /tmp/apt-grafana.log 2>&1 && echo "OK grafana" || { echo "FAILED grafana"; tail -5 /tmp/apt-grafana.log; }
RUN apt-get install -y --no-install-recommends libpq5 libmariadb3 libsqlite3-0 sqlite3 > /tmp/apt-libs.log 2>&1; ldd /opt/bin/diesel | grep -i "not found" || echo "OK diesel links"
RUN { echo "etcdutl $(etcdutl version 2>&1 | head -1)"; echo "dolt $(dolt version 2>&1 | head -1)"; \
      echo "tursodb $(tursodb --version 2>&1 | head -1)"; echo "diesel $(diesel --version 2>&1 | head -1)"; \
      echo "grafana $(grafana cli --version 2>&1 | head -1)"; \
      for b in etcdutl dolt tursodb diesel /usr/share/grafana/bin/grafana; do echo "link $b: $(file -bL $(command -v $b || echo $b) | cut -c1-90)"; done; } | tee /versions.txt
