# Set 1's reserves (transcripts/scout-1.txt), for the targets set 1 met a wall on: vmrestore, Flyway,
# RocksDB's ldb. Latest releases for linux/arm64 as GitHub answered on 2026-10-25; ldb is Debian
# trixie's rocksdb-tools 9.10.0 (upstream publishes no binary; upstream is 11.8.1).
FROM sideeye-sv1025-s1
RUN set -u; cd /tmp/dl; gh=https://github.com; \
    get() { curl -fsSL -o "$2" "$1" && echo "OK $2" || echo "MISSING $2 ($1)"; }; \
    get $gh/VictoriaMetrics/VictoriaMetrics/releases/download/v1.154.1/vmutils-linux-arm64-v1.154.1.tar.gz vmutils.tgz; \
    get $gh/VictoriaMetrics/VictoriaMetrics/releases/download/v1.154.1/victoria-metrics-linux-arm64-v1.154.1.tar.gz vm.tgz; \
    get $gh/flyway/flyway/releases/download/flyway-13.11.1/flyway-commandline-13.11.1.tar.gz flyway.tgz; \
    mkdir -p x-vm && tar xzf vmutils.tgz -C x-vm && tar xzf vm.tgz -C x-vm && \
      for b in vmbackup-prod vmrestore-prod victoria-metrics-prod; do install -m 755 "x-vm/$b" "/opt/bin/${b%-prod}"; done; \
    mkdir -p /opt/flyway && tar xzf flyway.tgz -C /opt/flyway --strip-components=1 && ln -sf /opt/flyway/flyway /opt/bin/flyway; \
    ls -l /opt/bin
RUN apt-get install -y --no-install-recommends openjdk-21-jre-headless rocksdb-tools > /tmp/apt-1b.log 2>&1 && echo "OK jre rocksdb-tools" || { echo "MISSING jre/rocksdb-tools"; tail -3 /tmp/apt-1b.log; }
RUN { cat /versions.txt; echo "vmrestore $(vmrestore -version 2>&1 | head -1)"; echo "flyway $(flyway -v 2>&1 | grep -i -m1 'flyway')"; \
      echo "ldb $(dpkg-query -W rocksdb-tools)"; echo "java $(java -version 2>&1 | head -1)"; \
      for b in vmrestore ldb; do echo "link $b: $(file -bL $(command -v $b) | cut -c1-90)"; done; } > /versions.new && mv /versions.new /versions.txt && cat /versions.txt
