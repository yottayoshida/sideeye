# aspiers/stow#139, the report's steps with S=/work/s.
S=/work/s
mkdir -p "$S/stowdir/A/sub" "$S/stowdir/B/sub" "$S/target"
echo grace-content > "$S/stowdir/A/sub/grace.txt"
echo ada-content   > "$S/stowdir/B/sub/ada.txt"
stow -d "$S/stowdir" -t "$S/target" -S A
ls -l "$S/target" | tail -n +2
cat "$S/target/sub/grace.txt"
strace -f -qq -e trace=mkdirat,mkdir -e inject=mkdirat:signal=KILL:when=1 stow -d "$S/stowdir" -t "$S/target" -S B; echo "exit $?"
ls -A "$S/target"
cat "$S/target/sub/grace.txt"
