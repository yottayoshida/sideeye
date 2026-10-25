#!/bin/sh
# keep-cases.sh for set 3's own targets only: the four sets share transcripts/explore, and moving another
# set's work directory while its explore runs would take the state out from under it.
#   sh keep-cases-s3.sh <explore dir> <destination outside the repository>
set -eu
src=$1; dst=$2; n=0
for t in sysusers vagrant vagrant-live freshrss salt-grains vcpkg-s3 wallabag wallabag-l0; do
    for w in "$src/$t"/work-*; do
        [ -d "$w" ] || continue
        lab=${w##*/work-}
        for c in "$w"/cases/*.json; do
            [ -f "$c" ] || continue
            cp "$c" "$src/$t/case-$lab.json"; n=$((n + 1))
        done
        mkdir -p "$dst/$t"
        mv "$w" "$dst/$t/"
    done
done
echo "cases kept: $n; work directories moved to $dst"
