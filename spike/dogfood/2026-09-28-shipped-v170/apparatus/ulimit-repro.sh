#!/bin/sh
# No-crash reproductions for the drafted upstream reports (2026-09-28, after the owner's review of
# the not-filed rulings): a write that fails after the truncating open. Runs inside the
# sideeye-sv170 box, --network none, each from its define's seed. Every command is echoed before
# it runs, so the transcript is the session a report quotes.
run() { echo "\$ $*"; sh -c "$*" 2>&1; }
t=${1:?usage: ulimit-repro.sh nbqa|nbqa-large|terraform}
case $t in
nbqa)
    sh /ap/defines/nbqa/seed.sh; cd /s/nbqa/proj || exit 2
    run 'wc -c < nb.ipynb'
    run '( ulimit -f 0; nbqa black nb.ipynb ); echo "exit $?"'
    run 'wc -c < nb.ipynb'
    run 'ls -A' ;;
nbqa-large)
    # The same cell, with 4 KB of notebook metadata so the notebook is larger than one ulimit -f
    # block while the .py copy nbqa writes first stays under it: the .py write succeeds and the
    # notebook's does not. (With ulimit -f 0 the .py write fails first and the notebook is untouched.)
    sh /ap/defines/nbqa/seed.sh; cd /s/nbqa/proj || exit 2
    python3 -c 'import json;p="nb.ipynb";d=json.load(open(p));d["metadata"]["note"]="x"*4000;open(p,"w").write(json.dumps(d))'
    run 'wc -c < nb.ipynb'
    run '( ulimit -f 1; nbqa black nb.ipynb ); echo "exit $?"'
    run 'wc -c < nb.ipynb'
    run 'python3 -c "import json; json.load(open(\"nb.ipynb\"))" && echo "still valid JSON"'
    run 'ls -A' ;;
terraform)
    sh /ap/defines/terraform/seed.sh; cd /s/terraform/proj || exit 2
    run 'wc -c < main.tf'
    run '( ulimit -f 0; terraform fmt ); echo "exit $?"'
    run 'wc -c < main.tf'
    run 'ls -A' ;;
esac
