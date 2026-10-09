set -eu
# A fake KSP 1.12.5 instance made by CKAN itself (`instance fake`, no download); `compat add 1.7`
# rewrites the game's CKAN/compatible_ksp_versions.json (lab 18: O_RDWR|O_CREAT|O_TRUNC). The fake instance starts with 1.8 to 1.12 compatible, so the operation adds 1.7, which is not.
rm -rf /s/ksp /s/ckan-in /s/aux/data/CKAN /s/aux/home/.mono && mkdir -p /s/ksp /s/ckan-in
ckan instance fake box /s/ksp/game 1.12.5 --set-default --headless > /s/ckan-seed.log 2>&1
# The JSON is written by the first `compat` command, not by `instance fake`.
ckan compat add 1.10 --headless >> /s/ckan-seed.log 2>&1
grep -q '"1.8"' /s/ksp/game/CKAN/compatible_ksp_versions.json
