set -eu
. /ap/defines/cspell/env.sh
rm -rf /s/aux/home/.config/cspell /s/cspell-in && mkdir -p /s/cspell-in
printf '{"version":"0.2","words":["sideeye","explore"]}\n' > /s/cspell-in/a.json
printf '{"version":"0.2","words":["dogfood","replay"]}\n' > /s/cspell-in/b.json
cspell link add /s/cspell-in/a.json > /s/cspell-in/seed.log 2>&1
grep -rq a.json /s/aux/home/.config/cspell
