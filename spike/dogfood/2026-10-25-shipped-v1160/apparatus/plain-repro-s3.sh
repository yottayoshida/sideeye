#!/bin/sh
# Reproduce the Vagrant and Salt windows without Sideeye, for the upstream drafts: strace stops the
# process with SIGKILL at its first write to the one file (-P), then the tool's own read is shown.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-sv1025-s3 sh /ap/plain-repro-s3.sh
set -u
. /ap/env.sh
echo "### vagrant 2.4.9: global-status --prune over five stale entries and one live machine (vagrant-live's seed), killed at its first write to the machine index"
V="ruby /opt/vagrant-gems/bin/vagrant"
seedv() { sh /ap/defines/vagrant-live/seed.sh > /dev/null 2>&1; . /ap/defines/vagrant-live/env.sh; }
count() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(len(d['machines']), sorted(m['name'] for m in d['machines'].values()))" "$1"; }
idx=/s/vagrant.d/data/machine-index/index
seedv; echo "before: $(wc -c < $idx) bytes, machines: $(count $idx)"
strace -f -qq -P $idx -e trace=openat,write -e inject=write:signal=KILL $V global-status --prune > /tmp/v.out 2>/tmp/v.strace; echo "exit: $?"
grep -E 'openat|write\(|killed' /tmp/v.strace | tail -3
echo "after the kill: $(wc -c < $idx) bytes"
echo "-- vagrant global-status (next run, exit and the lines after the installer warning):"; $V global-status > /tmp/v2.out 2>&1; echo "exit: $?"; grep -v -E '^(You appear|Note that|dependencies|currently|  - |$|Vagrant has)' /tmp/v2.out | head -6
echo "-- the index the next run left: $(wc -c < $idx) bytes"
seedv; $V global-status --prune > /dev/null 2>&1
echo "run through instead: $(wc -c < $idx) bytes, machines: $(count $idx)"
echo; echo "### salt 3008.4: salt-call --local grains.setval, killed at its first write to grains"
sh /ap/defines/salt-grains/seed.sh > /dev/null 2>&1
g=/s/salt/grains
echo "before: $(wc -c < $g) bytes, $(grep -c '^[a-z_]*:' $g) grains"
strace -f -qq -P $g -e trace=openat,write -e inject=write:signal=KILL /opt/salt/salt/bin/python3.14 /opt/salt/salt/salt-call -c /s/salt --local grains.setval maintainer ops-oncall > /tmp/s.out 2>/tmp/s.strace; echo "exit: $?"
grep -E 'openat|write|killed' /tmp/s.strace | tail -3
echo "after the kill: $(wc -c < $g) bytes"
echo "-- salt-call --local grains.item datacenter roles (next run):"; /opt/salt/salt/salt-call -c /s/salt --local grains.item datacenter roles 2>&1 | head -6
/opt/salt/salt/salt-call -c /s/salt --local grains.setval maintainer ops-oncall > /dev/null 2>&1
echo "the next setval leaves: $(wc -c < $g) bytes:"; cat $g
sh /ap/defines/salt-grains/seed.sh > /dev/null 2>&1
/opt/salt/salt/salt-call -c /s/salt --local grains.setval maintainer ops-oncall > /dev/null 2>&1
echo "run through instead: $(wc -c < $g) bytes, $(grep -c '^[a-z_]*:' $g) grains"
