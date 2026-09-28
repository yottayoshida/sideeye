set -eu
rm -rf /s/sqruff && mkdir -p /s/sqruff/proj && cd /s/sqruff/proj
printf 'SELECT a,b   FROM t\nwhere  c=1\n' > a.sql
