set -eu
rm -rf /s/repo /s/xdg && git init -q /s/repo && mkdir -p /s/xdg/git && : > "$GIT_CONFIG_GLOBAL"
printf '*.log\n.DS_Store\n.idea/\n.env.keys*\n' > /s/xdg/git/ignore
git config --global core.excludesFile /s/xdg/git/ignore
git config --global dotenvx.protect.ignoreFile /s/xdg/git/ignore
