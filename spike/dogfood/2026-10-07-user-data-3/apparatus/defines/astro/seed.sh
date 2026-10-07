set -eu
. /ap/defines/astro/env.sh
rm -rf /s/aux/home/.config/astro /s/astro-in && mkdir -p /s/astro-in
astro preferences enable devToolbar --global > /s/astro-in/seed.log 2>&1
test -s /s/aux/home/.config/astro/settings.json
