set -eu
rm -rf /s/aux/home/.regctl /s/regctl-in && mkdir -p /s/aux/home/.regctl /s/regctl-in
printf '{\n  "hosts": {\n    "ghcr.io": {\n      "tls": "enabled",\n      "hostname": "ghcr.io",\n      "reqPerSec": 5,\n      "reqConcurrent": 3\n    }\n  }\n}\n' > /s/aux/home/.regctl/config.json
