#!/bin/sh
# B2 selection for the #619 fresh-target re-measurement — mechanical, no
# hand-picking: the discipline of select-b.sh with three things changed
# (ADR 0073). The archive is Debian 13 trixie rather than bookworm; the
# predicate asks for a state-changing command-line program in a language the
# first table of docs/target-classes.md is written in, rather than the
# works-with::pim|db family that sent nine of the first twenty to a W2 wall;
# and the order is a keyed hash rather than the alphabet.
#
# Runs INSIDE the debian:trixie-slim container (needs apt-cache with fetched
# lists). Reads the archive's own debtags and applies a fixed predicate:
#
#   role::program
#   implemented-in:: one of c, c++, python, perl, ruby, php, haskell, java,
#       ecmascript  (the languages a first-table row is written in;
#       implemented-in::rust does not exist in trixie's vocabulary, so Rust
#       is out of this predicate's reach and docs/unknown-rate.md says so)
#   use:: one of editing, converting, compressing, organizing, storing,
#       synchronizing  (a program that changes something)
#   works-with:: one of file, text, db, pim, mail, archive, image,
#       image:raster, image:vector, software:source, software:package, vcs,
#       logfile, font, dictionary, spreadsheet, calendar, audio, video
#       (something a program can keep in a file)
#   interface::commandline
#   NOT interface::daemon, NOT interface::x11, NOT interface::graphical,
#   NOT interface::web
#   name not matching ^lib / -dev$ / -doc$ / -common$ / -dbg$
#
# The pool is written alphabetically (b2-candidates.txt); then every member
# is ranked by sha256("<package>\t<key>") with the key from b2-order-key.txt,
# the committed name exclusions (b2-exclusions.txt) are removed, and the FIRST
# N of what remains is the group. Whatever lands in the list is the list — a
# candidate that turns out to be undrivable, out of domain, or already met by
# this project under another name becomes a published funnel wall
# (docs/unknown-rate.md, rules W0-W3), never a silent substitution.
#
# N is 30: at least the 20 the issue asks for, and enough that the explored
# count is not expected to fall to single digits at the first pool's funnel
# rate (7 of 20 reached an explore). That is an expectation, not a
# measurement; the funnel table is where it is measured.
#
# Outputs (written beside this script, committed):
#   b2-candidates.txt        the full filtered pool, alphabetical
#   b2-targets.txt           the first N of the keyed order after exclusions
#   b2-selection-record.txt  apt release identity of the lists read, the pool
#                            size, the key, and the keyed head with its hashes
set -eu

N=${N:-30}
here=$(cd "$(dirname "$0")" && pwd)
excl="$here/b2-exclusions.txt"
keyf="$here/b2-order-key.txt"
[ -f "$excl" ] || { echo "select-b2: $excl missing" >&2; exit 2; }
[ -f "$keyf" ] || { echo "select-b2: $keyf missing" >&2; exit 2; }
key=$(grep -v '^#' "$keyf" | grep . | head -n 1)
[ -n "$key" ] || { echo "select-b2: $keyf carries no key" >&2; exit 2; }

command -v apt-cache >/dev/null || { echo "select-b2: apt-cache not found (run inside the container)" >&2; exit 2; }
command -v sha256sum >/dev/null || { echo "select-b2: sha256sum not found" >&2; exit 2; }

apt-cache dumpavail | awk '
BEGIN{RS=""; FS="\n"}
{
  pkg=""; tags=""; intag=0
  for(i=1;i<=NF;i++){
    l=$i
    if(l ~ /^Package: /){pkg=substr(l,10)}
    if(l ~ /^Tag: /){intag=1; tags=tags substr(l,6); continue}
    if(intag){ if(l ~ /^ /){tags=tags l} else {intag=0} }
  }
  if(pkg!="" && tags!="") print pkg "\t" tags
}' | awk -F"\t" '
{
  p=$1; t=","$2","; gsub(/ /,"",t)
  if(t !~ /,role::program,/) next
  if(t !~ /,implemented-in::(c|c\+\+|python|perl|ruby|php|haskell|java|ecmascript),/) next
  if(t !~ /,use::(editing|converting|compressing|organizing|storing|synchronizing),/) next
  if(t !~ /,works-with::(file|text|db|pim|mail|archive|image|image:raster|image:vector|software:source|software:package|vcs|logfile|font|dictionary|spreadsheet|calendar|audio|video),/) next
  if(t !~ /,interface::commandline,/) next
  if(t ~ /,interface::(daemon|x11|graphical|web),/) next
  if(p ~ /^lib/ || p ~ /-(dev|doc|common|dbg)$/) next
  print p
}' | LC_ALL=C sort -u > "$here/b2-candidates.txt"

pool=$(wc -l < "$here/b2-candidates.txt" | tr -d ' ')
[ "$pool" -gt 0 ] || { echo "select-b2: empty candidate pool — predicate or apt lists broken" >&2; exit 2; }

# The keyed order: one hash per candidate, sorted by hash and then by name
# (the name only decides a tie the hash does not produce in practice). C
# collation, so the shell and count.py's Python sort the same bytes the same way.
ordered=$here/.b2-ordered.tmp
: > "$ordered"
while IFS= read -r p; do
    h=$(printf '%s\t%s' "$p" "$key" | sha256sum | cut -d' ' -f1)
    printf '%s\t%s\n' "$h" "$p" >> "$ordered"
done < "$here/b2-candidates.txt"
LC_ALL=C sort -k1,1 -k2,2 -o "$ordered" "$ordered"

# Name exclusions: exact package-name match on field 1 of b2-exclusions.txt.
# The head of what remains is computed once and written twice — the names as
# the group, the names with their hashes as the record.
head=$here/.b2-head.tmp
awk -F"\t" 'NR==FNR { if($0 !~ /^#/ && NF>=1 && $1!="") excl[$1]=1; next }
            !($2 in excl)' "$excl" "$ordered" | head -n "$N" > "$head"
cut -f2 "$head" > "$here/b2-targets.txt"

got=$(wc -l < "$here/b2-targets.txt" | tr -d ' ')
[ "$got" -eq "$N" ] || { echo "select-b2: expected $N targets, got $got — pool too small after exclusions" >&2; exit 2; }

{
  echo "generated: select-b2.sh (N=$N)"
  echo "pool after predicate: $pool packages"
  echo "order key: $key"
  echo "apt release identity of the lists read:"
  apt-cache policy 2>/dev/null | sed -n '/^ /p' | sort -u
  echo "keyed order, first $N after exclusions (hash  package):"
  awk -F"\t" '{ print "  " $1 "  " $2 }' "$head"
} > "$here/b2-selection-record.txt"
rm -f "$ordered" "$head"

echo "select-b2: wrote b2-candidates.txt ($pool), b2-targets.txt ($got), b2-selection-record.txt"
