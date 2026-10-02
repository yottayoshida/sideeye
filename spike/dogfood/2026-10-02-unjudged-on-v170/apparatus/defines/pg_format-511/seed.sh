set -eu
rm -rf /s/pg_format-511 && mkdir -p /s/pg_format-511/proj && cd /s/pg_format-511/proj
printf 'select a,b from t where c=1;\n' > a.sql
