set -eu
rm -rf /s/jd /s/jd-in && mkdir -p /s/jd /s/jd-in
JULIAUP_DEPOT_PATH=/s/jd juliaup config versionsdbupdateinterval 1440 > /s/jd-in/seed.log 2>&1
test -s /s/jd/juliaup/juliaup.json
