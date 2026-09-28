set -eu
rm -rf /s/biome && mkdir -p /s/biome/proj && cd /s/biome/proj
printf 'const a = {b:1,c:2}\nfunction f( x ){return x+1}\n' > a.js
