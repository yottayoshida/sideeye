set -eu
rm -rf /s/acme /s/acme-in && mkdir -p /s/acme-in
cd /opt/acme.sh-src && ./acme.sh --install --home /s/acme --config-home /s/acme/conf --nocron --noprofile --accountemail ops@example.invalid > /s/acme-in/seed.log 2>&1
/s/acme/acme.sh --home /s/acme --config-home /s/acme/conf --set-default-ca --server zerossl >> /s/acme-in/seed.log 2>&1
grep -q zerossl /s/acme/conf/account.conf
