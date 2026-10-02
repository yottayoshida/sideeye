set -eu
rm -rf /s/yamlfmt && mkdir -p /s/yamlfmt/proj && cd /s/yamlfmt/proj
printf 'a:   1\nb:\n    - x\n    -   y\nc: {d: 2,   e: 3}\n' > a.yaml
