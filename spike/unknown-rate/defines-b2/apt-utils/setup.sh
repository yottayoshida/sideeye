#!/bin/sh
set -eu
mkdir -p "$TOY_STATE/pool" "$TOY_STATE/dists/x/main/binary-arm64" "$TOY_STATE/pkg/DEBIAN"
cat > "$TOY_STATE/pkg/DEBIAN/control" <<'EOF'
Package: seeded
Version: 1.0
Architecture: all
Maintainer: nobody <nobody@example.org>
Description: seeded package
EOF
# A deterministic .deb: the tar inside carries mtimes, so pin them.
export SOURCE_DATE_EPOCH=946684800
touch -t 200001010000 "$TOY_STATE/pkg" "$TOY_STATE/pkg/DEBIAN" "$TOY_STATE/pkg/DEBIAN/control"
dpkg-deb --root-owner-group -b "$TOY_STATE/pkg" "$TOY_STATE/pool/seeded_1.0_all.deb" >/dev/null
touch -t 200001010000 "$TOY_STATE/pool/seeded_1.0_all.deb"
cat > "$TOY_STATE/apt.conf" <<EOF
Dir { ArchiveDir "$TOY_STATE"; };
Default { Packages::Compress ". gzip"; Contents::Compress ". gzip"; };
BinDirectory "pool" {
  Packages "dists/x/main/binary-arm64/Packages";
  Contents "dists/x/main/Contents-arm64";
};
EOF
