set -eu
. /ap/defines/rustic/env.sh
rm -rf /s/rustic /s/rustic-in && mkdir -p /s/rustic /s/rustic-in/data
echo first-version-of-a > /s/rustic-in/data/a
rustic init > /s/rustic-in/seed.log 2>&1
rustic backup /s/rustic-in/data >> /s/rustic-in/seed.log 2>&1
echo second-version-of-a > /s/rustic-in/data/a
rustic backup /s/rustic-in/data >> /s/rustic-in/seed.log 2>&1
test "$(ls /s/rustic/repo/snapshots | wc -l)" = 2
