set -eu
rm -rf /s/ctl && mkdir -p /s/ctl
printf '{"key": "init"}\n' > /s/ctl/key.json
