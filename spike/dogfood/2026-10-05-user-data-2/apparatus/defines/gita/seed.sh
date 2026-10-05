set -eu
rm -rf /s/gita /s/gita-in /s/repos && mkdir -p /s/gita/gita /s/gita-in /s/repos/a/.git /s/repos/b/.git
printf '/s/repos/a,a,,\n/s/repos/b,b,,\n' > /s/gita/gita/repos.csv
printf 'work:a b:\n' > /s/gita/gita/groups.csv
