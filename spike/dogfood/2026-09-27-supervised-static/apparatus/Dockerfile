# The box for the 2026-09-27 supervised-static run: the spike image, the five statically linked
# release binaries the static-linkage wall names (digests checked by build.sh before COPY), and
# Debian's busybox-static at a pinned version. Network only here; every run is --network none.
FROM sideeye-spike

COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends ca-certificates git file \
         busybox-static=1:1.35.0-4+deb12u1+b1 > /tmp/apt.log 2>&1; \
    echo "apt exit: $?"; tail -1 /tmp/apt.log; update-ca-certificates > /dev/null 2>&1 || true

COPY assets/ /assets/
RUN set -e; cd /assets \
    && mkdir -p /opt/gh /opt/cz /opt/gp /opt/jj \
    && tar xzf gh_2.97.0_linux_arm64.tar.gz -C /opt/gh --strip-components=1 \
    && tar xzf chezmoi_2.72.1_linux_arm64.tar.gz -C /opt/cz \
    && tar xzf gopass-1.17.0-linux-arm64.tar.gz -C /opt/gp \
    && tar xzf jj-v0.44.0-aarch64-unknown-linux-musl.tar.gz -C /opt/jj \
    && install -m 755 /opt/gh/bin/gh /usr/local/bin/gh \
    && install -m 755 /opt/cz/chezmoi /usr/local/bin/chezmoi \
    && install -m 755 /opt/gp/gopass /usr/local/bin/gopass \
    && install -m 755 "$(find /opt/jj -type f -name jj | head -1)" /usr/local/bin/jj \
    && install -m 755 lefthook_1.13.6_Linux_arm64 /usr/local/bin/lefthook

# What is installed, as the tools and the package manager report it.
RUN { for b in gh chezmoi gopass jj; do echo "$b: $("$b" --version 2>&1 | head -1)"; done; \
      echo "lefthook: $(lefthook version 2>&1 | head -1)"; \
      echo "busybox-static: $(dpkg-query -W -f='${Version}' busybox-static)"; \
      echo "git: $(git --version)"; echo "strace: $(strace -V | head -1)"; \
      sha256sum /usr/local/bin/gh /usr/local/bin/chezmoi /usr/local/bin/gopass /usr/local/bin/jj \
                /usr/local/bin/lefthook /bin/busybox; } > /versions.txt 2>&1; cat /versions.txt

WORKDIR /w
