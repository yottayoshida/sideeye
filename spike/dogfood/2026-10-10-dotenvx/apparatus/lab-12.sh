#!/bin/sh
# G1 follow-up: .env.keys as a symlink into secrets/, with its target present and with it not yet
# made (dangling), through a first encrypt and through set. Both versions.
export HOME=/s/lab12/home UV_THREADPOOL_SIZE=1 npm_config_update_notifier=false; mkdir -p $HOME
for v in 2.32.4 2.34.2; do export PATH=/opt/dx-$v/bin:/usr/local/bin:/usr/bin:/bin
  for t in present dangling; do
    d=/s/lab12/$v-$t; mkdir -p $d/secrets; cd $d; printf 'DB_PASSWORD=hunter2\n' > .env
    [ $t = present ] && printf '# my keys\n' > secrets/.env.keys
    ln -s secrets/.env.keys .env.keys
    dotenvx encrypt -f .env > /dev/null 2>&1; dotenvx set NEW x -f .env > /dev/null 2>&1
    echo "## $v, target $t: .env.keys is $(stat -c %F .env.keys); secrets/: $(ls -A secrets | tr '\n' ' '); get: $(dotenvx get DB_PASSWORD -f .env 2>&1 | cut -c1-30)"
  done
done
