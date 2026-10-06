set -eu
rm -rf /s/fw /s/fw-in && mkdir -p /s/fw /s/fw-in
cp /etc/firewalld/firewalld.conf /s/fw/
firewall-offline-cmd --system-config /s/fw --zone=public --add-service=ssh > /s/fw-in/seed.log 2>&1
test -s /s/fw/zones/public.xml
