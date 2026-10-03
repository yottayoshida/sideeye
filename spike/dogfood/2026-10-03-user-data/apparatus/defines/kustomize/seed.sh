set -eu
rm -rf /s/kustomize && mkdir -p /s/kustomize && cd /s/kustomize
printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n- deploy.yaml\nimages:\n- name: nginx\n  newTag: "1.25"\n' > kustomization.yaml
printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: web\n' > deploy.yaml
