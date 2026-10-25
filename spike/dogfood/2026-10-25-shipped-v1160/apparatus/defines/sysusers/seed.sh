set -eu
# An image root's four account databases, the ones an image build or a package's postinst hands to
# `systemd-sysusers --root=`: users and groups a running system's files are owned by. The config that
# asks for one more system user and group lives outside the state.
rm -rf /s/sysroot /s/sysaux && mkdir -p /s/sysroot/etc /s/sysaux
cat > /s/sysroot/etc/passwd <<'EOF'
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
sys:x:3:3:sys:/dev:/usr/sbin/nologin
www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
postgres:x:105:110:PostgreSQL administrator:/var/lib/postgresql:/bin/bash
alice:x:1000:1000:Alice,,,:/home/alice:/bin/bash
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
EOF
cat > /s/sysroot/etc/shadow <<'EOF'
root:$y$j9T$examplesaltexample$examplehashexamplehashexamplehashexamp:20300:0:99999:7:::
daemon:*:20300:0:99999:7:::
bin:*:20300:0:99999:7:::
sys:*:20300:0:99999:7:::
www-data:*:20300:0:99999:7:::
postgres:!:20300::::::
alice:$y$j9T$examplesaltalice00$examplehashforalicexamplehashforalic:20300:0:99999:7:::
nobody:*:20300:0:99999:7:::
EOF
cat > /s/sysroot/etc/group <<'EOF'
root:x:0:
daemon:x:1:
bin:x:2:
sys:x:3:
adm:x:4:alice
sudo:x:27:alice
www-data:x:33:
postgres:x:110:
ssl-cert:x:111:postgres
alice:x:1000:
nogroup:x:65534:
EOF
cat > /s/sysroot/etc/gshadow <<'EOF'
root:*::
daemon:*::
bin:*::
sys:*::
adm:*::alice
sudo:*::alice
www-data:*::
postgres:!::
ssl-cert:!::postgres
alice:!::
nogroup:*::
EOF
chmod 0644 /s/sysroot/etc/passwd /s/sysroot/etc/group
chmod 0640 /s/sysroot/etc/shadow /s/sysroot/etc/gshadow
cat > /s/sysaux/app.conf <<'EOF'
g appsvc -
u appsvc -:appsvc "Example application service" /var/lib/appsvc
m appsvc ssl-cert
EOF
