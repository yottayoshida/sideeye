set -eu
rm -rf /s/sheldon /s/sheldon-data /s/sheldon-in && mkdir -p /s/sheldon /s/sheldon-in
printf 'shell = "zsh"\n\n[plugins.base16]\ngithub = "chriskempson/base16-shell"\n' > /s/sheldon/plugins.toml
