#!/bin/sh
# Plain runs: juju's client-side credentials, kubeadm's config migrate.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 120 "$@" </dev/null 2>&1 | tail -${TAILN:-10}; echo "rc=$?"; }
sum() { find "$1" -type f -exec sha256sum {} \; 2>/dev/null | cut -c1-12,65- | sort -k2; }
export JUJU_DATA=/lab/juju; mkdir -p /lab/juju-in
printf 'credentials:\n  aws:\n    work:\n      auth-type: access-key\n      access-key: FAKE-ACCESS-ID-00001\n      secret-key: example-secret-1\n    home:\n      auth-type: access-key\n      access-key: FAKE-ACCESS-ID-00002\n      secret-key: example-secret-2\n' > /lab/juju-in/creds.yaml
x juju add-credential aws -f /lab/juju-in/creds.yaml --client
sum /lab/juju; cat /lab/juju/credentials.yaml
x juju remove-credential aws home --client
sum /lab/juju; cat /lab/juju/credentials.yaml
x juju default-credential aws work --client
sum /lab/juju
mkdir -p /lab/kadm
printf 'apiVersion: kubeadm.k8s.io/v1beta3\nkind: ClusterConfiguration\nkubernetesVersion: v1.36.0\nclusterName: home\nnetworking:\n  podSubnet: 10.244.0.0/16\n' > /lab/kadm/kubeadm.yaml
x kubeadm config migrate --old-config /lab/kadm/kubeadm.yaml --new-config /lab/kadm/kubeadm.yaml
sum /lab/kadm; head -20 /lab/kadm/kubeadm.yaml
