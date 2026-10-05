set -eu
rm -rf /s/cri /s/cri-in && mkdir -p /s/cri /s/cri-in
printf 'runtime-endpoint: unix:///run/containerd/containerd.sock\nimage-endpoint: unix:///run/containerd/containerd.sock\ntimeout: 2\ndebug: false\n' > /s/cri/crictl.yaml
