#!/bin/sh
# .git/index is scratch: it caches the work tree's file times, which the restore does not rebuild,
# so two clean runs leave it different (transcripts/explore/git-nogc). This judges the repository
# through git: fsck is clean, HEAD is the third commit or the new one, and the staged change to f1.txt
# is in the work tree.
G="$SIDEEYE_STATE_DIR"
git -C "$G" fsck --no-dangling > /tmp/fsck.txt 2>&1 || { echo "git fsck fails: $(tail -1 /tmp/fsck.txt | cut -c1-120)"; exit 1; }
s=$(git -C "$G" log -1 --format=%s 2>&1)
case "$s" in c3|second) ;; *) echo "HEAD's subject is '$s'"; exit 1 ;; esac
grep -q '^change$' "$G/f1.txt" || { echo "f1.txt lost its change"; exit 1; }
exit 0
