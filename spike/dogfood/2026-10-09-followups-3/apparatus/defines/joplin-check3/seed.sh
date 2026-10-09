set -eu
# The seed of 2026-09-13 (preflight-main.sh): a profile holding one notebook and one note, made by
# joplin itself. The operation adds a second note to it.
rm -rf /s/joplin && mkdir -p /s/joplin/jp
joplin --profile /s/joplin/jp mkbook TestBook
joplin --profile /s/joplin/jp use TestBook
joplin --profile /s/joplin/jp mknote SeedNote
