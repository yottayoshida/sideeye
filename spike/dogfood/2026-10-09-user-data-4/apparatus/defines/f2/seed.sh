set -eu
# Three photos to rename in one run. f2's undo record goes to $TMPDIR/f2/backups (lab 1),
# outside --state; the state is the directory whose names change.
rm -rf /s/f2 /s/aux/tmp/f2 /s/aux/home/.config/f2 && mkdir -p /s/f2
for i in 1 2 3; do printf 'photo %s: not a real jpeg, 64 bytes of text standing in for pixels......\n' $i > /s/f2/IMG_$i.jpg; done
[ -f /s/f2/IMG_3.jpg ]
# The checker, outside --state (the apparatus mount is read-only; the seed copies it executable).
install -m 755 /ap/defines/f2/check.sh /s/f2-check.sh
