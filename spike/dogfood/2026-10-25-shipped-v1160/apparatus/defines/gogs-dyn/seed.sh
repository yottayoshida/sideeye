set -eu
# The instance the restore replaces (alice, bob, two avatars) — the box's /opt/gogs-proto — and the
# app.ini the restore is pointed at, kept outside the state so renaming `custom` does not move it.
rm -rf /s/gogs /s/gogsaux && mkdir -p /s/gogsaux/tmp /s/gogsaux/log
cp -a /opt/gogs-proto /s/gogs
cp /opt/gogs-proto/custom/conf/app.ini /s/gogsaux/app.ini
install -m 755 /ap/defines/gogs-dyn/check.sh /s/gogs-check.sh
