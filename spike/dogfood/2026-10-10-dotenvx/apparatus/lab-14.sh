#!/bin/sh
# The reproduction blocks of report-concurrent.md and report-escape.md, verbatim, each in a fresh
# HOME and directory, on both versions; the concurrent one five times over.
export npm_config_update_notifier=false
for v in 2.34.2 2.32.4; do export PATH=/opt/dx-$v/bin:/usr/local/bin:/usr/bin:/bin
  for i in 1 2 3 4 5; do export HOME=/s/lab14/home-$v-c$i; mkdir -p $HOME /s/lab14/$v-c$i; cd /s/lab14/$v-c$i
    echo "## $v report-concurrent, run $i"; sh /ap/verbatim-report-concurrent.sh 2>&1 | grep -v '^⚠\|^◈' | cut -c1-110 | sed 's/^/   /'
    echo "   .env.keys private keys: $(grep -c '^DOTENV_PRIVATE_KEY=' demo/.env.keys)"; done
  export HOME=/s/lab14/home-$v-e; mkdir -p $HOME /s/lab14/$v-e; cd /s/lab14/$v-e
  echo "## $v report-escape"; sh /ap/verbatim-report-escape.sh 2>&1 | sed 's/^/   /'
done
