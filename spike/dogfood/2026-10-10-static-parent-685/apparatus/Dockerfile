# The box for #685's re-measurement: the three static parents whose dynamic child carried the shim,
# each installed the way the run that met it installed it (lefthook: 2026-10-02-unjudged-on-v170;
# aliyun-cli: 2026-10-05-user-data-2; roswell: 2026-10-07-user-data-3), and nothing else. No engine
# is installed: run.sh mounts the build under test at /se, so the box measures that build and not a
# release.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps git curl bzip2 make \
 && rm -rf /var/lib/apt/lists/*

COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

RUN set -eu; mkdir -p /tmp/dl && cd /tmp/dl; gh=https://github.com; \
    curl -fsSL -o lefthook "$gh/evilmartians/lefthook/releases/download/v1.13.6/lefthook_1.13.6_Linux_arm64"; \
    curl -fsSL -o aliyun.tgz "$gh/aliyun/aliyun-cli/releases/download/v3.5.1/aliyun-cli-linux-3.5.1-arm64.tgz"; \
    curl -fsSL -o ros.tbz "$gh/roswell/roswell/releases/download/v26.02.116/roswell-26.02.116-linux-arm64.tar.bz2"; \
    sha256sum lefthook aliyun.tgz ros.tbz | tee /downloads.sha256; \
    install -m 755 lefthook /usr/local/bin/lefthook; \
    mkdir -p y-aliyun && tar xzf aliyun.tgz -C y-aliyun && install -m 755 y-aliyun/aliyun /usr/local/bin/aliyun; \
    mkdir -p x-ros && tar xjf ros.tbz -C x-ros

# roswell by its own Makefile, then set up at build with the network on, so `ros config` finds an SBCL
# offline. ROSWELL_HOME is pinned under /opt so the define's home starts empty of everything but the
# config the seed writes (the 2026-10-07 layers eleven and twelve).
RUN set -eu; cd /tmp/dl/x-ros/roswell && make install > /tmp/ros-install.log 2>&1
RUN ROSWELL_HOME=/opt/roswell-home ros setup > /tmp/ros-setup.log 2>&1; ls /opt/roswell-home | head

RUN { lefthook version; aliyun version; ros version | head -1; file -L /usr/local/bin/lefthook /usr/local/bin/aliyun "$(command -v ros)" | cut -c1-140; } > /versions.txt 2>&1; cat /versions.txt
