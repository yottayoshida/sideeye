set -eu
rm -rf /s/doctl && mkdir -p /s/doctl
printf 'access-token: placeholder-default-credential\ncontext: default\nauth-contexts:\n  work: placeholder-work-credential\n' > /s/doctl/config.yaml
