set -eu
# A recipe directory with a two-section pantry; `cook pantry add` rewrites config/pantry.conf
# (lab 3: .pantry.conf.<pid>.tmp written O_TRUNC, fsync, renamed over the file).
rm -rf /s/cook && mkdir -p /s/cook/config
printf '[dairy]\nmilk = "1%%l"\nbutter = "200%%g"\n\n[pantry]\nflour = "1%%kg"\nsugar = "500%%g"\n' > /s/cook/config/pantry.conf
printf -- '---\nservings: 2\n---\nMix @flour{200%%g} with @milk{300%%ml} and @butter{50%%g}.\n' > /s/cook/Pancakes.cook
grep -q sugar /s/cook/config/pantry.conf
