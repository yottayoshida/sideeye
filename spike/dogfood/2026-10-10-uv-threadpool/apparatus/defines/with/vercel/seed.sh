set -eu
rm -rf /s/vercel /s/vercel-in && mkdir -p /s/vercel /s/vercel-in
printf '{\n  "// Note": "This is your Vercel config file.",\n  "telemetry": {\n    "enabled": true\n  }\n}\n' > /s/vercel/config.json
