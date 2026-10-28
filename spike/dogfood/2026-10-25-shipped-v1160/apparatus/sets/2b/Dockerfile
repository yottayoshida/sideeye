# Set 2's second box: what set 2's walls were asked next (transcripts/set-2-notes.md).
# Gogs v0.14.3 built from its tag with cgo, so the binary is dynamically linked and the shim can enter
# it — the release tarball's is static and met the threads wall under --observe supervised. Same
# source, same version; Go 1.27.3, the toolchain go.dev listed first on 2026-10-25.
FROM sideeye-sv1025-s2
RUN cd /tmp/dl && curl -fsSL -o go.tgz https://go.dev/dl/go1.27.3.linux-arm64.tar.gz && tar xzf go.tgz -C /opt && /opt/go/bin/go version
RUN set -eu; cd /tmp/dl && git clone -q --depth 1 --branch v0.14.3 https://github.com/gogs/gogs.git gogs-src && cd gogs-src && \
    CGO_ENABLED=1 GOFLAGS=-buildvcs=false /opt/go/bin/go build -o /opt/gogs-dyn/gogs ./ > /tmp/gogs-build.log 2>&1 || { tail -20 /tmp/gogs-build.log; exit 1; }; \
    cp -a /opt/gogs/templates /opt/gogs/public /opt/gogs/scripts /opt/gogs-dyn/ 2>/dev/null || true; \
    /opt/gogs-dyn/gogs --version; file -bL /opt/gogs-dyn/gogs | cut -c1-100
# gqlgen v0.17.98 (its linux arm64 release binary) and a project `gqlgen init` made, its modules
# downloaded here; at explore time GOPROXY=off and the module and build caches are outside the state.
ENV GOMODCACHE=/opt/gomod GOCACHE=/opt/gocache GOTOOLCHAIN=local PATH=/opt/go/bin:$PATH
RUN set -eu; cd /tmp/dl && curl -fsSL -o gqlgen.tgz https://github.com/99designs/gqlgen/releases/download/v0.17.98/gqlgen_Linux_arm64.tar.gz && \
    mkdir -p x-gqlgen && tar xzf gqlgen.tgz -C x-gqlgen && install -m 755 "$(find x-gqlgen -type f -name gqlgen | head -1)" /opt/bin/gqlgen; \
    mkdir -p /opt/gql-proto && cd /opt/gql-proto && go mod init example.com/notes > /dev/null 2>&1 && \
    go get github.com/99designs/gqlgen@v0.17.98 > /tmp/gql-get.log 2>&1 && gqlgen init > /tmp/gql-init.log 2>&1 && go mod tidy > /tmp/gql-tidy.log 2>&1 && go build ./... && \
    chmod -R a+rwX /opt/gomod /opt/gocache && ls -R /opt/gql-proto | head -30 && gqlgen version
# vcpkg: the tool 2026-09-26 (vcpkg-glibc-arm64) over the registry's release 2026.10.16, with two
# ports installed here (zlib, bzip2) so `vcpkg remove` has an installed tree to change. arm64 Linux
# needs the system's cmake and ninja (VCPKG_FORCE_SYSTEM_BINARIES).
RUN apt-get install -y --no-install-recommends cmake ninja-build zip > /tmp/apt-vcpkg.log 2>&1 && echo "OK cmake ninja" || { tail -3 /tmp/apt-vcpkg.log; exit 1; }
ENV VCPKG_FORCE_SYSTEM_BINARIES=1 VCPKG_DISABLE_METRICS=1
RUN set -eu; git clone -q --depth 1 --branch 2026.10.16 https://github.com/microsoft/vcpkg.git /opt/vcpkg-proto && \
    curl -fsSL -o /opt/vcpkg-proto/vcpkg https://github.com/microsoft/vcpkg-tool/releases/download/2026-09-26/vcpkg-glibc-arm64 && chmod 755 /opt/vcpkg-proto/vcpkg && \
    cd /opt/vcpkg-proto && ./vcpkg install zlib bzip2 > /tmp/vcpkg-install.log 2>&1 || { tail -30 /tmp/vcpkg-install.log; exit 1; }; \
    ./vcpkg list; ./vcpkg version | head -1; du -sh /opt/vcpkg-proto/installed /opt/vcpkg-proto/buildtrees /opt/vcpkg-proto/packages 2>/dev/null; true
RUN { cat /versions.txt; echo "gogs-dyn $(/opt/gogs-dyn/gogs --version 2>&1 | head -1) (built from v0.14.3 with cgo, $(/opt/go/bin/go version))"; \
      echo "gqlgen $(gqlgen version 2>&1 | head -1)"; echo "link /opt/bin/gqlgen: $(file -bL /opt/bin/gqlgen | cut -c1-100)"; echo "vcpkg $(/opt/vcpkg-proto/vcpkg version 2>&1 | head -1)"; echo "link /opt/vcpkg-proto/vcpkg: $(file -bL /opt/vcpkg-proto/vcpkg | cut -c1-100)"; echo "link /opt/gogs-dyn/gogs: $(file -bL /opt/gogs-dyn/gogs | cut -c1-100)"; } > /versions.new && mv /versions.new /versions.txt
