set -u
# sh /b/gate.sh <define> <runs> [extra flags...]: preflight --twice under main's build and this change's, the reason per run.
name=$1 n=$2; shift 2
d=/ap/defines/$name
[ -f /ap/env.sh ] && . /ap/env.sh
[ -f "$d/env.sh" ] && . "$d/env.sh"
for v in ${VERS:-base mine}; do
  i=1
  while [ "$i" -le "$n" ]; do
    sh "$d/seed.sh" > /tmp/seed.log 2>&1 || { echo "seed failed"; tail -3 /tmp/seed.log; exit 1; }
    rm -rf /tmp/w
    /b/$v-out/bin/sideeye ${CMD:-preflight} --config "$d/sideeye.toml" ${TWICE---twice} --oracle /usr/bin/strace --shim /b/$v-out/lib/libsideeye_shim.so --work /tmp/w "$@" > /tmp/o.txt 2>&1
    rc=$?
    r=$(sed -n 's/^\(UNKNOWN\|SETUP ERROR\)  *//p' /tmp/o.txt | head -1)
    [ -z "$r" ] && r=$(grep -m1 -E '^(recording accepted|PASS|FAIL)' /tmp/o.txt)
    echo "$v run$i rc=$rc ${r:-?}"
    [ "$i" = 1 ] && sed -n '/^UNKNOWN/{n;s/^  *//;p;q;}' /tmp/o.txt | cut -c1-220
    i=$((i + 1))
  done
done
