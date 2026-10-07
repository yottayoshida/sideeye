set -eu
rm -rf /s/alac /s/alac-in && mkdir -p /s/alac /s/alac-in
printf '# my terminal, set up by hand\nlive_config_reload = true\nimport = ["/s/alac/colors.toml"]\n\n[shell]\nprogram = "/bin/bash"\nargs = ["-l"]\n\n[font]\nsize = 13.0\n' > /s/alac/alacritty.toml
printf 'live_config_reload = false\n\n[colors.primary]\nbackground = "#1d1f21"\nforeground = "#c5c8c6"\n' > /s/alac/colors.toml
grep -q '^\[shell\]' /s/alac/alacritty.toml
