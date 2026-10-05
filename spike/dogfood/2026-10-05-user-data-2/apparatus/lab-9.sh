#!/bin/sh
# Plain runs: python-dotenv's `set`, gita's registry, Home Assistant's auth script.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 180 "$@" </dev/null 2>&1 | tail -${TAILN:-10}; echo "rc=$?"; }
sum() { find "$1" -type f -exec sha256sum {} \; 2>/dev/null | cut -c1-12,65- | sort -k2; }
mkdir -p /lab/env /lab/repos/a/.git /lab/repos/b/.git /lab/ha
printf '# production secrets\nDATABASE_URL=postgres://app:pw@db/app\nSTRIPE_KEY=sk_live_aaaa\nDEBUG=false\n' > /lab/env/.env
x dotenv -f /lab/env/.env set DEBUG true
sum /lab/env; cat /lab/env/.env; ls -la /lab/env
export XDG_CONFIG_HOME=/lab/gita-cfg
x gita add /lab/repos/a
x gita add /lab/repos/b
sum /lab/gita-cfg; cat /lab/gita-cfg/gita/repos.csv
x gita group add a b -n work
sum /lab/gita-cfg; cat /lab/gita-cfg/gita/groups.csv 2>/dev/null
x gita rename a alpha
sum /lab/gita-cfg; cat /lab/gita-cfg/gita/repos.csv
unset XDG_CONFIG_HOME
TAILN=20 x hass --script auth --help
x hass --script auth -c /lab/ha add alice pw-one
sum /lab/ha
x hass --script auth -c /lab/ha add bob pw-two
x hass --script auth -c /lab/ha change_password alice pw-three
sum /lab/ha
