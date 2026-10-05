set -eu
rm -rf /s/kadm /s/kadm-in && mkdir -p /s/kadm /s/kadm-in
printf 'apiVersion: kubeadm.k8s.io/v1beta4\nkind: ClusterConfiguration\nkubernetesVersion: v1.37.1\nclusterName: home\nnetworking:\n  podSubnet: 10.244.0.0/16\n' > /s/kadm/kubeadm.yaml
kubeadm config migrate --old-config /s/kadm/kubeadm.yaml --new-config /s/kadm/kubeadm.yaml > /s/kadm-in/seed.log 2>&1
sed -i '/imagePullSerial/d' /s/kadm/kubeadm.yaml
