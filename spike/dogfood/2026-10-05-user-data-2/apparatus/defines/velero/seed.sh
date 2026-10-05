set -eu
rm -rf /s/aux/home/.config/velero /s/velero-in && mkdir -p /s/aux/home/.config/velero /s/velero-in
printf '{"features":"EnableCSI","namespace":"velero","colorized":"false"}\n' > /s/aux/home/.config/velero/config.json
