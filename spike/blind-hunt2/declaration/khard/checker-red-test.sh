#!/bin/sh
# Campaign-2 Seal B artifact: red-side sanity of the declared checker WITHOUT
# observing any khard failure. Every state below is hand-fabricated by THIS
# script (printf of well-formed or deliberately mis-shaped vCard text), not
# produced by khard crashing; khard itself only ever runs `list` over these
# stores, and an empty store making `list` exit 1 is documented-normal behavior
# (observed in normal runs, not a crash). The checker's red side against real
# crash states belongs to sideeye's falsification gate, after Seal B.
#
# Usage (inside the pinned container, repo mounted at /work):
#   sh /work/spike/blind-hunt2/declaration/khard/checker-red-test.sh
set -u
export HOME=/tmp/blind2/home; mkdir -p "$HOME"
here=/work/spike/blind-hunt2/declaration/khard/ops
fails=0
n=0
expect() {  # expect <want-rc> <op> <name>
    want=$1; op=$2; name=$3
    ( cd "$here" && sh ./check.sh "$op" ) >/tmp/red.out 2>&1
    rc=$?
    n=$((n + 1))
    if [ "$rc" = "$want" ]; then
        echo "ok   $name (rc=$rc) — $(tail -1 /tmp/red.out | cut -c1-90)"
    else
        echo "FAIL $name (rc=$rc, wanted $want)"; head -3 /tmp/red.out | sed 's/^/     | /'
        fails=$((fails + 1))
    fi
}
vcard() {  # vcard <path> <name>  — one well-formed vCard
    printf 'BEGIN:VCARD\nVERSION:3.0\nUID:%s\nFN:%s\nN:%s;;;;\nEND:VCARD\n' \
        "$(basename "$1" .vcf)" "$2" "$2" > "$1"
}
reset() {  # reset <op>
    rm -rf "/tmp/blind2/hunt/$1"
    mkdir -p "/tmp/blind2/hunt/$1/state/main" "/tmp/blind2/hunt/$1/state/second"
}

S=/tmp/blind2/hunt/move/state

echo "== I-C / I-Q =="
reset move   # bystander lost: store holds only Ada
vcard "$S/main/aaa.vcf" "Ada Lovelace"
expect 1 move "red: conserved bystander in neither book"

reset move   # bystander duplicated across books
vcard "$S/main/g1.vcf" "Grace Hopper"; vcard "$S/second/g2.vcf" "Grace Hopper"; vcard "$S/main/aaa.vcf" "Ada Lovelace"
expect 1 move "red: conserved bystander duplicated"

reset move   # empty store: the liveness query itself must refuse (list exits 1)
expect 1 move "red: empty store fails the liveness query"

echo "== the move window =="
reset move   # subject in neither book — lost
vcard "$S/main/g1.vcf" "Grace Hopper"
expect 1 move "red: moved subject in neither addressbook"

reset move   # subject in both books — duplicated
vcard "$S/main/g1.vcf" "Grace Hopper"; vcard "$S/main/a1.vcf" "Ada Lovelace"; vcard "$S/second/a2.vcf" "Ada Lovelace"
expect 1 move "red: moved subject in both addressbooks"

reset move   # green control: subject landed, bystander intact
vcard "$S/main/g1.vcf" "Grace Hopper"; vcard "$S/second/a1.vcf" "Ada Lovelace"
expect 0 move "green: post-move shape passes"

echo "== copy =="
C=/tmp/blind2/hunt/copy/state
reset copy   # source gone from main
vcard "$C/main/g1.vcf" "Grace Hopper"; vcard "$C/second/a1.vcf" "Ada Lovelace"
expect 1 copy "red: copy source missing from main"

reset copy   # green control: copy not yet landed
vcard "$C/main/g1.vcf" "Grace Hopper"; vcard "$C/main/a1.vcf" "Ada Lovelace"
expect 0 copy "green: pre-copy shape passes"

echo "== I-F (normative shape) =="
reset move
vcard "$S/main/g1.vcf" "Grace Hopper"; vcard "$S/second/a1.vcf" "Ada Lovelace"
printf 'VERSION:3.0\nFN:Junk\nEND:VCARD\n' > "$S/main/bad.vcf"
expect 1 move "red: a .vcf not starting with BEGIN:VCARD"

reset move
vcard "$S/main/g1.vcf" "Grace Hopper"; vcard "$S/second/a1.vcf" "Ada Lovelace"
printf 'BEGIN:VCARD\nVERSION:3.0\nFN:Two\nEND:VCARD\nBEGIN:VCARD\nVERSION:3.0\nFN:Cards\nEND:VCARD\n' > "$S/main/two.vcf"
expect 1 move "red: two VCARD records in one file"

reset move
vcard "$S/main/g1.vcf" "Grace Hopper"; vcard "$S/second/a1.vcf" "Ada Lovelace"
printf 'BEGIN:VCARD\nVERSION:3.0\nUID:x\nN:NoFn;;;;\nEND:VCARD\n' > "$S/main/nofn.vcf"
expect 1 move "red: a vCard without the mandatory FN"

echo "== dispatch =="
( cd "$here" && sh ./check.sh edit ) >/dev/null 2>&1
rc=$?; n=$((n + 1))
[ "$rc" = 1 ] && echo "ok   red: an undeclared operation is refused (rc=1)" || { echo "FAIL undeclared op (rc=$rc)"; fails=$((fails + 1)); }

echo ""
echo "red-suite: $n cases, $fails failure(s)"
[ "$fails" = 0 ]
