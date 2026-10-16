#!/bin/sh
# Builds the valid starting state in $SIDEEYE_STATE_DIR: a source tree with two
# pristine files and patches/series naming two patches, nothing applied (no .pc).
set -eu
S=${SIDEEYE_STATE_DIR:?}
mkdir -p "$S/patches"
printf "alpha one\nalpha two\nalpha three\n" > "$S/a.txt"
printf "beta one\nbeta two\nbeta three\n" > "$S/b.txt"
printf "p1.diff\np2.diff\n" > "$S/patches/series"
cat > "$S/patches/p1.diff" <<P1
Change the second line of a.txt.

--- a/a.txt
+++ b/a.txt
@@ -1,3 +1,3 @@
 alpha one
-alpha two
+alpha TWO patched
 alpha three
P1
cat > "$S/patches/p2.diff" <<P2
Change the second line of b.txt.

--- a/b.txt
+++ b/b.txt
@@ -1,3 +1,3 @@
 beta one
-beta two
+beta TWO patched
 beta three
P2
