#!/bin/sh
# Campaign-2 Seal B artifact (ADR 0012 via ADR 0015): the declared setup for
# each abook operation. Pre-states are cp'd from the sealed goldens — stores
# abook itself wrote at fixture-generation time (make-goldens.sh; byte-
# deterministic per normal-runs §2), so setup runs no target binary and every
# NATIVE STORE the operation reads is abook-written by construction. The
# vCard INPUTS import/refused name in their argv are the committed
# hand-authored well-formed files (ada.vcf, next.vcf) — the documented-normal
# input class the normal runs recorded, not stores.
#
# Grace is the conserved bystander in every operation. Ada is import's
# subject and, with Grace, the content of the export/refused source store.
#
# Usage: setup.sh <import|export|refused>
set -eu

op=${1:?usage: setup.sh <import|export|refused>}
here=$(cd "$(dirname "$0")" && pwd)
S=/tmp/blind2/hunt/$op/state

case $op in
    import)
        mkdir -p "$S/keep" "$S/book"
        cp "$here/golden-grace.addressbook" "$S/keep/addressbook" ;;
    export)
        mkdir -p "$S/book"
        cp "$here/golden-pair.addressbook" "$S/book/addressbook" ;;
    refused)
        mkdir -p "$S/book"
        cp "$here/golden-pair.addressbook" "$S/book/addressbook" ;;
    *) echo "setup: unknown operation '$op'" >&2; exit 1 ;;
esac
