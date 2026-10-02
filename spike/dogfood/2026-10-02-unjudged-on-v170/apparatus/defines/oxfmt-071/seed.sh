set -eu
rm -rf /s/oxfmt-071 && mkdir -p /s/oxfmt-071/proj && cd /s/oxfmt-071/proj
printf 'const a = {b:1,c:2}\nfunction f( x ){return x+1}\n' > a.js
