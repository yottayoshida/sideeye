set -eu
rm -rf /s/jsonnetfmt && mkdir -p /s/jsonnetfmt/proj && cd /s/jsonnetfmt/proj
printf '{a:1,\n  "b":   [1,2,3],\n    c: {d: "x"}}\n' > a.jsonnet
