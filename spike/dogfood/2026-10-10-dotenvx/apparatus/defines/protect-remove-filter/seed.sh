set -eu
rm -rf /s/repo /s/xdg && git init -q /s/repo && mkdir -p /s/xdg/git && : > "$HOME/.gitconfig"
printf '*.png binary\n*.lockb binary diff=lockb\n' > /s/xdg/git/attributes
cd /s/repo && dotenvx protect > /s/seed-dotenvx.log 2>&1
grep -q 'filter=dotenvx.protect' /s/xdg/git/attributes
