set -eu
# The tree the box built (vcpkg tool 2026-09-26, registry 2026.10.16, zlib and bzip2 installed for
# arm64-linux). The registry's ports, scripts and triplets are linked, the installed tree copied.
rm -rf /s/vcpkg && mkdir -p /s/vcpkg && cd /s/vcpkg
cp /opt/vcpkg-proto/vcpkg /opt/vcpkg-proto/.vcpkg-root /s/vcpkg/
for x in ports scripts triplets versions LICENSE.txt; do ln -s /opt/vcpkg-proto/$x $x; done
cp -a /opt/vcpkg-proto/installed /s/vcpkg/installed
install -m 755 /ap/defines/vcpkg/check.sh /s/vcpkg-check.sh
