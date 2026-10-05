#!/bin/sh
# Does aliyun-cli start other programs? A static parent with a dynamic child would leave the shim's
# marker (written by the child) while the parent's writes go unseen: oracle_missed_operation rather
# than no_shim_marker. The operation once under strace, execve and clone only.
. /ap/env.sh
sh /ap/defines/aliyun/seed.sh > /dev/null 2>&1
cd /s/aliyun-in && strace -f -qq -e signal=none -e trace=execve,clone,clone3,vfork -o /tmp/st aliyun configure delete --profile home < /dev/null > /dev/null 2>&1
grep -c clone /tmp/st | sed 's/^/clone lines: /'
grep execve /tmp/st | cut -c1-200
