set -eu
rm -rf /s/xmr /s/xmr-in && mkdir -p /s/xmr /s/xmr-in
monero-wallet-cli --offline --generate-new-wallet /s/xmr/w --password pw --mnemonic-language English --log-file /s/xmr-in/log exit > /s/xmr-in/gen.log 2>&1 || true
test -s /s/xmr/w.keys && test -s /s/xmr/w
