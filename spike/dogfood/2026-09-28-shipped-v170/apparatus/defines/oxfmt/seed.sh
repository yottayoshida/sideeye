set -eu
rm -rf /s/oxfmt && mkdir -p /s/oxfmt/proj && cd /s/oxfmt/proj
printf 'const a = {b:1,c:2}\nfunction f( x ){return x+1}\n' > a.js
