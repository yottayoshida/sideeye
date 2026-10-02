set -eu
rm -rf /s/ormolu && mkdir -p /s/ormolu/proj && cd /s/ormolu/proj
printf "module A where\nf x=x+1\n" > A.hs
