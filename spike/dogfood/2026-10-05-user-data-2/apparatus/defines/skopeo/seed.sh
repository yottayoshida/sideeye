set -eu
rm -rf /s/sk /s/sk-in && mkdir -p /s/sk /s/sk-in
printf '%s\n' '{"auths":{"registry.example.com":{"auth":"YWxpY2U6c2VjcmV0"},"ghcr.io":{"auth":"Ym9iOnRva2Vu"},"quay.io":{"auth":"Y2Fyb2w6cHc="}}}' > /s/sk/auth.json
