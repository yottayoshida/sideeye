# Set 3's next reserve after Dokku (which this box cannot install as a user would; SELECTION.md):
# vcpkg, the tool vcpkg-glibc-arm64 from microsoft/vcpkg-tool's latest release (2026-09-26) over a
# depth-1 clone of microsoft/vcpkg's master as of 2026-10-25. Two header-only ports are installed here,
# at build, where the network is: the state the explores start from is a real install root.
FROM sideeye-sv1025-s3
RUN apt-get install -y --no-install-recommends cmake ninja-build zip tar > /tmp/apt-vcpkg.log 2>&1 && echo "OK cmake ninja"
ENV VCPKG_FORCE_SYSTEM_BINARIES=1 VCPKG_DISABLE_METRICS=1 VCPKG_ROOT=/opt/vcpkg
RUN set -u; git clone -q --depth 1 https://github.com/microsoft/vcpkg.git /opt/vcpkg && git -C /opt/vcpkg log -1 --format='vcpkg ports commit %H %cs' && \
    curl -fsSL -o /opt/vcpkg/vcpkg https://github.com/microsoft/vcpkg-tool/releases/download/2026-09-26/vcpkg-glibc-arm64 && chmod 755 /opt/vcpkg/vcpkg && \
    /opt/vcpkg/vcpkg version | head -1
RUN cd /opt/vcpkg && ./vcpkg install nlohmann-json utfcpp --x-install-root=/opt/vcpkg-installed > /tmp/vcpkg-install.log 2>&1 && echo "OK vcpkg install" || { echo "FAILED vcpkg install"; tail -30 /tmp/vcpkg-install.log; }; \
    ls /opt/vcpkg-installed /opt/vcpkg-installed/vcpkg; cat /opt/vcpkg-installed/vcpkg/status | grep -E "^Package|^Status" | paste - - | head
RUN { echo "vcpkg $(/opt/vcpkg/vcpkg version | head -1)"; echo "vcpkg ports $(git -C /opt/vcpkg log -1 --format='%H %cs')"; echo "link /opt/vcpkg/vcpkg: $(file -bL /opt/vcpkg/vcpkg | cut -c1-80)"; } | tee -a /versions.txt
