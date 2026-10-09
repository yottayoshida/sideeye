set -eu
rm -rf /s/prettier && mkdir -p /s/prettier/state
printf 'const   a = {b:1,\n c : [1,2,3]}\nfunction f( x ){return x*2}\nconsole.log( f(a.b) )\n' > /s/prettier/state/a.js
