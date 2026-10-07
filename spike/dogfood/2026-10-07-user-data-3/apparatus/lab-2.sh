#!/bin/sh
# Lab 2 (2026-10-07 user-data-3): lab 1's open questions again, with the exit status of the tool
# itself (lab 1's `show` printed `cut`'s, the last command of its pipe), and three candidates that
# hand their writes to a child (acme.sh, easyrsa, git-lfs).
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1007 sh /ap/lab-2.sh > transcripts/lab-2.txt 2>&1
set -u
. /ap/env.sh
show() { echo "\$ $*"; "$@" < /dev/null > /tmp/show.out 2>&1; rc=$?; head -12 /tmp/show.out | cut -c1-160; echo "  -> exit $rc"; }
digest() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-12); }
kind() { f=$(command -v "$1" 2>/dev/null || echo "$1"); echo "  image: $f: $(file -L "$f" | sed 's/^[^:]*: //' | cut -c1-110)"; }

echo "=== sfntedit: the entry point and the binary behind it"
kind sfntedit; sed -n 1,12p "$(command -v sfntedit)"
ls -l /opt/py/lib/python3*/site-packages/afdko/bin 2>/dev/null | head; find /opt/py -type f -name 'sfntedit*' 2>/dev/null | head

echo "=== duplicacy set -no-backup"
d=/s/dup; rm -rf $d; mkdir -p $d/repo $d/storage; cd $d/repo; echo x > f
duplicacy init snap1 /s/dup/storage > /dev/null 2>&1; duplicacy backup > /dev/null 2>&1
b=$(digest $d/repo/.duplicacy); show duplicacy set -no-backup; echo "  state: $b -> $(digest $d/repo/.duplicacy)"; grep -o '"no_backup": *[a-z]*' .duplicacy/preferences

echo "=== plakar with a passphrase from the environment"
d=/s/plakar; rm -rf $d; mkdir -p $d/data; echo a > $d/data/a
export PLAKAR_PASSPHRASE=examplepassphrase0001
show plakar -disable-security-check
show plakar at $d/repo create; show plakar at $d/repo backup $d/data; echo b > $d/data/b; show plakar at $d/repo backup $d/data
show plakar at $d/repo ls
id=$(plakar at $d/repo ls 2>/dev/null | awk 'NR==1{print $2}'); echo "  first snapshot: [$id]"
b=$(digest $d/repo); show plakar at $d/repo rm "$id"; echo "  state: $b -> $(digest $d/repo)"
unset PLAKAR_PASSPHRASE

echo "=== ferium profile switch / delete / configure"
kind ferium
rm -rf $HOME/.config/ferium
for n in p1 p2 p3; do ferium profile create --name $n --game-version 1.20.1 --mod-loader fabric --output-dir /s/ferium/$n > /dev/null 2>&1; done
c=$HOME/.config/ferium; show ferium profiles
b=$(digest $c); show ferium profile switch --profile-name p1; echo "  state: $b -> $(digest $c)"
b=$(digest $c); show ferium profile configure --name p1b; echo "  state: $b -> $(digest $c)"
b=$(digest $c); show ferium profile delete --profile-name p2; echo "  state: $b -> $(digest $c)"

echo "=== espsecure sign-data in place"
d=/s/esp; rm -rf $d; mkdir -p $d; cd $d
espsecure generate-signing-key --version 2 --scheme ecdsa256 k.pem > /dev/null 2>&1; head -c 65536 /dev/urandom > fw.bin
show espsecure sign-data -h
b=$(digest $d); show espsecure sign-data --version 2 --keyfile=k.pem fw.bin; echo "  state: $b -> $(digest $d)"; ls -l
b=$(digest $d); show espsecure sign-data fw.bin --version 2 --keyfile k.pem; echo "  state: $b -> $(digest $d)"; ls -l

echo "=== acme.sh --set-default-ca (installed offline from its tag)"
kind sh
cd /opt/acme.sh-src && show ./acme.sh --install --home /s/acme --config-home /s/acme/conf --nocron --noprofile --accountemail ops@example.invalid
ls -la /s/acme/conf 2>&1 | tail -n +2
b=$(digest /s/acme/conf); show /s/acme/acme.sh --home /s/acme --config-home /s/acme/conf --set-default-ca --server letsencrypt; echo "  state: $b -> $(digest /s/acme/conf)"
b=$(digest /s/acme/conf); show /s/acme/acme.sh --home /s/acme --config-home /s/acme/conf --set-notify --notify-level 1; echo "  state: $b -> $(digest /s/acme/conf)"

echo "=== easyrsa revoke"
kind easyrsa
d=/s/pki-w; rm -rf $d; mkdir -p $d; cd $d
export EASYRSA_BATCH=1 EASYRSA_PKI=/s/pki-w/pki EASYRSA_REQ_CN=TestCA
show easyrsa init-pki; show easyrsa build-ca nopass; show easyrsa build-client-full c1 nopass; show easyrsa build-client-full c2 nopass
b=$(digest $d/pki); show easyrsa revoke c1; echo "  state: $b -> $(digest $d/pki)"
unset EASYRSA_BATCH EASYRSA_PKI EASYRSA_REQ_CN

echo "=== git-lfs install / uninstall"
kind git-lfs
printf '[user]\n\tname = t\n\temail = t@example.invalid\n' > $HOME/.gitconfig
b=$(digest $HOME); show git-lfs install --skip-repo; echo "  home: $b -> $(digest $HOME)"; cat $HOME/.gitconfig
b=$(digest $HOME); show git-lfs uninstall --skip-repo; echo "  home: $b -> $(digest $HOME)"; cat $HOME/.gitconfig
