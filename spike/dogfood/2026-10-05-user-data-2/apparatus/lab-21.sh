#!/bin/sh
# Plain runs: kubeadm config migrate onto its own input, with the current API version.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 120 "$@" </dev/null 2>&1 | tail -${TAILN:-10}; echo "rc=$?"; }
mkdir -p /lab/kadm
printf 'apiVersion: kubeadm.k8s.io/v1beta4\nkind: ClusterConfiguration\nkubernetesVersion: v1.37.1\nclusterName: home\nnetworking:\n  podSubnet: 10.244.0.0/16\n' > /lab/kadm/kubeadm.yaml
sha256sum /lab/kadm/kubeadm.yaml
x kubeadm config migrate --old-config /lab/kadm/kubeadm.yaml --new-config /lab/kadm/kubeadm.yaml
sha256sum /lab/kadm/kubeadm.yaml; cat /lab/kadm/kubeadm.yaml | head -30
x kubeadm config migrate --old-config /lab/kadm/kubeadm.yaml --new-config /lab/kadm/kubeadm.yaml
sha256sum /lab/kadm/kubeadm.yaml
