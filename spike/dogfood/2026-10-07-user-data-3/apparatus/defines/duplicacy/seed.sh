set -eu
rm -rf /s/dup && mkdir -p /s/dup/repo /s/dup/storage && cd /s/dup/repo && echo x > f
duplicacy init snap1 /s/dup/storage > /s/dup/seed.log 2>&1
duplicacy backup >> /s/dup/seed.log 2>&1
test -s /s/dup/repo/.duplicacy/preferences
