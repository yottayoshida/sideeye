set -eu
. /ap/defines/pi/env.sh
rm -rf /s/aux/home/.pi /s/pi-in && mkdir -p /s/pi-in/ext1 /s/pi-in/ext2
for n in ext1 ext2; do printf '{"name":"%s","version":"1.0.0","main":"index.js"}\n' $n > /s/pi-in/$n/package.json; echo 'module.exports={}' > /s/pi-in/$n/index.js; done
pi install /s/pi-in/ext1 > /s/pi-in/seed.log 2>&1
grep -q ext1 /s/aux/home/.pi/agent/settings.json
