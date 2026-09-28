set -eu
rm -rf /s/kubectl && mkdir -p /s/kubectl
cat > /s/kubectl/config <<'Y'
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://a.example.invalid
  name: a
- cluster:
    server: https://b.example.invalid
  name: b
contexts:
- context:
    cluster: a
    user: u
  name: a
- context:
    cluster: b
    user: u
  name: b
current-context: a
users:
- name: u
  user:
    token: not-a-real-credential
preferences: {}
Y
chmod 600 /s/kubectl/config
