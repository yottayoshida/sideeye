set -eu
rm -rf /s/av /s/avaux && mkdir -p /s/av /s/avaux/pin /s/aux/tmp/ansible
printf 'correct horse battery staple\n' > /s/avaux/pw && chmod 0600 /s/avaux/pw
cat > /s/avaux/pin/sitecustomize.py <<'EOF'
import os
os.urandom = lambda n: bytes((i * 37 + 11) % 256 for i in range(n))
EOF
cat > /s/av/secrets.yml <<'EOF'
# Production secrets for the web tier. Rotated 2026-09-30.
db_host: db.internal.example
db_user: web
db_password: s3cr3t-before-encryption
stripe_api_key: example-stripe-api-key
smtp_password: mailer-example-password
EOF
