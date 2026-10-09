#!/bin/sh
# F1 follow-up: a password with a `$` in it, written the ways a .env lets you keep the `$` literal,
# through encrypt and then decrypt. What `get` and `run` read at each step, and the line decrypt writes.
export HOME=/s/lab10/home UV_THREADPOOL_SIZE=1 npm_config_update_notifier=false; mkdir -p $HOME
echo '# dotenvx decrypt: a literal $ kept by a backslash, through encrypt and decrypt (filed as dotenvx/dotenvx#1016)'
for v in 2.32.4 2.34.2; do
  export PATH=/opt/dx-$v/bin:/usr/local/bin:/usr/bin:/bin
  d=/s/lab10/$v; mkdir -p $d; cd $d
  printf '%s\n' 'PW_BACKSLASH=pa\$sword' 'PW_DQ_BACKSLASH="pa\$sword"' "PW_SQ='pa\$sword'" > .env
  echo "## $v"; echo "   file before:"; sed 's/^/     /' .env
  rd() { for k in PW_BACKSLASH PW_DQ_BACKSLASH PW_SQ; do printf '     %-16s get=%-12s run=%s\n' $k "$(dotenvx get $k -f .env 2>/dev/null)" "$(dotenvx run -q -f .env -- printenv $k 2>/dev/null)"; done; }
  echo "   read before:"; rd
  dotenvx encrypt -f .env > /dev/null 2>&1; echo "   read after encrypt:"; rd
  dotenvx decrypt -f .env > /dev/null 2>&1; echo "   file after decrypt:"; grep '^PW' .env | sed 's/^/     /'
  echo "   read after decrypt:"; rd
  dotenvx encrypt -f .env > /dev/null 2>&1; echo "   read after encrypting again:"; rd
done
