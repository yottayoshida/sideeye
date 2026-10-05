#!/bin/sh
# Finding each candidate's seed and operation by running them, before any define is written:
# keystores, wallets and secrets. Plain runs only — no engine here.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1005 sh /ap/lab-1.sh
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 60 "$@" </dev/null 2>&1 | tail -${TAILN:-12}; echo "rc=$?"; }
tree() { find "$1" -type f -exec ls -l {} \; 2>/dev/null | awk '{print $1, $5, $9}'; }

echo "##### geth"
mkdir -p /lab/geth/ks; printf 'hunter2\n' > /lab/geth/pw
x geth account new --keystore /lab/geth/ks --password /lab/geth/pw --lightkdf
tree /lab/geth/ks
addr=$(ls /lab/geth/ks | sed 's/.*--//')
x geth account update --keystore /lab/geth/ks --password /lab/geth/pw --lightkdf "$addr"
tree /lab/geth/ks

echo "##### monero"
mkdir -p /lab/xmr; cd /lab/xmr
x monero-wallet-cli --offline --generate-new-wallet /lab/xmr/w --password pw --mnemonic-language English --use-english-language-names --log-file /lab/xmr/log exit
tree /lab/xmr
TAILN=40 x monero-wallet-cli --offline --wallet-file /lab/xmr/w --password pw --log-file /lab/xmr/log help
x monero-wallet-cli --offline --wallet-file /lab/xmr/w --password pw --log-file /lab/xmr/log set_description "rent and savings"
tree /lab/xmr
x monero-wallet-cli --offline --wallet-file /lab/xmr/w --password pw --log-file /lab/xmr/log get_description

echo "##### steamguard"
mkdir -p /lab/sg
cat > /lab/sg/manifest.json <<'J'
{"version":1,"entries":[{"filename":"alice.maFile","steam_id":76561198000000001,"account_name":"alice","encryption":null}],"keyring_id":null,"auto_confirm_market_transactions":false,"auto_confirm_trades":false}
J
cat > /lab/sg/alice.maFile <<'J'
{"shared_secret":"zvIayp3JPvtvX/QGHqsqKBk/44s=","serial_number":"12345678901234567890","revocation_code":"R12345","uri":"otpauth://totp/Steam:alice?secret=ZZZZ&issuer=Steam","server_time":1700000000,"account_name":"alice","token_gid":"abcdef0123456789","identity_secret":"Q2lkZW50aXR5LXNlY3JldC1leGFtcGxlPT0=","secret_1":"c2VjcmV0MS1leGFtcGxl","status":1,"device_id":"android:00000000-0000-0000-0000-000000000000","fully_enrolled":true,"Session":{"SessionID":"x","SteamLogin":"x","SteamLoginSecure":"x","WebCookie":"x","OAuthToken":"x","SteamID":76561198000000001}}
J
x steamguard -m /lab/sg list
x steamguard -m /lab/sg -p correcthorse encrypt
tree /lab/sg; head -c 300 /lab/sg/manifest.json; echo
x steamguard -m /lab/sg -p correcthorse code
x steamguard -m /lab/sg -p correcthorse decrypt
tree /lab/sg

echo "##### lighthouse"
mkdir -p /lab/lh/validators
cat > /lab/lh/validators/validator_definitions.yml <<'J'
---
- enabled: true
  voting_public_key: "0xa99a76ed7796f7be22d5b7e85deeb7c5677e88e511e0b337618f8c4eb61349b4bf2d153f649f7b53359fe8b94a38e44c"
  type: local_keystore
  voting_keystore_path: /lab/lh/validators/0xa99a/voting-keystore.json
  voting_keystore_password: "pw1"
- enabled: true
  voting_public_key: "0xb89bebc699769726a318c8e9971bd3171297c61aea4a6578a7a4f94b547dcba5bac16a89108b6b6a1fe3695d1a874a0b"
  type: local_keystore
  voting_keystore_path: /lab/lh/validators/0xb89b/voting-keystore.json
  voting_keystore_password: "pw2"
J
TAILN=20 x lighthouse account validator modify --datadir /lab/lh disable --pubkey 0xa99a76ed7796f7be22d5b7e85deeb7c5677e88e511e0b337618f8c4eb61349b4bf2d153f649f7b53359fe8b94a38e44c
tree /lab/lh; cat /lab/lh/validators/validator_definitions.yml | head -8
