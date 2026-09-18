#!/bin/sh
# The first step of authoring a B2 define (#619): what the protocol reads
# before anything is written, gathered in one place so the record of each
# target starts the same way. Run on the HOST from the repo; the container
# part needs the sideeye-ur-b2 image (Dockerfile.b2, apt lists kept).
#
#   1. the clock's setup_started, once
#   2. freshness: every tracked file naming the package (word match), so a
#      target this project already met under this name becomes wall W0 and not
#      a define — the alias table is written from memory and this is the check
#      on it. Hits under spike/unknown-rate/b2-* are the selection itself.
#   3. in a fresh container: does the package install (wall W1 if not), which
#      binaries and manual pages it ships, and the first screens of each
#      binary's manual and --help — the documentation the define must be read
#      from (walls W2 and W3 are quoted from it)
#
# Output goes to $HOME/.cctmp/b2-author/<target>.txt for the author to read;
# nothing here decides anything.
#
# Usage: b2-author.sh <package>
set -u
t=${1:?package}
here=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$here/../.." && pwd)
out=$HOME/.cctmp/b2-author
mkdir -p "$out" || exit 2
log=$out/$t.txt

sh "$here/b2-clock.sh" "$t" setup_started >/dev/null

{
  echo "== $t — authoring probe $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "== freshness: tracked files naming '$t' (word match), the selection's own files last"
  hits=$(git -C "$ROOT" grep -l -w -- "$t")
  printf '%s\n' "$hits" | grep -v '^spike/unknown-rate/b2-' | grep . || echo "(no tracked file outside the selection names it)"
  printf '%s\n' "$hits" | grep '^spike/unknown-rate/b2-' | sed 's/^/  selection: /'
  echo
  echo "== container: install, files, manuals"
  docker run --rm sideeye-ur-b2 sh -c '
    t="$1"
    if ! apt-get install -y --no-install-recommends "$t" >/tmp/install.log 2>&1; then
        echo "INSTALL FAILED rc=$? (wall W1 candidate):"; tail -n 8 /tmp/install.log; exit 0
    fi
    echo "installed: $(dpkg-query -W -f="\${Package} \${Version}" "$t")"
    echo "-- binaries:"; dpkg -L "$t" | grep -E "/(s?bin|games)/" || echo "(none)"
    echo "-- manual pages:"; dpkg -L "$t" | grep -E "/man/man[0-9]/" || echo "(none)"
    echo "-- description:"; apt-cache show "$t" 2>/dev/null | sed -n "/^Description/,/^[A-Z]/p" | head -n 20
    echo "-- tags:"; apt-cache show "$t" 2>/dev/null | grep "^Tag:" | head -n 3
    for b in $(dpkg -L "$t" | grep -E "/(s?bin|games)/" | head -n 6); do
        n=$(basename "$b")
        echo; echo "==== $n: manual (first 120 lines)"
        MANPAGER=cat man "$n" 2>/dev/null | col -b | head -n 120 || true
        echo "==== $n --help (first 60 lines)"
        "$b" --help 2>&1 | head -n 60 || true
    done
  ' sh "$t"
} > "$log" 2>&1
echo "$log"
wc -l < "$log" | tr -d ' ' | sed 's/^/lines: /'
