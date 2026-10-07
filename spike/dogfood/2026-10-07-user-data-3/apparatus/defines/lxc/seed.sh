set -eu
rm -rf /s/aux/home/.config/lxc /s/lxc-in && mkdir -p /s/lxc-in
lxc alias add l1 list > /s/lxc-in/seed.log 2>&1
lxc alias add l2 info >> /s/lxc-in/seed.log 2>&1
lxc alias add l3 exec >> /s/lxc-in/seed.log 2>&1
grep -q l1 /s/aux/home/.config/lxc/config.yml
