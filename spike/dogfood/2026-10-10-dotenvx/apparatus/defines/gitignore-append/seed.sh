set -eu
rm -rf /s/proj && mkdir -p /s/proj && cd /s/proj
printf 'node_modules/\ndist/\n' > .gitignore
