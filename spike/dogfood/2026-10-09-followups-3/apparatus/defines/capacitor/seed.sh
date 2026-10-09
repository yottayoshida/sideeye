set -eu
. /ap/defines/capacitor/env.sh
rm -rf /s/aux/home/.config/capacitor /s/cap-in && mkdir -p /s/cap-in
cap telemetry on > /s/cap-in/seed.log 2>&1
test -s /s/aux/home/.config/capacitor/sysconfig.json
