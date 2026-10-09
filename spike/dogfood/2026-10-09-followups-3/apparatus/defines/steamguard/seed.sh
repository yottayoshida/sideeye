set -eu
rm -rf /s/sg /s/sg-in && mkdir -p /s/sg /s/sg-in
printf '%s\n' '{"version":1,"entries":[{"filename":"alice.maFile","steam_id":76561198000000001,"account_name":"alice","encryption":null}],"keyring_id":null,"auto_confirm_market_transactions":false,"auto_confirm_trades":false}' > /s/sg/manifest.json
printf '%s\n' '{"shared_secret":"zvIayp3JPvtvX/QGHqsqKBk/44s=","serial_number":"12345678901234567890","revocation_code":"R12345","uri":"otpauth://totp/Steam:alice?secret=ZZZZ&issuer=Steam","server_time":1700000000,"account_name":"alice","token_gid":"abcdef0123456789","identity_secret":"Q2lkZW50aXR5LXNlY3JldC1leGFtcGxlPT0=","secret_1":"c2VjcmV0MS1leGFtcGxl","status":1,"device_id":"android:00000000-0000-0000-0000-000000000000","fully_enrolled":true,"steam_id":76561198000000001}' > /s/sg/alice.maFile
steamguard -m /s/sg -p correcthorse encrypt > /s/sg-in/encrypt.log 2>&1
grep -q Argon2id /s/sg/manifest.json
