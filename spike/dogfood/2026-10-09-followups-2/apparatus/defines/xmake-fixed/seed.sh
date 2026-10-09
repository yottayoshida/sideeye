set -eu
rm -rf /s/xm /s/xm-in && mkdir -p /s/xm /s/xm-in
XMAKE_ROOT=y XMAKE_GLOBALDIR=/s/xm xmake g --network=private > /s/xm-in/seed.log 2>&1
test -s /s/xm/.xmake/xmake.conf
