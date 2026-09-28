set -eu
rm -rf /s/pg_format && mkdir -p /s/pg_format/proj && cd /s/pg_format/proj
printf 'select a,b from t where c=1;\n' > a.sql
