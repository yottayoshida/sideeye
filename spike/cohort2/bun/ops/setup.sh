#!/bin/sh
# Cohort-2 bun define (P1) setup: the probe's pre-state shape — a minimal
# project in the state root, the dependency tarball outside it, ambient
# dirs fresh.
set -eu
B=/tmp/cohort2/bun
rm -rf "$B"
mkdir -p "$B/state" "$B/deppkg/package" "$B/ambient/home" "$B/ambient/cache" "$B/ambient/tmp"
cat > "$B/deppkg/package/package.json" <<'EOF'
{ "name": "probe-dep", "version": "1.0.0", "main": "index.js" }
EOF
printf 'module.exports = "probe-dep";\n' > "$B/deppkg/package/index.js"
touch -t 202601010000 "$B/deppkg/package/package.json" "$B/deppkg/package/index.js" "$B/deppkg/package"
tar -czf "$B/dep-1.0.0.tgz" -C "$B/deppkg" package
touch -t 202601010000 "$B/dep-1.0.0.tgz"
cat > "$B/state/package.json" <<'EOF'
{ "name": "probe-proj", "version": "1.0.0" }
EOF
touch -t 202601010000 "$B/state/package.json" "$B/state"
