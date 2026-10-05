#!/bin/sh
# Plain runs: conan's remotes, platformio's settings.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 120 "$@" </dev/null 2>&1 | tail -${TAILN:-12}; echo "rc=$?"; }
sum() { find "$1" -type f -exec sha256sum {} \; 2>/dev/null | cut -c1-12,65- | sort -k2; }
export CONAN_HOME=/lab/conan
x conan remote list
sum /lab/conan
x conan remote add internal https://artifacts.example.internal/conan
x conan remote disable conancenter
sum /lab/conan; cat /lab/conan/remotes.json
x conan remote set-user internal alice
sum /lab/conan; cat /lab/conan/credentials.json 2>/dev/null
unset CONAN_HOME
export PLATFORMIO_CORE_DIR=/lab/pio
x pio settings get
x pio settings set enable_telemetry No
sum /lab/pio; cat /lab/pio/appstate.json; echo
x pio settings set check_platformio_interval 30
sum /lab/pio; cat /lab/pio/appstate.json
