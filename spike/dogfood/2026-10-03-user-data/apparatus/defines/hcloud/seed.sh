set -eu
rm -rf /s/hcloud && mkdir -p /s/hcloud
printf 'active_context = "home"\n\n[[contexts]]\n  name = "home"\n  token = "placeholder-home-credential"\n\n[[contexts]]\n  name = "work"\n  token = "placeholder-work-credential"\n' > /s/hcloud/cli.toml
