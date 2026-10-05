#!/bin/sh
# Plain runs: limactl edit --set on a stopped instance, tenv's constraint.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 120 "$@" </dev/null 2>&1 | tail -${TAILN:-12}; echo "rc=$?"; }
sum() { find "$1" -type f -exec sha256sum {} \; 2>/dev/null | cut -c1-12,65- | sort -k2; }
export LIMA_HOME=/lab/lima
x limactl create --name=dev --tty=false --cpus=2 --memory=2 template:default
sum /lab/lima | head
x limactl list
x limactl edit --tty=false --set .cpus=4 dev
sum /lab/lima | head; grep -n -E '^(cpus|memory):' /lab/lima/dev/lima.yaml
unset LIMA_HOME
export TENV_ROOT=/lab/tenv
TAILN=25 x tenv tf constraint --help
x tenv tf constraint '>=1.5.0'
sum /lab/tenv; find /lab/tenv -type f -exec sh -c 'echo "== {}"; cat {}' \;
x tenv tf constraint '~>1.6'
sum /lab/tenv
