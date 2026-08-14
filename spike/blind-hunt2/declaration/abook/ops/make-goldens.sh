#!/bin/sh
# Campaign-2 Seal B artifact (abook): regenerates the committed golden stores
# from the committed .vcf inputs, via abook itself inside the pinned container
# — so "the bytes abook writes" (byte-deterministic, normal-runs §2) are the
# fixture, not a hand-imitation of them. Run when fixtures change; the red
# suite and checker compare against the COMMITTED goldens, so a drift between
# this script's output and the committed bytes is a red suite failure, not a
# silent re-baseline.
#
# Usage (inside the pinned container, repo mounted at /work):
#   sh /work/spike/blind-hunt2/declaration/abook/ops/make-goldens.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT

gen() { # gen <in.vcf> <out-name>
    rm -f "$t/g"
    abook --convert --informat vcard --infile "$here/$1" --outformat abook --outfile "$t/g" < /dev/null
    cp "$t/g" "$here/$2"
    printf '%s <- %s\n' "$2" "$1"
}
gen grace.vcf    golden-grace.addressbook
gen pair.vcf     golden-pair.addressbook
gen impostor.vcf golden-impostor.addressbook
sha256sum "$here"/golden-*.addressbook
