#!/bin/sh
# After the kill of plain-repro-s3.sh's Vagrant case: does using the live machine's own project put it
# back in the machine index?
set -u
. /ap/env.sh
V="ruby /opt/vagrant-gems/bin/vagrant"; idx=/s/vagrant.d/data/machine-index/index
sh /ap/defines/vagrant-live/seed.sh > /dev/null 2>&1; . /ap/defines/vagrant-live/env.sh
strace -f -qq -P $idx -e trace=write -e inject=write:signal=KILL $V global-status --prune > /dev/null 2>&1
echo "after the kill: $(wc -c < $idx) bytes"
cd /s/vagrantaux/payments && $V status > /tmp/st.out 2>&1; echo "vagrant status in the project: exit $?"; grep -E "web|not created|running" /tmp/st.out | head -3
echo "index now: $(wc -c < $idx) bytes"; python3 -c "import json;d=json.load(open('$idx'));print({k:v['name'] for k,v in d['machines'].items()})" 2>&1
cat /s/vagrantaux/payments/.vagrant/machines/web/virtualbox/index_uuid 2>/dev/null; echo " <- index_uuid in the project"
$V global-status 2>&1 | grep -E "^[0-9a-f]{7}|no active" | head -3
