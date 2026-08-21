#!/bin/sh
# Cohort-2 borg define (P1) setup: repo with one committed archive `base`,
# then a modified source file so the operation archives new content.
# Runs under the launcher's frozen clock/entropy (FAKETIME + PYTHONPATH
# reach this script from the engine's environment), so the pre-state is
# byte-reproducible. The sitecustomize is GENERATED here for the hg-r3
# reason: bytes that decide the question live inside D2-held files.
set -eu
B=/tmp/cohort2/borg
rm -rf "$B/state" "$B/src"
mkdir -p "$B/state/ambient" "$B/src" "$B/pylib"
export BORG_BASE_DIR="$B/state/ambient"
cat > "$B/pylib/sitecustomize.py" <<'EOF'
import time, os, shutil
time.monotonic = lambda: 0.0
os.urandom = lambda n: b"\x5a" * n
# CPython's shutil fast-copies through sendfile, outside the engine's
# frozen contract (the hg-r3 lesson; borg's r2 explore refused on it).
shutil._USE_CP_SENDFILE = False
EOF
printf 'alpha file, fixed bytes\n' > "$B/src/alpha"
printf 'beta file, fixed bytes\n'  > "$B/src/beta"
printf 'gamma file, fixed bytes\n' > "$B/src/gamma"
touch -t 202601010000 "$B/src/alpha" "$B/src/beta" "$B/src/gamma" "$B/src"
borg init --encryption=none "$B/state/repo"
borg create --timestamp 2026-01-01T00:00:00 "$B/state/repo::base" "$B/src"
printf 'alpha, modified fixed bytes\n' > "$B/src/alpha"
touch -t 202601020000 "$B/src/alpha"
