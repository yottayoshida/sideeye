#!/bin/sh
# Second pass on lab-1's three: geth's --password placement, monero's settings (the .keys file), and
# steamguard with the field its account format requires.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 60 "$@" </dev/null 2>&1 | tail -${TAILN:-8}; echo "rc=$?"; }
tree() { find "$1" -type f -exec ls -l {} \; 2>/dev/null | awk '{print $1, $5, $9}'; }
sum() { find "$1" -type f -exec sha256sum {} \; | cut -c1-12,65-; }
echo "##### geth"
mkdir -p /lab/geth/ks; printf 'hunter2\n' > /lab/geth/pw
geth account new --keystore /lab/geth/ks --password /lab/geth/pw --lightkdf >/dev/null 2>&1
addr=$(ls /lab/geth/ks | sed 's/.*--//'); sum /lab/geth/ks
x geth --password /lab/geth/pw account update --keystore /lab/geth/ks --lightkdf "$addr"
x geth account update --keystore /lab/geth/ks --lightkdf --password /lab/geth/pw "$addr"
TAILN=30 x sh -c 'geth account update --help | grep -i -B1 -A2 pass'
sum /lab/geth/ks
echo "##### monero"
mkdir -p /lab/xmr /lab/xmrlog
monero-wallet-cli --offline --generate-new-wallet /lab/xmr/w --password pw --mnemonic-language English --log-file /lab/xmrlog/log >/dev/null 2>&1
sum /lab/xmr
x monero-wallet-cli --offline --wallet-file /lab/xmr/w --password pw --log-file /lab/xmrlog/log set always-confirm-transfers 0
sum /lab/xmr
x monero-wallet-cli --offline --wallet-file /lab/xmr/w --password pw --log-file /lab/xmrlog/log set
echo "##### steamguard"
mkdir -p /lab/sg
printf '%s\n' '{"version":1,"entries":[{"filename":"alice.maFile","steam_id":76561198000000001,"account_name":"alice","encryption":null}],"keyring_id":null,"auto_confirm_market_transactions":false,"auto_confirm_trades":false}' > /lab/sg/manifest.json
printf '%s\n' '{"shared_secret":"zvIayp3JPvtvX/QGHqsqKBk/44s=","serial_number":"12345678901234567890","revocation_code":"R12345","uri":"otpauth://totp/Steam:alice?secret=ZZZZ&issuer=Steam","server_time":1700000000,"account_name":"alice","token_gid":"abcdef0123456789","identity_secret":"Q2lkZW50aXR5LXNlY3JldC1leGFtcGxlPT0=","secret_1":"c2VjcmV0MS1leGFtcGxl","status":1,"device_id":"android:00000000-0000-0000-0000-000000000000","fully_enrolled":true,"steam_id":76561198000000001}' > /lab/sg/alice.maFile
x steamguard -m /lab/sg code
x steamguard -m /lab/sg -p correcthorse encrypt
tree /lab/sg; head -c 260 /lab/sg/manifest.json; echo
x steamguard -m /lab/sg -p correcthorse code
x steamguard -m /lab/sg -p correcthorse decrypt
tree /lab/sg
