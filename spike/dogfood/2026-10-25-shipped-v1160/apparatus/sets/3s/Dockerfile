# systemd-sysusers at upstream's latest tag, v262.1, for the report: set 3 measured Debian trixie's
# 257.13 and spike/upstream-report-template.md asks for the latest release. Built from the tag with
# meson (run on Debian's Python: the box's PATH puts a venv without jinja2 first), the standalone binary only (no libsystemd-shared to install), beside Debian's.
FROM sideeye-sv1025-s3
RUN apt-get install -y --no-install-recommends meson ninja-build gperf python3-jinja2 libcap-dev libmount-dev libcrypt-dev pkgconf > /tmp/apt-sd.log 2>&1 && echo "OK build deps" || { echo "FAILED build deps"; tail -5 /tmp/apt-sd.log; }
RUN set -u; cd /tmp/dl; \
    curl -fsSL -o systemd.tgz https://github.com/systemd/systemd/archive/refs/tags/v262.1.tar.gz && echo "OK systemd.tgz"; \
    mkdir -p /opt/sd-src && tar xzf systemd.tgz -C /opt/sd-src --strip-components=1 && \
    cd /opt/sd-src && PATH=/usr/bin:/bin meson setup build -Dmode=release -Dstandalone-binaries=true -Dtests=false -Dman=disabled -Dhtml=disabled \
        > /tmp/meson-setup.log 2>&1 && echo "OK meson setup" || { echo "FAILED meson setup"; tail -30 /tmp/meson-setup.log; }
RUN cd /opt/sd-src && PATH=/usr/bin:/bin ninja -C build systemd-sysusers.standalone > /tmp/ninja.log 2>&1 && \
    install -m 755 build/systemd-sysusers.standalone /opt/bin/systemd-sysusers-262 && echo "OK sysusers 262" || { echo "FAILED ninja"; tail -30 /tmp/ninja.log; }
RUN { echo "systemd-sysusers-262 $(/opt/bin/systemd-sysusers-262 --version | head -1)"; echo "link: $(file -bL /opt/bin/systemd-sysusers-262 | cut -c1-90)"; echo "debian: $(systemd-sysusers --version | head -1)"; } | tee /versions.txt
