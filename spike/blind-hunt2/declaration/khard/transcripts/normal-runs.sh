#!/bin/sh
# Normal-run (non-crash) observation of khard 0.21.0 — the script that produced
# normal-runs.txt. Permitted sources only (ADR 0012): observed normal behavior,
# no traces, no crash experiments, no source, no bug trackers. vCard file
# contents are read under the normative-format carve-out (RFC 6350; khard.conf(5):
# "vCard files to hold only one VCARD record each and end in a .vcf extension").
# Interactivity probes cap runtime and output: a command that waits for stdin is
# a fact worth one line, not a transcript of its prompt loop.
export HOME=/tmp/obs/home; mkdir -p "$HOME"
printf 'First name : Ada\nLast name  : Lovelace\n' > /tmp/obs/ada.yaml
printf 'First name : Grace\nLast name  : Hopper\n' > /tmp/obs/grace.yaml

mkbook() {  # mkbook <root>  -> writes a config with main+second under <root>
    mkdir -p "$1/main" "$1/second"
    printf '[addressbooks]\n[[main]]\npath = %s/main\n[[second]]\npath = %s/second\n' "$1" "$1" > "$1/khard.conf"
}

echo "===== 1. new from a yaml file: output, filename, file content ====="
mkbook /tmp/obs/n1
khard -c /tmp/obs/n1/khard.conf new -a main -i /tmp/obs/ada.yaml
echo "rc=$?"
echo "--- files ---"; ls /tmp/obs/n1/main
echo "--- content ---"; cat /tmp/obs/n1/main/*.vcf

echo ""
echo "===== 2. new twice into fresh stores: the UID (and filename) is random ====="
mkbook /tmp/obs/n2
khard -c /tmp/obs/n2/khard.conf new -a main -i /tmp/obs/ada.yaml >/dev/null 2>&1
f1=$(ls /tmp/obs/n2/main)
rm /tmp/obs/n2/main/*
khard -c /tmp/obs/n2/khard.conf new -a main -i /tmp/obs/ada.yaml >/dev/null 2>&1
f2=$(ls /tmp/obs/n2/main)
echo "first:  $f1"
echo "second: $f2"
[ "$f1" = "$f2" ] && echo "SAME" || echo "DIFFERENT (random per run; REV also carries a second-precision timestamp)"

echo ""
echo "===== 3. remove --force: non-interactive, deterministic across identical stores ====="
mkbook /tmp/obs/r0
khard -c /tmp/obs/r0/khard.conf new -a main -i /tmp/obs/ada.yaml >/dev/null 2>&1
khard -c /tmp/obs/r0/khard.conf new -a main -i /tmp/obs/grace.yaml >/dev/null 2>&1
cp -R /tmp/obs/r0 /tmp/obs/r1; cp -R /tmp/obs/r0 /tmp/obs/r2
printf '[addressbooks]\n[[main]]\npath = /tmp/obs/r1/main\n[[second]]\npath = /tmp/obs/r1/second\n' > /tmp/obs/r1/khard.conf
printf '[addressbooks]\n[[main]]\npath = /tmp/obs/r2/main\n[[second]]\npath = /tmp/obs/r2/second\n' > /tmp/obs/r2/khard.conf
khard -c /tmp/obs/r1/khard.conf remove --force Ada < /dev/null
echo "rc=$?"
khard -c /tmp/obs/r2/khard.conf remove --force Ada < /dev/null >/dev/null 2>&1
diff -r /tmp/obs/r1/main /tmp/obs/r2/main >/dev/null 2>&1 && echo "two identical stores end byte-identical" || echo "stores diverged"

echo ""
echo "===== 4. move: non-interactive; filename and bytes preserved across books ====="
mkbook /tmp/obs/m1
khard -c /tmp/obs/m1/khard.conf new -a main -i /tmp/obs/ada.yaml >/dev/null 2>&1
before=$(cat /tmp/obs/m1/main/*.vcf); fname=$(ls /tmp/obs/m1/main)
khard -c /tmp/obs/m1/khard.conf move -a main -A second Ada < /dev/null
echo "rc=$?"
echo "main: $(ls /tmp/obs/m1/main | wc -l) files; second: $(ls /tmp/obs/m1/second)"
after=$(cat /tmp/obs/m1/second/*.vcf)
[ "$before" = "$after" ] && [ "$fname" = "$(ls /tmp/obs/m1/second)" ] && echo "filename and bytes preserved" || echo "CHANGED"

echo ""
echo "===== 5. copy: non-interactive, but the copy gets a NEW random UID (and REV) ====="
mkbook /tmp/obs/c1
khard -c /tmp/obs/c1/khard.conf new -a main -i /tmp/obs/ada.yaml >/dev/null 2>&1
khard -c /tmp/obs/c1/khard.conf copy -a main -A second Ada < /dev/null
echo "rc=$?"
echo "main file:   $(ls /tmp/obs/c1/main)"
echo "second file: $(ls /tmp/obs/c1/second)"

echo ""
echo "===== 6. edit -i: prints, then WAITS for input (unusable without stdin) ====="
mkbook /tmp/obs/e1
khard -c /tmp/obs/e1/khard.conf new -a main -i /tmp/obs/ada.yaml >/dev/null 2>&1
printf 'First name : Ada\nLast name  : Lovelace\nNickname : Countess\n' > /tmp/obs/edit.yaml
timeout 10 khard -c /tmp/obs/e1/khard.conf edit -i /tmp/obs/edit.yaml Ada < /dev/null > /tmp/obs/edit.out 2>&1
rc=$?
head -2 /tmp/obs/edit.out
[ $rc -eq 124 ] && echo "TIMED OUT after printing the proposed modification = waits for confirmation"

echo ""
echo "===== 7. add-email -i: prompt loop on EOF (unusable without stdin) ====="
mkbook /tmp/obs/a1
khard -c /tmp/obs/a1/khard.conf new -a main -i /tmp/obs/ada.yaml >/dev/null 2>&1
printf 'From: Ada Lovelace <ada@example.org>\nSubject: x\n' > /tmp/obs/header.txt
timeout 5 khard -c /tmp/obs/a1/khard.conf add-email -i /tmp/obs/header.txt Ada < /dev/null > /tmp/obs/ae.out 2>&1
rc=$?
head -c 200 /tmp/obs/ae.out; echo ""
echo "rc=$rc; bytes of prompt output in 5s: $(wc -c < /tmp/obs/ae.out) (the Select? prompt repeats on EOF)"

echo ""
echo "===== 8. merge: needs a merge editor; without one it errors out ====="
mkbook /tmp/obs/g1
khard -c /tmp/obs/g1/khard.conf new -a main -i /tmp/obs/ada.yaml >/dev/null 2>&1
khard -c /tmp/obs/g1/khard.conf new -a main -i /tmp/obs/grace.yaml >/dev/null 2>&1
timeout 10 khard -c /tmp/obs/g1/khard.conf merge -a main -t Grace Ada < /dev/null 2>&1 | head -4
echo ""

echo "===== 9. query shapes: list, filename, and list over an empty book ====="
khard -c /tmp/obs/g1/khard.conf list < /dev/null; echo "rc=$?"
khard -c /tmp/obs/g1/khard.conf filename Ada < /dev/null; echo "rc=$?"
mkbook /tmp/obs/q1
khard -c /tmp/obs/q1/khard.conf list < /dev/null; echo "rc=$? (an empty addressbook is exit 1, 'Found no contacts')"
