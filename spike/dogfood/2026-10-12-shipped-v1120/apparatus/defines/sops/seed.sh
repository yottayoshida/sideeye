set -eu
# A secrets file encrypted to the box's own age key (made once at build, Dockerfile).
rm -rf /s/sops /s/sopsaux && mkdir -p /s/sops
r=$(sed -n 's/^Public key: //p' /opt/sops-age-recipient.txt)
cat > /tmp/sops-plain.yaml <<'EOF'
db:
  host: db.internal.example
  user: web
  password: changeme
api:
  stripe_key: example-stripe-key
  smtp_password: mailer-example
EOF
SOPS_AGE_KEY_FILE=/opt/sops-age-key.txt sops encrypt --age "$r" --output /s/sops/secrets.enc.yaml /tmp/sops-plain.yaml < /dev/null
rm -f /tmp/sops-plain.yaml
