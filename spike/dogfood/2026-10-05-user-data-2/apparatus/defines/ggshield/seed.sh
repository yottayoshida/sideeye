set -eu
rm -rf /s/gg /s/gg-in && mkdir -p /s/gg /s/gg-in
printf 'version: 2\ninstance: https://dashboard.gitguardian.example\nexit_zero: false\n' > /s/gg/.gitguardian.yaml
