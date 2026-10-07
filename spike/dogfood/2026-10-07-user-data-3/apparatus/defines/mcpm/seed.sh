set -eu
rm -rf /s/aux/home/.config/mcpm /s/mcpm-in && mkdir -p /s/mcpm-in
mcpm new srv --type stdio --command echo --force > /s/mcpm-in/seed.log 2>&1
mcpm new other --type stdio --command true --force >> /s/mcpm-in/seed.log 2>&1
grep -q other /s/aux/home/.config/mcpm/servers.json
