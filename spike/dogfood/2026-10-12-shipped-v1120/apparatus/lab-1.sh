#!/bin/sh
# Lab 1: each candidate's write, by hand and without Sideeye, before any define is written — the
# flags each command takes on this build, whether it runs with no network, and its linkage.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-sv1012 sh /ap/lab-1.sh
set -u
. /ap/env.sh
L=/s/lab; rm -rf "$L"; mkdir -p "$L"
hr() { echo; echo "======== $*"; }
for b in keepassxc-cli sops rclone duckdb yq crystal bun swiftlint /opt/freecad/usr/bin/freecadcmd /opt/py/bin/python3; do
  p=$(command -v "$b" || echo "$b"); echo "link $b: $(file -bL "$p" | cut -c1-110)"
done

hr keepassxc-cli db-create / add help
keepassxc-cli db-create --help 2>&1 | sed -n '1,30p'
keepassxc-cli add --help 2>&1 | grep -E -- '--no-password|-k,|--key-file|-u,|--url|-p,' | head
mkdir -p $L/kp && cd $L/kp && keepassxc-cli db-create --set-key-file key.keyx vault.kdbx < /dev/null; echo "db-create rc=$?"; ls -la
keepassxc-cli add --no-password -k key.keyx vault.kdbx Web/github -u me --url https://github.com < /dev/null; echo "add rc=$?"
keepassxc-cli ls --no-password -k key.keyx -R vault.kdbx < /dev/null; echo "ls rc=$?"

hr sops set
mkdir -p $L/sops && cd $L/sops && export SOPS_AGE_KEY_FILE=/opt/sops-age-key.txt
r=$(sed -n 's/^Public key: //p' /opt/sops-age-recipient.txt)
printf 'db:\n  user: app\n  password: changeme\napi:\n  token: abc123\n' > plain.yaml
sops encrypt --age "$r" plain.yaml > secrets.enc.yaml < /dev/null; echo "encrypt rc=$?"
sops set secrets.enc.yaml '["db"]["password"]' '"hunter2"' < /dev/null; echo "set rc=$?"
sops decrypt secrets.enc.yaml < /dev/null | head -3

hr rclone config update
mkdir -p $L/rc && cd $L/rc && export RCLONE_CONFIG=$L/rc/rclone.conf
printf '[backup]\ntype = local\n\n[s3prod]\ntype = s3\nprovider = AWS\naccess_key_id = AKIAEXAMPLE\nregion = us-east-1\n' > rclone.conf
rclone config update s3prod region eu-west-1 --non-interactive < /dev/null; echo "update rc=$?"; cat rclone.conf; ls -la

hr duckdb update
mkdir -p $L/dk && cd $L/dk
duckdb shop.duckdb -c "CREATE TABLE orders AS SELECT range AS id, 'new' AS status FROM range(1000)" < /dev/null; echo "create rc=$?"
duckdb shop.duckdb -c "UPDATE orders SET status='shipped' WHERE id < 10" < /dev/null; echo "update rc=$?"
duckdb -readonly shop.duckdb -c "SELECT status, count(*) FROM orders GROUP BY 1 ORDER BY 1" < /dev/null; ls -la

hr yq -i
mkdir -p $L/yq && cd $L/yq && printf 'apiVersion: apps/v1\nkind: Deployment\nspec:\n  replicas: 1 # keep\n' > d.yaml && chmod 640 d.yaml
yq -i '.spec.replicas = 3' d.yaml < /dev/null; echo "yq rc=$?"; cat d.yaml; ls -la d.yaml

hr crystal tool format
mkdir -p $L/cr && cd $L/cr && printf 'def add(a,b)\na+b\nend\nputs add( 1,2 )\n' > app.cr
crystal tool format app.cr < /dev/null; echo "format rc=$?"; cat app.cr

hr swiftlint --fix
mkdir -p $L/sw && cd $L/sw && printf 'let a = 1;   \nlet b = 2;\n' > App.swift
swiftlint --fix --no-cache App.swift < /dev/null; echo "fix rc=$?"; cat -A App.swift | head
swiftlint --help 2>&1 | head -20

hr bun add
mkdir -p $L/bunaux/deppkg/package $L/bun && printf '{ "name": "probe-dep", "version": "1.0.0", "main": "index.js" }\n' > $L/bunaux/deppkg/package/package.json
printf 'module.exports = "probe-dep";\n' > $L/bunaux/deppkg/package/index.js; tar -czf $L/bunaux/dep-1.0.0.tgz -C $L/bunaux/deppkg package
cd $L/bun && printf '{ "name": "probe-proj", "version": "1.0.0" }\n' > package.json
BUN_INSTALL_CACHE_DIR=$L/bun-cache bun add $L/bunaux/dep-1.0.0.tgz < /dev/null; echo "bun add rc=$?"; cat package.json; ls

hr ansible-vault encrypt
mkdir -p $L/av $L/avaux && cd $L/av && printf 'hunter2\n' > $L/avaux/pw && chmod 600 $L/avaux/pw
printf 'db_password: changeme\napi_token: abc123\n' > secrets.yml
ansible-vault encrypt secrets.yml --vault-password-file $L/avaux/pw < /dev/null; echo "encrypt rc=$?"; head -2 secrets.yml
ansible-vault rekey secrets.yml --vault-password-file $L/avaux/pw --new-vault-password-file $L/avaux/pw < /dev/null; echo "rekey rc=$?"

hr freecadcmd save
mkdir -p $L/fc && cd $L/fc
cat > mk.py <<'EOF'
import FreeCAD, Part
d = FreeCAD.newDocument("part"); b = d.addObject("Part::Box", "Box"); b.Length = 10; d.recompute(); d.saveAs("/s/lab/fc/part.FCStd")
EOF
cat > edit.py <<'EOF'
import FreeCAD
d = FreeCAD.openDocument("/s/lab/fc/part.FCStd"); d.getObject("Box").Length = 20; d.recompute(); d.save()
EOF
/opt/freecad/usr/bin/freecadcmd mk.py < /dev/null > fc1.log 2>&1; echo "mk rc=$?"; tail -3 fc1.log
/opt/freecad/usr/bin/freecadcmd edit.py < /dev/null > fc2.log 2>&1; echo "edit rc=$?"; tail -3 fc2.log; ls -la
