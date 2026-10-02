#!/bin/sh
# The window the shrink define found, entered without Sideeye: strace delivers SIGKILL as the
# process enters ftruncate, i.e. after the formatted bytes are written and before the file is cut
# to their length. Every command is echoed.
run() { echo "\$ $*"; sh -c "$*" 2>&1; }
terraform version | head -1
sh /ap/defines/terraform-shrink/seed.sh; cd /s/terraform/proj
run 'wc -c main.tf; cat main.tf'
run 'strace -f -o /dev/null -e trace=ftruncate -e inject=ftruncate:signal=KILL terraform fmt; echo "exit $?"'
run 'ls -lA'
run 'cat main.tf'
run 'terraform fmt -write=false -list=false main.tf > /dev/null; echo "parse exit $?"'
run 'for f in main.tf?*; do [ -e "$f" ] && { wc -c "$f"; cat "$f"; }; done'
exit 0
