set -eu
rm -rf /s/kubecm /s/kubecm-in && mkdir -p /s/kubecm /s/kubecm-in /s/aux/home/.kube
cat > /s/kubecm/config <<'Y'
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://prod.example.invalid:6443
    certificate-authority-data: Y2EtcHJvZA==
  name: prod
- cluster:
    server: https://staging.example.invalid:6443
    certificate-authority-data: Y2Etc3RhZ2luZw==
  name: staging
contexts:
- context: {cluster: prod, user: prod-admin}
  name: prod
- context: {cluster: staging, user: staging-admin}
  name: staging
current-context: prod
users:
- name: prod-admin
  user: {token: placeholder-prod-credential}
- name: staging-admin
  user: {token: placeholder-staging-credential}
Y
