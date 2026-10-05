set -eu
rm -rf /s/aux/home/.gemini /s/gemini-in && mkdir -p /s/aux/home/.gemini /s/gemini-in
printf '{\n  "theme": "Default",\n  "mcpServers": {\n    "docs": {"command": "docs-server"}\n  }\n}\n' > /s/aux/home/.gemini/settings.json
