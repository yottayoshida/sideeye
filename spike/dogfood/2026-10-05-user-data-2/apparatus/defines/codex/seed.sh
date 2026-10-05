set -eu
rm -rf /s/codex /s/codex-in && mkdir -p /s/codex /s/codex-in
printf 'model = "o3"\n\n[mcp_servers.docs]\ncommand = "docs-server"\n' > /s/codex/config.toml
