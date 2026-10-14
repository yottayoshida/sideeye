set -eu
rm -rf /s/dv /s/dv-aux && mkdir -p /s/dv/admin /s/dv/root/usr/bin /s/dv-aux
printf 'the original tool\n' > /s/dv/root/usr/bin/tool
: > /s/dv/admin/diversions
install -m 755 /ap/defines/divert/check.sh /s/dv-aux/check.sh
