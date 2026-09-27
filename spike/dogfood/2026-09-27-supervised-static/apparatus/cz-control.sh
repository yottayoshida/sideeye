#!/bin/sh
# The control behind the chezmoi correction: two plain `chezmoi apply` runs, no engine and no
# shim, the destination emptied between them as `preflight --twice` restores it — then the same
# with chezmoi's own database removed too.
export HOME=/tmp/cz/home; mkdir -p /tmp/cz/src "$HOME" /tmp/cz/dest
printf 'hello from chezmoi\n' > /tmp/cz/src/dot_testrc; printf 'second file\n' > /tmp/cz/src/dot_second
C="/usr/local/bin/chezmoi apply --source /tmp/cz/src --destination /tmp/cz/dest --no-tty"
$C; echo "run 1: exit $?"
rm -rf /tmp/cz/dest; mkdir /tmp/cz/dest; $C < /dev/null; echo "run 2 (destination emptied, database kept): exit $?"
rm -rf /tmp/cz/dest "$HOME/.config/chezmoi"; mkdir /tmp/cz/dest; $C < /dev/null; echo "run 3 (destination emptied, database removed): exit $?"
