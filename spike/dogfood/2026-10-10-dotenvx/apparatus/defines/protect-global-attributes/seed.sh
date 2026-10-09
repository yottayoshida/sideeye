set -eu
rm -rf /s/repo /s/xdg && git init -q /s/repo && mkdir -p /s/xdg/git && : > "$HOME/.gitconfig"
printf '*.png binary\n*.lockb binary diff=lockb\n.env* filter=dotenvx\n*.env filter=dotenvx\n.flaskenv filter=dotenvx\n.dev.vars* filter=dotenvx\n**/.env.d/* filter=dotenvx\n' > /s/xdg/git/attributes
