#!/bin/sh
# The reproduction blocks of report-protect.md and report-leftover.md, extracted verbatim
# (verbatim-*.sh), each run in a fresh HOME and directory with 2.34.2 first on PATH. A git identity
# is set first, as any machine that commits has one.
export PATH=/opt/dx-2.34.2/bin:/usr/local/bin:/usr/bin:/bin npm_config_update_notifier=false
for f in report-protect report-leftover; do
  export HOME=/s/lab7/home-$f; mkdir -p $HOME /s/lab7/$f; cd /s/lab7/$f
  git config --global user.email lab@example.invalid; git config --global user.name lab
  echo "## $f"; sh -x /ap/verbatim-$f.sh 2>&1 | sed 's/^/   /'
done
cd /s/lab7/report-leftover/demo; k=$(ls -A | grep '^\.env\.keys\.'); echo "## then: dotenvx get DB_PASSWORD -f .env -fk $k -> $(dotenvx get DB_PASSWORD -f .env -fk $k 2>&1)"
