set -eu
rm -rf /s/zlua /s/zlua-dirs && mkdir -p /s/zlua /s/zlua-dirs/projects /s/zlua-dirs/notes
printf '/s/zlua-dirs/notes|12|1790000000\n/s/zlua-dirs/projects|3|1790000100\n/root|40|1790000200\n' > /s/zlua/zlua.db
