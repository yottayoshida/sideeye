set -eu
rm -rf /s/aux/home/.gemini /s/gemini-in && mkdir -p /s/aux/home/.gemini /s/gemini-in/.gemini
# Trusted, so the project settings are read before the write (an untrusted folder has them wiped: gemini-cli #29465).
printf '{"/s/gemini-in": "TRUST_FOLDER"}\n' > /s/aux/home/.gemini/trustedFolders.json
printf '{\n  "theme": "Default",\n  "mcpServers": {\n    "docs": {"command": "docs-server"}\n  }\n}\n' > /s/gemini-in/.gemini/settings.json
