#!/bin/sh
# Campaign-3 Seal B artifact (ADR 0012 via ADR 0015/0016): the declared setup
# for each khal operation. Pre-states are cp'd from the sealed golden EVENT
# files — khal's own serialization, minted by make-goldens.sh — so setup runs
# no target binary and every event file the operation meets is khal-written
# by construction. Grace is the conserved bystander in every operation; Ada
# is import's subject and, pre-placed, import-update's overwrite target.
#
# Usage: setup.sh <import|update|new>
set -eu

op=${1:?usage: setup.sh <import|update|new>}
here=$(cd "$(dirname "$0")" && pwd)
S=/tmp/blind3/hunt/$op/state
mkdir -p "$S/cal"

cp "$here/golden-grace-event.ics" "$S/cal/grace-fixed-uid-001.ics"
case $op in
    import) : ;;
    update) cp "$here/golden-ada-event.ics" "$S/cal/ada-fixed-uid-001.ics" ;;
    new)    : ;;
    *) echo "setup: unknown operation '$op'" >&2; exit 1 ;;
esac
