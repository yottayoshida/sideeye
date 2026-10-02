#!/bin/sh
# The 2026-09-28 entry gate's engine question, asked of rumdl once as it was refused and once
# with --no-cache: `sideeye preflight --twice --oracle`, the exit code and the `next` sentence.
SE=$(cat /install.path)
for t in rumdl rumdl-nocache; do
    d=/ap/defines/$t
    sh "$d/seed.sh" || { echo "$t: seed failed"; continue; }
    echo "## $t: $(grep '^operation' "$d/sideeye.toml")"
    "$SE" preflight --twice --config "$d/sideeye.toml" --oracle /usr/bin/strace 2>&1
    echo "preflight exit $?"
    echo "state directory after: $(ls -A /s/rumdl/proj | tr '\n' ' ')"
done
