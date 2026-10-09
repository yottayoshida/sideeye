set -eu
rm -rf /s/bat && mkdir -p /s/bat/state /s/bat/aux/batsrc
mkdir -p "/s/bat/state" /s/bat/aux/batsrc
batcat cache --build --source /s/bat/aux/batsrc --target "/s/bat/state" >/dev/null 2>&1
