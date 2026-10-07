#!/bin/sh
# Lab 9 (2026-10-07 user-data-3): the last candidates by hand in the box, stdin at EOF.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1007 sh /ap/lab-9.sh > transcripts/lab-9.txt 2>&1
set -u
. /ap/env.sh
show() { echo "\$ $*"; "$@" < /dev/null > /tmp/show.out 2>&1; rc=$?; sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' /tmp/show.out | tr -cd '\11\12\40-\176' | head -10 | cut -c1-160; echo "  -> exit $rc"; }
digest() { (cd "$1" 2>/dev/null && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-12); }
kind() { f=$(command -v "$1" 2>/dev/null || echo "$1"); echo "  image: $f: $(file -L "$f" | sed 's/^[^:]*: //' | cut -c1-110)"; }

echo "=== alacritty migrate"
kind alacritty
d=/s/alac; rm -rf $d; mkdir -p $d
printf 'live_config_reload = true\nimport = ["/s/alac/colors.toml"]\n\n[shell]\nprogram = "/bin/bash"\nargs = ["-l"]\n\n[font]\nsize = 13.0\n' > $d/alacritty.toml
printf '[colors.primary]\nbackground = "#1d1f21"\n' > $d/colors.toml
b=$(digest $d); show alacritty migrate -c /s/alac/alacritty.toml; echo "  state: $b -> $(digest $d)"; ls -la $d | tail -n +2; cat $d/alacritty.toml

echo "=== goaccess --persist --restore"
kind goaccess
d=/s/goa; rm -rf $d /s/goa-in; mkdir -p $d/db /s/goa-in
i=0; while [ $i -lt 30 ]; do echo "10.0.0.$((i%7)) - - [07/Oct/2026:10:$((10+i%50)):00 +0000] \"GET /page$((i%5)) HTTP/1.1\" 200 $((100+i)) \"-\" \"curl/8\""; i=$((i+1)); done > /s/goa-in/a.log
i=0; while [ $i -lt 20 ]; do echo "10.0.1.$((i%3)) - - [07/Oct/2026:11:$((10+i%50)):00 +0000] \"GET /other$((i%4)) HTTP/1.1\" 404 $((50+i)) \"-\" \"curl/8\""; i=$((i+1)); done > /s/goa-in/b.log
show goaccess /s/goa-in/a.log --log-format=COMBINED --persist --db-path=/s/goa/db -o /s/goa-in/a.html; ls -la $d/db | tail -n +2 | head -8; ls $d/db | wc -l
b=$(digest $d/db); show goaccess /s/goa-in/b.log --log-format=COMBINED --persist --restore --db-path=/s/goa/db -o /s/goa-in/b.html; echo "  state: $b -> $(digest $d/db)"

echo "=== ostree config set / remote add"
kind ostree
d=/s/ost; rm -rf $d; mkdir -p $d
show ostree --repo=/s/ost/repo init --mode=archive; cat $d/repo/config
b=$(digest $d/repo); show ostree --repo=/s/ost/repo config set core.min-free-space-percent 5; echo "  state: $b -> $(digest $d/repo)"
b=$(digest $d/repo); show ostree --repo=/s/ost/repo remote add --no-gpg-verify origin https://example.invalid/repo; echo "  state: $b -> $(digest $d/repo)"; cat $d/repo/config

echo "=== gitmoji -i over a hand-written hook"
kind node
d=/s/gm; rm -rf $d; mkdir -p $d; cd $d; git init -q .
printf '#!/bin/sh\n# my own prepare-commit-msg hook, written by hand\necho "[ticket] $(cat "$1")" > "$1"\n' > .git/hooks/prepare-commit-msg; chmod 755 .git/hooks/prepare-commit-msg
b=$(digest $d/.git/hooks); show gitmoji -i; echo "  hooks: $b -> $(digest $d/.git/hooks)"; ls -la .git/hooks | grep -v sample; head -3 .git/hooks/prepare-commit-msg

echo "=== capacitor telemetry off / astro preferences"
( export PATH=/opt/node22/bin:$PATH ASTRO_TELEMETRY_DISABLED=1
  kind cap
  b=$(digest $HOME); show cap telemetry off; echo "  home: $b -> $(digest $HOME)"; find $HOME -newer /tmp/show.out -o -path '*capacitor*' -type f 2>/dev/null | grep -i capac | head
  show cap telemetry on; find $HOME $XDG_STATE_HOME $XDG_DATA_HOME -path '*apacitor*' -type f 2>/dev/null | head
  show astro preferences disable devToolbar --global; find $HOME $XDG_STATE_HOME $XDG_DATA_HOME -path '*astro*' -type f 2>/dev/null | head
  c=$(find $HOME -path '*astro*' -name '*.json' 2>/dev/null | head -1); [ -n "$c" ] && { b=$(sha256sum "$c" | cut -c1-12); show astro preferences enable devToolbar --global; echo "  $c: $b -> $(sha256sum "$c" | cut -c1-12)"; cat "$c"; } )
