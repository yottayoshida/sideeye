#!/bin/sh
# The no-crash reproduction for kubectl's report (2026-09-28): a write that fails after the
# truncating open. Run inside the sideeye-sv170 box, --network none, from the define's seed.
# Every command is echoed before it runs, so the transcript is the session the report quotes.
sh /ap/defines/kubectl/seed.sh
cd /s/kubectl || exit 2
run() { echo "\$ $*"; sh -c "$*" 2>&1; }
run 'wc -c < config'
run '( ulimit -f 0; kubectl config use-context b --kubeconfig ./config ); echo "exit $?"'
run 'wc -c < config'
run 'ls -A'
