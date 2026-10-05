#!/bin/sh
# Plain runs: k8sgpt's backends, ggshield's config, uv's credential store.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 120 "$@" </dev/null 2>&1 | tail -${TAILN:-10}; echo "rc=$?"; }
sum() { find "$1" -type f -exec sha256sum {} \; 2>/dev/null | cut -c1-12,65- | sort -k2; }
x k8sgpt auth add --backend openai --model gpt-4o --password sk-test-aaaa
x k8sgpt auth add --backend localai --model llama --baseurl http://localhost:8080/v1
sum /s/aux/home/.config/k8sgpt; cat /s/aux/home/.config/k8sgpt/k8sgpt.yaml
x k8sgpt auth default --provider localai
x k8sgpt auth remove --backends openai
sum /s/aux/home/.config/k8sgpt; cat /s/aux/home/.config/k8sgpt/k8sgpt.yaml
TAILN=20 x ggshield config --help
x ggshield config set instance https://dashboard.gitguardian.example
x ggshield config set default_token_lifetime 30
find /s/aux -path '*gitguardian*' -type f -exec sh -c 'echo "== {}"; cat {}' \; ; find /s/aux/home -maxdepth 2 -name '*.yaml' -newer /etc/hostname 2>/dev/null
TAILN=20 x /opt/py/bin/uv auth --help
x /opt/py/bin/uv auth login https://pkgs.example.internal/simple --username alice --password pw1
find /s/aux -path '*uv*' -name '*.toml' -exec sh -c 'echo "== {}"; cat {}' \;
