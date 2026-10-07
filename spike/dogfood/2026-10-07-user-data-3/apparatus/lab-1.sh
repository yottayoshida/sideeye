#!/bin/sh
# Lab 1 (2026-10-07 user-data-3): each first-screen candidate's operation found by hand in the box,
# with stdin at EOF as a define gives it, before any define is written.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1007 sh /ap/lab-1.sh > transcripts/lab-1.txt 2>&1
set -u
. /ap/env.sh
show() { echo "\$ $*"; "$@" < /dev/null 2>&1 | head -12 | cut -c1-160; echo "  -> exit $?"; }
digest() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-12); }
kind() { f=$(command -v "$1" 2>/dev/null || echo "$1"); echo "  image: $(file -L "$f" | sed 's/^[^:]*: //' | cut -c1-110)"; }

echo "=== openssl ca -revoke"
kind openssl
d=/s/ca; rm -rf $d; mkdir -p $d/newcerts $d/private; cd $d
touch index.txt; echo 1000 > serial; echo 1000 > crlnumber
cat > ca.cnf <<'EOF'
[ ca ]
default_ca = CA_default
[ CA_default ]
dir = /s/ca
database = $dir/index.txt
new_certs_dir = $dir/newcerts
certificate = $dir/ca.crt
private_key = $dir/private/ca.key
serial = $dir/serial
crlnumber = $dir/crlnumber
default_md = sha256
default_days = 365
default_crl_days = 30
policy = policy_any
unique_subject = no
[ policy_any ]
commonName = supplied
[ req ]
distinguished_name = dn
prompt = no
[ dn ]
CN = Test CA
EOF
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout private/ca.key -out ca.crt -days 365 -config ca.cnf > seed.log 2>&1
for n in a b c; do
  openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout $n.key -out $n.csr -subj /CN=$n >> seed.log 2>&1
  openssl ca -batch -config ca.cnf -in $n.csr -out $n.crt >> seed.log 2>&1
done
ls; cat index.txt | cut -c1-80
b=$(digest $d); show openssl ca -config ca.cnf -revoke b.crt -batch; echo "  state: $b -> $(digest $d)"; ls; cat index.txt | cut -c1-80
show openssl ca -config ca.cnf -gencrl -out crl.pem; echo "  crlnumber now $(cat crlnumber)"

echo "=== minisign -C"
kind minisign
d=/s/mini; rm -rf $d; mkdir -p $d; cd $d
show minisign -G -W -p pk -s sk
b=$(digest $d); show minisign -C -W -s sk; echo "  state: $b -> $(digest $d)"
show minisign -C -s sk; echo "  state: $(digest $d)"
printf 'a\na\n' | minisign -G -p pk2 -s sk2 > /dev/null 2>&1; echo "  passworded key made: $(ls sk2 2>/dev/null)"
b=$(digest $d); show minisign -C -W -s sk2; echo "  state: $b -> $(digest $d)"

echo "=== sfntedit (afdko)"
kind sfntedit
d=/s/font; rm -rf $d; mkdir -p $d; cd $d
/opt/py/bin/python -I - <<'PY'
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
fb = FontBuilder(1000, isTTF=True)
fb.setupGlyphOrder([".notdef", "A"]); fb.setupCharacterMap({65: "A"})
p = TTGlyphPen(None); p.moveTo((100, 0)); p.lineTo((500, 700)); p.lineTo((900, 0)); p.closePath(); g = p.glyph()
fb.setupGlyf({".notdef": g, "A": g}); fb.setupHorizontalMetrics({".notdef": (1000, 100), "A": (1000, 100)})
fb.setupHorizontalHeader(ascent=800, descent=-200); fb.setupNameTable({"familyName": "T", "styleName": "Regular"})
fb.setupOS2(); fb.setupPost(); fb.setupDummyDSIG(); fb.save("f.ttf")
PY
ls -l f.ttf | cut -c1-80; show sfntedit -l f.ttf
b=$(digest $d); show sfntedit -d DSIG f.ttf; echo "  state: $b -> $(digest $d)"; ls
printf 'x%.0s' $(seq 1 64) > blob.bin; b=$(digest $d); show sfntedit -a TEST=blob.bin f.ttf; echo "  state: $b -> $(digest $d)"; ls

echo "=== keyring del (keyrings.alt plaintext)"
kind /opt/py/bin/python3
export PYTHON_KEYRING_BACKEND=keyrings.alt.file.PlaintextKeyring
/opt/py/bin/python -I -c "import keyring; [keyring.set_password(s,u,p) for s,u,p in (('svc','u1','examplepass1'),('svc','u2','examplepass2'),('other','u3','examplepass3'))]; print(keyring.get_keyring().file_path)"
f=$(/opt/py/bin/python -I -c "import keyring; print(keyring.get_keyring().file_path)"); d=$(dirname "$f"); ls -l "$d" | tail -n +2
b=$(digest $d); show keyring del svc u1; echo "  state: $b -> $(digest $d)"; grep -c '' "$f"
unset PYTHON_KEYRING_BACKEND

echo "=== zsh-z --add"
kind zsh
d=/s/z; rm -rf $d; mkdir -p $d/data $d/d1 $d/d2 $d/d3; cd $d
printf 'ZSHZ_DATA=/s/z/data/.z\nsource /opt/zsh-z/zsh-z.plugin.zsh\nzshz --add /s/z/d1\nzshz --add /s/z/d2\n' > seed.zsh
printf 'ZSHZ_DATA=/s/z/data/.z\nsource /opt/zsh-z/zsh-z.plugin.zsh\nzshz --add /s/z/d3\nzshz --add /s/z/d1\n' > op.zsh
show zsh seed.zsh; cat data/.z
b=$(digest $d/data); show zsh op.zsh; echo "  state: $b -> $(digest $d/data)"; cat data/.z; ls -la data

echo "=== rustic"
kind rustic
d=/s/rustic; rm -rf $d; mkdir -p $d/data; cd $d
export RUSTIC_PASSWORD=examplepass RUSTIC_REPOSITORY=/s/rustic/repo RUSTIC_NO_PROGRESS=true
echo a > data/a; show rustic init; show rustic backup /s/rustic/data; echo b > data/b; show rustic backup /s/rustic/data
show rustic snapshots
b=$(digest $d/repo); show rustic config --set-compression 5; echo "  state: $b -> $(digest $d/repo)"
b=$(digest $d/repo); show rustic forget --keep-last 1 --prune; echo "  state: $b -> $(digest $d/repo)"
unset RUSTIC_PASSWORD RUSTIC_REPOSITORY RUSTIC_NO_PROGRESS

echo "=== lxc (lxd client) alias"
kind lxc
show lxc alias add l1 list; show lxc alias add l2 info; show lxc alias list
c=$HOME/.config/lxc; ls -la $c 2>&1 | tail -n +2
b=$(digest $c); show lxc alias remove l1; echo "  state: $b -> $(digest $c)"
b=$(digest $c); show lxc alias rename l2 l3; echo "  state: $b -> $(digest $c)"

echo "=== duplicacy set"
kind duplicacy
d=/s/dup; rm -rf $d; mkdir -p $d/repo $d/storage; cd $d/repo; echo x > f
show duplicacy init snap1 /s/dup/storage; show duplicacy backup
ls -la .duplicacy; show duplicacy set
b=$(digest $d/repo/.duplicacy); show duplicacy set -nobackup; echo "  state: $b -> $(digest $d/repo/.duplicacy)"

echo "=== plakar rm"
kind plakar
d=/s/plakar; rm -rf $d; mkdir -p $d/data; echo a > $d/data/a
show plakar at $d/repo create -plaintext; show plakar at $d/repo create -no-encryption
show plakar at $d/repo backup $d/data; echo b > $d/data/b; show plakar at $d/repo backup $d/data
show plakar at $d/repo ls

echo "=== ferium profile"
kind ferium
show ferium profile create --name p1 --game-version 1.20.1 --mod-loader fabric --output-dir /s/ferium/mods1
ls -la $HOME/.config/ferium 2>&1 | tail -n +2; show ferium profiles

echo "=== espsecure sign-data in place"
kind /opt/py/bin/python3
d=/s/esp; rm -rf $d; mkdir -p $d; cd $d
show espsecure generate-signing-key --version 2 --scheme ecdsa256 k.pem
head -c 65536 /dev/urandom > fw.bin
b=$(digest $d); show espsecure sign-data --version 2 --keyfile k.pem fw.bin; echo "  state: $b -> $(digest $d)"; ls -l
