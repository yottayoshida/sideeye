set -u
mkdir -p /t/spike && cp -r /b/toys/toys /b/toys/build-toys.sh /t/spike/
SIDEEYE_ROOT=/t sh /t/spike/build-toys.sh /t/out > /t/toys.log 2>&1; [ -x /t/out/toy-bug ] || { tail -5 /t/toys.log; exit 1; }
for v in base mine; do
  for case in ${CASES:-TOY_THREAD_ROOT_MKDIR TOY_THREAD_SIBLINGS}; do
    rm -rf /tmp/acc && mkdir -p /tmp/acc/state
    o=$(env $case=1 /b/$v-out/bin/sideeye explore --state /tmp/acc/state --setup "/t/out/toy-bug init" --operation "/t/out/toy-bug rotate" --shim /b/$v-out/lib/libsideeye_shim.so --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
    echo "== $v $case rc=$?"; printf '%s\n' "$o" | grep -E '^(UNKNOWN|FAIL|PASS|earliest|next) ' | cut -c1-160
  done
done
