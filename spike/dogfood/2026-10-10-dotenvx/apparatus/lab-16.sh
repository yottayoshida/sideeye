#!/bin/sh
# E3 as SELECTION.md wrote it (the first lab-8 measured a different case under the same name): a
# writer running while readers read. Four readers loop `get` and `run -- printenv` on the same .env
# while one writer runs once: the first `encrypt` of a plaintext file, `set` on an encrypted one,
# `decrypt`. Every read is one line: the reader, its exit status, what it printed. A read is torn
# when it is neither the value before nor the value after. No crash, no Sideeye.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-dx1010 sh /ap/lab-16.sh
echo "# dotenvx readers: get and run while encrypt, set or decrypt writes (SELECTION.md E3)"
export UV_THREADPOOL_SIZE=1 npm_config_update_notifier=false
ROUNDS=${ROUNDS:-15}
reader() { # <dir> <id> <out>
  while [ ! -e "$1/stop" ]; do
    g=$(cd "$1" && dotenvx get DB_PASSWORD -f .env 2>/dev/null); echo "get $? $g" >> "$3"
    r=$(cd "$1" && dotenvx run -q -f .env -- printenv DB_PASSWORD 2>/dev/null); echo "run $? $r" >> "$3"
  done
}
for v in 2.32.4 2.34.2; do
  export PATH=/opt/dx-$v/bin:/usr/local/bin:/usr/bin:/bin
  for w in encrypt set decrypt; do
    torn=0; reads=0; i=0; first=""
    while [ $i -lt $ROUNDS ]; do i=$((i+1))
      d=/s/lab16/$v-$w-$i; mkdir -p $d; export HOME=$d.home; mkdir -p $HOME; cd $d
      printf 'DB_PASSWORD=old-value\n' > .env
      [ $w != encrypt ] && dotenvx encrypt -f .env > /dev/null 2>&1
      for r in 1 2 3 4; do reader $d $r $d.reads & done
      sleep 1
      case $w in encrypt) dotenvx encrypt -f .env > /dev/null 2>&1;; set) dotenvx set DB_PASSWORD new-value -f .env > /dev/null 2>&1;; decrypt) dotenvx decrypt -f .env > /dev/null 2>&1;; esac
      sleep 1; : > $d/stop; wait
      n=$(wc -l < $d.reads); reads=$((reads+n))
      bad=$(grep -v -E '^(get|run) 0 (old-value|new-value)$' $d.reads | wc -l); torn=$((torn+bad))
      [ $bad -gt 0 ] && [ -z "$first" ] && first="round $i: $(grep -v -E '^(get|run) 0 (old-value|new-value)$' $d.reads | sort | uniq -c | head -3 | cut -c1-90 | tr '\n' ';')"
    done
    echo "## $v $w: $torn torn of $reads reads over $ROUNDS rounds${first:+ — first: $first}"
  done
done
