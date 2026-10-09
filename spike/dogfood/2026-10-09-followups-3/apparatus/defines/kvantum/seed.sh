set -eu
# A Kvantum config naming one theme; `--set` rewrites it through Qt's QSettings (lab 10: a lock
# file, a temporary name, rename).
rm -rf /s/aux/home/.config/Kvantum /s/kv && mkdir -p /s/kv /s/aux/home/.config/Kvantum
printf '[General]\ntheme=KvArc\n\n[Applications]\nKvFlat=okular, konsole\n' > /s/aux/home/.config/Kvantum/kvantum.kvconfig
grep -q KvArc /s/aux/home/.config/Kvantum/kvantum.kvconfig
