#!/bin/sh
# B-group selection for the #84 UNKNOWN-rate measurement — mechanical, no
# hand-picking (plan review P0-1: when the threshold's only basis is the
# B-group, a human choosing its members re-opens the gerrymandering the
# two-group split exists to close).
#
# Runs INSIDE the Debian bookworm container (needs apt-cache with fetched
# lists). Reads the archive's own debtags and applies a fixed predicate:
#
#   role::program
#   implemented-in:: one of c, c++, python, perl   (the supported language
#       classes per docs/target-classes.md — Rust/Go/Node/shell are not
#       classes with recorded verdicts)
#   works-with:: pim or db                          (the file-backed-state
#       family; this is the one deliberately biased choice, published as
#       such in docs/unknown-rate.md)
#   NOT interface::daemon, NOT interface::x11, NOT interface::graphical
#   name not matching ^lib / -dev$ / -doc$ / -common$
#
# minus the committed name exclusions (b-exclusions.txt: measured, tainted,
# sealed), then a deterministic sort, then the FIRST N. Whatever lands in
# the list is the list — a candidate that turns out to be undrivable or
# out of domain becomes a published funnel wall (docs/unknown-rate.md,
# rules W1-W3), never a silent substitution.
#
# Outputs (written beside this script, committed):
#   b-candidates.txt      the full filtered pool, sorted
#   b-targets.txt         the first N after exclusions — the frozen B-group
#   b-selection-record.txt  apt release identity of the lists the selection read
set -eu

N=${N:-20}
here=$(cd "$(dirname "$0")" && pwd)
excl="$here/b-exclusions.txt"
[ -f "$excl" ] || { echo "select-b: $excl missing" >&2; exit 2; }

command -v apt-cache >/dev/null || { echo "select-b: apt-cache not found (run inside the container)" >&2; exit 2; }

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
  if(t !~ /,implemented-in::(c|c\+\+|python|perl),/) next
  if(t !~ /,works-with::(pim|db),/) next
  if(t ~ /,interface::daemon,/) next
  if(t ~ /,interface::(x11|graphical),/) next
  if(p ~ /^lib/ || p ~ /-(dev|doc|common)$/) next
  print p
}' | sort -u > "$here/b-candidates.txt"

pool=$(wc -l < "$here/b-candidates.txt" | tr -d ' ')
[ "$pool" -gt 0 ] || { echo "select-b: empty candidate pool — predicate or apt lists broken" >&2; exit 2; }

# Name exclusions: exact package-name match on field 1 of b-exclusions.txt.
awk -F"\t" 'NR==FNR { if($0 !~ /^#/ && NF>=1 && $1!="") excl[$1]=1; next }
            !($0 in excl)' "$excl" "$here/b-candidates.txt" \
  | head -n "$N" > "$here/b-targets.txt"

got=$(wc -l < "$here/b-targets.txt" | tr -d ' ')
[ "$got" -eq "$N" ] || { echo "select-b: expected $N targets, got $got — pool too small after exclusions" >&2; exit 2; }

{
  echo "generated: select-b.sh (N=$N)"
  echo "pool after predicate: $pool packages"
  echo "apt release identity of the lists read:"
  apt-cache policy 2>/dev/null | sed -n '/^ /p' | sort -u
} > "$here/b-selection-record.txt"

echo "select-b: wrote b-candidates.txt ($pool), b-targets.txt ($got), b-selection-record.txt"
