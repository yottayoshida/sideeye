set -eu
. /ap/defines/easyrsa/env.sh
rm -rf /s/easyrsa /s/easyrsa-in && mkdir -p /s/easyrsa /s/easyrsa-in && cd /s/easyrsa-in
easyrsa init-pki > seed.log 2>&1
easyrsa build-ca nopass >> seed.log 2>&1
easyrsa build-client-full c1 nopass >> seed.log 2>&1
easyrsa build-client-full c2 nopass >> seed.log 2>&1
test "$(grep -c '^V' /s/easyrsa/pki/index.txt)" = 2
