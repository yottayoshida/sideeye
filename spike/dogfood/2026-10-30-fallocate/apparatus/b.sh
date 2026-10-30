set -u
mkdir -p /t/spike && cp -r /b/toysB/toys /b/toysB/build-toys.sh /t/spike/
SIDEEYE_ROOT=/t sh /t/spike/build-toys.sh /t/out > /t/toys.log 2>&1; [ -x /t/out/toy-fixed ] || { tail -5 /t/toys.log; exit 1; }
for v in base mineB; do
  for fa in 0 keep punch; do
    for obs in wrappers syscalls supervised; do
      rm -rf /tmp/acc && mkdir -p /tmp/acc/state
      o=$(TOY_FALLOCATE=$fa /b/$v-out/bin/sideeye explore --state /tmp/acc/state --setup "/t/out/toy-fixed init" --operation "/t/out/toy-fixed rotate" --shim /b/$v-out/lib/libsideeye_shim.so --observe $obs --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
      rc=$?
      echo "$v fallocate=$fa $obs rc=$rc $(printf '%s\n' "$o" | sed -n 's/^\(UNKNOWN\|PASS\|FAIL\|SETUP ERROR\)  *//p' | head -1 | cut -c1-70) | $(printf '%s\n' "$o" | sed -n '/^UNKNOWN/{n;s/^  *//;p;q;}' | cut -c1-120)"
    done
  done
done
