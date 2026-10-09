#!/bin/sh
# database.sqlite and log.txt are scratch (ids and timestamps differ in every run); this judges the
# notebook through joplin: it opens the profile and lists SeedNote, with or without SecondNote.
out=$(joplin --profile "$SIDEEYE_STATE_DIR" ls TestBook 2>&1) || { echo "joplin cannot list the notebook: $(echo "$out" | tail -1 | cut -c1-100)"; exit 1; }
echo "$out" | grep -q SeedNote || { echo "SeedNote is gone: $(echo "$out" | tr '\n' ' ' | cut -c1-100)"; exit 1; }
exit 0
