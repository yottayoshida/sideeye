#!/bin/sh
# Cohort-3 papis define (P1) setup: the library (state root) holding one
# existing document, plus the outside-root fixtures the operation reads.
# Fixture bytes are the accepted probe's, unchanged. The papis config,
# cache and HOME are ambient created here, outside the snapshot; the
# config's only variable is the library path.
set -eu
P=/tmp/cohort3/papis
rm -rf "$P/lib" "$P/xdg" "$P/cache" "$P/home"
mkdir -p "$P/lib" "$P/xdg/papis" "$P/cache" "$P/home"
printf 'existing document, fixed bytes' > "$P/existing.txt"
printf 'probe document, fixed bytes'    > "$P/fixture.txt"
cat > "$P/existing-meta.yaml" <<'EOF'
title: Existing
author: Probe Author
papis_id: existing0001
EOF
cat > "$P/probe-meta.yaml" <<'EOF'
title: Probe
author: Probe Author
year: 2026
papis_id: probe0001
EOF
cat > "$P/xdg/papis/config" <<EOF
[settings]
time-stamp = False
use-cache = False
default-library = probe

[probe]
dir = $P/lib
EOF
export XDG_CONFIG_HOME="$P/xdg" XDG_CACHE_HOME="$P/cache" HOME="$P/home"
export PAPIS_NP=0
papis add --batch --from yaml "$P/existing-meta.yaml" \
    --folder-name existing-doc "$P/existing.txt"
