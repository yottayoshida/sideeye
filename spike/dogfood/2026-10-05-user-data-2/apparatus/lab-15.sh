#!/bin/sh
# Plain runs: crictl's config, kubeadm's config migrate and certs renew.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 120 "$@" </dev/null 2>&1 | tail -${TAILN:-10}; echo "rc=$?"; }
sum() { find "$1" -type f -exec sha256sum {} \; 2>/dev/null | cut -c1-12,65- | sort -k2; }
mkdir -p /lab/cri; printf 'runtime-endpoint: unix:///run/containerd/containerd.sock\nimage-endpoint: unix:///run/containerd/containerd.sock\ntimeout: 2\ndebug: false\n' > /lab/cri/crictl.yaml
x crictl --config /lab/cri/crictl.yaml config --set timeout=10
sum /lab/cri; cat /lab/cri/crictl.yaml
mkdir -p /lab/kadm/pki /lab/kadm-in
printf 'apiVersion: kubeadm.k8s.io/v1beta4\nkind: ClusterConfiguration\nkubernetesVersion: v1.37.1\ncertificatesDir: /lab/kadm/pki\nclusterName: home\n' > /lab/kadm-in/config.yaml
x kubeadm init phase certs ca --config /lab/kadm-in/config.yaml
x kubeadm init phase certs apiserver --config /lab/kadm-in/config.yaml
sum /lab/kadm
x kubeadm certs renew apiserver --config /lab/kadm-in/config.yaml
sum /lab/kadm
