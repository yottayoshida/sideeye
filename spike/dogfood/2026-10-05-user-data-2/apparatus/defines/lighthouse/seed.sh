set -eu
rm -rf /s/lh /s/lh-in && mkdir -p /s/lh/validators /s/lh-in
cat > /s/lh/validators/validator_definitions.yml <<'J'
---
- enabled: true
  voting_public_key: "0xa99a76ed7796f7be22d5b7e85deeb7c5677e88e511e0b337618f8c4eb61349b4bf2d153f649f7b53359fe8b94a38e44c"
  type: local_keystore
  voting_keystore_path: /s/lh/validators/0xa99a/voting-keystore.json
  voting_keystore_password: "pw1"
- enabled: true
  voting_public_key: "0xb89bebc699769726a318c8e9971bd3171297c61aea4a6578a7a4f94b547dcba5bac16a89108b6b6a1fe3695d1a874a0b"
  type: local_keystore
  voting_keystore_path: /s/lh/validators/0xb89b/voting-keystore.json
  voting_keystore_password: "pw2"
J
