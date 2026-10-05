set -eu
rm -rf /s/aux/home/.config/.wrangler /s/wrangler-in && mkdir -p /s/aux/home/.config/.wrangler /s/wrangler-in
printf '{\n  "permission": {\n    "enabled": true,\n    "date": "2026-09-01T00:00:00.000Z"\n  }\n}\n' > /s/aux/home/.config/.wrangler/metrics.json
